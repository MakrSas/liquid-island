import AppKit
import CoreAudio
import AudioToolbox
import Accelerate
import Combine

/// Реальные уровни звука по частотным полосам.
///
/// Слушаем системный выход через process tap (macOS 14.2+): создаём отвод,
/// заворачиваем его в приватное агрегатное устройство и снимаем с него кадры.
/// Дальше окно Ханна, БПФ и разбивка на полосы — то, что видит эквалайзер.
///
/// Системе для этого нужно разрешение на запись звука; пока его нет, монитор
/// молча не запускается, и остров рисует спокойную волну по таймеру.
/// Отвод системного звука.
///
/// Живёт вне главного актора намеренно: блок ввода-вывода вызывается с
/// реального аудио-потока, и любая изоляция там роняет процесс.
final class AudioTapSession: @unchecked Sendable {
    /// Последние отсчёты моно-микса, кольцом.
    let samples: Guarded<[Float]>
    /// Сколько раз система отдала нам кадры — для диагностики.
    let callbackCount = Guarded(0)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let frameCount: Int
    /// Какие процессы слушаем. Пусто — весь выход системы.
    private let processes: [AudioObjectID]

    init(frameCount: Int, processes: [AudioObjectID] = []) {
        self.frameCount = frameCount
        self.processes = processes
        samples = Guarded([Float](repeating: 0, count: frameCount))
    }

    deinit { stop() }

    func start() -> Bool {
        guard createTap(), createAggregate(), startIO() else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func createTap() -> Bool {
        // Отвод либо на весь выход, либо на конкретные процессы. Второе нужно,
        // чтобы отличать «это приложение играет» от «где-то в системе есть
        // звук»: без разделения браузер на фоне выдаётся за плеер на паузе.
        let description = processes.isEmpty
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            : CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "LiquidIsland"
        description.isPrivate = true
        // Отвод не должен глушить звук — мы только слушаем.
        description.muteBehavior = .unmuted
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr else {
            log("создание отвода не удалось", status)
            return false
        }
        tapID = id
        return true
    }

    private func createAggregate() -> Bool {
        guard let outputUID = defaultOutputDeviceUID(), let tapUID = tapUUID() else { return false }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LiquidIsland Levels",
            kAudioAggregateDeviceUIDKey: "app.liquidisland.levels",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]]
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else {
            log("агрегатное устройство не создалось", status)
            return false
        }
        aggregateID = id
        return true
    }

    private func startIO() -> Bool {
        let store = samples
        let self_callbacks = callbackCount
        let capacity = frameCount
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
            @Sendable _, inputData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData)
            )
            guard let first = list.first, let data = first.mData else { return }
            let channels = Int(first.mNumberChannels)
            let total = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard total > 0, channels > 0 else { return }
            let pointer = data.assumingMemoryBound(to: Float.self)
            let frames = total / channels
            let take = min(frames, capacity)

            self_callbacks.withLock { $0 += 1 }
            store.withLock { buffer in
                // Сдвигаем окно и дописываем свежие отсчёты в конец.
                if take < capacity { buffer.removeFirst(take) }
                else { buffer.removeAll(keepingCapacity: true) }
                for index in 0..<take {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += pointer[(frames - take + index) * channels + channel]
                    }
                    buffer.append(sum / Float(channels))
                }
            }
        }
        guard status == noErr, let procID else {
            log("IOProc не создан", status)
            return false
        }
        ioProcID = procID
        let started = AudioDeviceStart(aggregateID, procID)
        if started != noErr { log("устройство не запустилось", started) }
        return started == noErr
    }

    /// Ошибки Core Audio приходят кодами-четырёхбуквенниками — печатаем их
    /// читаемо, иначе разбираться невозможно.
    private func log(_ message: String, _ status: OSStatus) {
        guard ProcessInfo.processInfo.environment["LIQUID_ISLAND_DEBUG"] == "1"
                || ProcessInfo.processInfo.environment["LIQUID_ISLAND_TAP_TEST"] == "1"
        else { return }
        let bytes = [24, 16, 8, 0].map { UInt8((status >> $0) & 0xFF) }
        let code = String(bytes: bytes, encoding: .ascii) ?? "\(status)"
        print("отвод: \(message) — \(status) '\(code)'")
    }

    private func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString? = nil
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &uidSize, &uid) == noErr
        else { return nil }
        return uid as String?
    }

    private func tapUUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uid) == noErr
        else { return nil }
        return uid as String?
    }
}

@MainActor
final class AudioLevels: ObservableObject {
    /// Уровни полос, 0…1, слева направо от низов к верхам.
    @Published private(set) var bands: [Float] = []
    @Published private(set) var isRunning = false
    /// Идёт ли сейчас звук на самом деле.
    ///
    /// Приложение может держать выход открытым, стоя на паузе, — по одному
    /// факту открытого выхода нельзя судить, играет ли что-то. Здесь смотрим
    /// на сам сигнал.
    @Published private(set) var hasSignal = false

