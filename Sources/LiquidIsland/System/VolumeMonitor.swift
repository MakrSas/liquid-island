import AppKit
import CoreAudio

/// Следит за громкостью системного выхода.
///
/// Подписываемся на свойства устройства, а не опрашиваем их: CoreAudio сам
/// сообщает об изменении, в том числе когда громкость меняют клавишами.
final class VolumeMonitor: @unchecked Sendable {
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listener: AudioObjectPropertyListenerBlock?
    private let onChange: @Sendable (Float, Bool) -> Void

    /// 'vmvc' — виртуальная общая громкость устройства. Константа живёт в
    /// AudioToolbox под именем kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
    /// но в Swift оттуда не видна, поэтому задаём кодом четырёх символов.
    private static let volumeSelector = AudioObjectPropertySelector(0x766D_7663)

    init(onChange: @escaping @Sendable (Float, Bool) -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        deviceID = Self.defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.onChange(self.currentVolume(), self.isMuted())
        }
        listener = block

        for selector in [Self.volumeSelector, AudioObjectPropertySelector(kAudioDevicePropertyMute)] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
        }
    }

    func stop() {
        guard let listener, deviceID != kAudioObjectUnknown else { return }
        for selector in [Self.volumeSelector, AudioObjectPropertySelector(kAudioDevicePropertyMute)] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
        }
        self.listener = nil
    }

    func currentVolume() -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: Self.volumeSelector,
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return value
    }

    func isMuted() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr else { return AudioObjectID(kAudioObjectUnknown) }
        return id
    }
}