    private let bandCount: Int
    private let fftSize = 1024
    private var session: AudioTapSession?
    private var fftSetup: vDSP.FFT<DSPSplitComplex>?
    private var window: [Float] = []
    /// Сглаженные значения: без них полосы дёргаются кадр в кадр.
    private var smoothed: [Float]
    private var displayTimer: Timer?
    /// Пока разрешение на запись звука не выдано, система честно отдаёт кадры,
    /// но заполненные тишиной. Считаем такие подряд и, не дождавшись сигнала,
    /// отдаём пустые полосы — остров тогда рисует свою волну и не выглядит
    /// сломанным.
    private var silentFrames = 0
    private let silenceLimit = 90      // три секунды при 30 кадрах
    private let signalLimit = 24       // около секунды: столько ждём, прежде
                                       // чем считать, что звук прекратился

    /// Границы динамического диапазона в децибелах.
    private static let floorDB: Float = -84
    private static let ceilingDB: Float = -6

    init(bandCount: Int = 4) {
        self.bandCount = bandCount
        smoothed = [Float](repeating: 0, count: bandCount)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: fftSize, isHalfWindow: false)
        fftSetup = vDSP.FFT(log2n: vDSP_Length(log2(Float(fftSize))),
                            radix: .radix2, ofType: DSPSplitComplex.self)
    }

    /// `processes` пусто — слушаем весь выход, иначе только эти процессы.
    func start(processes: [AudioObjectID] = []) {
        guard !isRunning else { return }
        let session = AudioTapSession(frameCount: fftSize, processes: processes)
        guard session.start() else { return }
        self.session = session
        currentProcesses = processes
        isRunning = true

        // Перекладываем сырые кадры в полосы с частотой экрана, а не потока.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBands() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    /// Переключить отвод на другие процессы, не роняя всё остальное.
    func retarget(to processes: [AudioObjectID]) {
        guard isRunning, processes != currentProcesses else { return }
        stop()
        start(processes: processes)
    }

    private(set) var currentProcesses: [AudioObjectID] = []

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        session?.stop()
        session = nil
        isRunning = false
        hasSignal = false
        silentFrames = 0
        smoothed = [Float](repeating: 0, count: bandCount)
        bands = []
    }

    /// Диагностика: сколько раз пришли кадры и какова их амплитуда.
    var debugStats: (callbacks: Int, peak: Float) {
        guard let session else { return (0, 0) }
        let peak = session.samples.withLock { $0.map(abs).max() ?? 0 }
        return (session.callbackCount.withLock { $0 }, peak)
    }

    private func refreshBands() {
        guard let fftSetup, let session else { return }
        var samples = session.samples.withLock { $0 }
        guard samples.count == fftSize else { return }
        vDSP.multiply(samples, window, result: &samples)

        let half = fftSize / 2
        var realParts = [Float](repeating: 0, count: half)
        var imagParts = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                samples.withUnsafeBytes { raw in
                    vDSP_ctoz(
                        raw.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                        &split, 1, vDSP_Length(half)
                    )
                }
                fftSetup.forward(input: split, output: &split)
                vDSP.absolute(split, result: &magnitudes)
            }
        }

        // Полосы растут по логарифму: иначе низы съедают всю картинку.
        var fresh = [Float](repeating: 0, count: bandCount)
        var lower = 1
        for band in 0..<bandCount {
            let fraction = Double(band + 1) / Double(bandCount)
            let upper = min(Int(pow(Double(half), fraction)), half)
            guard upper > lower else { lower = upper; continue }
            let slice = magnitudes[lower..<upper]
            let energy = slice.reduce(0, +) / Float(slice.count)
            let db = 20 * log10(max(energy, 1e-7))
            // Диапазон широкий, иначе музыка почти всегда упирается в потолок.
            let normalized = (db - Self.floorDB) / (Self.ceilingDB - Self.floorDB)
            // Кривая прижимает середину: пики остаются пиками, а не нормой.
            fresh[band] = pow(min(max(normalized, 0), 1), 1.7)
            lower = upper
        }

        let peak = fresh.max() ?? 0
        if peak < 0.001 {
            silentFrames += 1
            // Короткие паузы между словами и тактами — ещё не тишина.
            if silentFrames >= signalLimit, hasSignal { hasSignal = false }
            if silentFrames >= silenceLimit {
                if !bands.isEmpty { bands = [] }
                return
            }
        } else {
            silentFrames = 0
            if !hasSignal { hasSignal = true }
        }

        // Быстро вверх, плавно вниз — как у настоящих индикаторов уровня.
        for index in 0..<bandCount {
            let target = fresh[index]
            smoothed[index] = target > smoothed[index]
                ? smoothed[index] + (target - smoothed[index]) * 0.55
                : smoothed[index] + (target - smoothed[index]) * 0.18
        }
        bands = smoothed
    }
}
