using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace LiquidIsland.Sensors;

/// <summary>
/// Реальные уровни звука по частотным полосам.
/// </summary>
/// <remarks>
/// Слушаем системный вывод через WASAPI в режиме loopback: он отдаёт то же,
/// что уходит на колонки, и разрешения для этого не требуется — в отличие от
/// macOS, где под тот же перехват нужно согласие пользователя.
///
/// Дальше окно Ханна, быстрое преобразование Фурье и разбивка на полосы —
/// ровно то же, что делает версия для macOS, чтобы рисунок совпадал.
/// </remarks>
public sealed class AudioLevels : IDisposable
{
    public event Action? Changed;

    /// <summary>Уровни полос, 0…1, от низов к верхам.</summary>
    public float[] Bands { get; private set; } = Array.Empty<float>();

    /// <summary>Идёт ли сейчас звук на самом деле.</summary>
    public bool HasSignal { get; private set; }

    private const int FftSize = 1024;
    private const int BandCount = 4;
    private const float FloorDb = -84;
    private const float CeilingDb = -6;

    private readonly float[] _window = new float[FftSize];
    private readonly float[] _samples = new float[FftSize];
    private readonly float[] _smoothed = new float[BandCount];
    private readonly object _lock = new();

    private Thread? _worker;
    private volatile bool _running;
    private DispatcherTimer? _publish;
    private int _silentFrames;

    public AudioLevels()
    {
        for (var i = 0; i < FftSize; i++)
        {
            _window[i] = 0.5f * (1 - MathF.Cos(2 * MathF.PI * i / (FftSize - 1)));
        }
    }

    public void Start()
    {
        if (_running) return;
        _running = true;

        _worker = new Thread(Capture) { IsBackground = true, Name = "LiquidIsland audio" };
        _worker.Start();

        // Кадры приходят чаще, чем нужно глазу: наружу отдаём тридцать раз в
        // секунду, как и на macOS.
        _publish = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        _publish.Tick += (_, _) => Publish();
        _publish.Start();
    }

    public void Dispose()
    {
        _running = false;
        _publish?.Stop();
        _worker?.Join(500);
    }

    // --- Захват ---

    private void Capture()
    {
        IAudioClient? client = null;
        IAudioCaptureClient? capture = null;

        try
        {
            var enumeratorType = Type.GetTypeFromCLSID(
                new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"))!;
            var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(enumeratorType)!;
            enumerator.GetDefaultAudioEndpoint(0, 0, out var device);

            var clientId = typeof(IAudioClient).GUID;
            device.Activate(ref clientId, 1, IntPtr.Zero, out var clientObject);
            client = (IAudioClient)clientObject;

            client.GetMixFormat(out var formatPointer);
            var format = Marshal.PtrToStructure<WaveFormatEx>(formatPointer);

            // 0x00020000 — loopback: забираем то, что играет, а не микрофон.
            client.Initialize(0, 0x00020000, 10_000_000, 0, formatPointer, IntPtr.Zero);

            var captureId = typeof(IAudioCaptureClient).GUID;
            client.GetService(ref captureId, out var captureObject);
            capture = (IAudioCaptureClient)captureObject;
            client.Start();

            var ring = new float[FftSize];
            var filled = 0;

            while (_running)
            {
                capture.GetNextPacketSize(out var frames);
                if (frames == 0)
                {
                    Thread.Sleep(5);
                    continue;
                }

                while (frames > 0)
                {
                    capture.GetBuffer(out var buffer, out var available, out var flags, out _, out _);
                    if (available > 0 && buffer != IntPtr.Zero)
                    {
                        // Флаг 0x2 означает тишину: система не заполняет буфер,
                        // и читать его нельзя.
                        var silent = (flags & 0x2) != 0;
                        Mix(buffer, (int)available, format, ring, ref filled, silent);
                    }
                    capture.ReleaseBuffer(available);
                    capture.GetNextPacketSize(out frames);
                }
            }
        }
        catch (Exception)
        {
            // Нет устройства вывода или отказ в доступе: эквалайзер просто
            // останется стоять, остальное работает.
        }
        finally
        {
            try { client?.Stop(); } catch (Exception) { }
            if (capture is not null) Marshal.ReleaseComObject(capture);
            if (client is not null) Marshal.ReleaseComObject(client);
        }
    }

    /// <summary>Сводит кадры в моно и складывает в кольцо последних отсчётов.</summary>
    private void Mix(IntPtr buffer, int frames, WaveFormatEx format,
        float[] ring, ref int filled, bool silent)
    {
        var channels = Math.Max((int)format.Channels, 1);
        var floats = format.BitsPerSample == 32;

        for (var frame = 0; frame < frames; frame++)
        {
            float value = 0;
            if (!silent && floats)
            {
                for (var channel = 0; channel < channels; channel++)
                {
                    var offset = (frame * channels + channel) * 4;
                    value += Marshal.PtrToStructure<float>(buffer + offset);
                }
                value /= channels;
            }

            ring[filled % FftSize] = value;
            filled++;
        }

        if (filled < FftSize) return;

        lock (_lock)
        {
            // Разворачиваем кольцо в прямой порядок: старшие отсчёты в конце.
            var start = filled % FftSize;
            for (var i = 0; i < FftSize; i++)
            {
                _samples[i] = ring[(start + i) % FftSize];
            }
        }
    }

    // --- Разбор спектра ---

    private void Publish()
    {
        float[] frame;
        lock (_lock) frame = (float[])_samples.Clone();

        var real = new float[FftSize];
        var imaginary = new float[FftSize];
        for (var i = 0; i < FftSize; i++) real[i] = frame[i] * _window[i];

        Fft(real, imaginary);

        var half = FftSize / 2;
        var fresh = new float[BandCount];
        var lower = 1;
        for (var band = 0; band < BandCount; band++)
        {
            // Полосы растут по логарифму: иначе низы съедают всю картинку.
            var fraction = (double)(band + 1) / BandCount;
            var upper = Math.Min((int)Math.Pow(half, fraction), half);
            if (upper <= lower) { lower = upper; continue; }

            double energy = 0;
            for (var i = lower; i < upper; i++)
            {
                energy += Math.Sqrt(real[i] * real[i] + imaginary[i] * imaginary[i]);
            }
            energy /= upper - lower;

            var db = 20 * Math.Log10(Math.Max(energy, 1e-7));
            var normalized = (db - FloorDb) / (CeilingDb - FloorDb);
            // Кривая прижимает середину: пики остаются пиками, а не нормой.
            fresh[band] = (float)Math.Pow(Math.Clamp(normalized, 0, 1), 1.7);
            lower = upper;
        }

        var peak = fresh.Max();
        if (peak < 0.001f)
        {
            _silentFrames++;
            // Короткие провалы между тактами — ещё не тишина.
            if (_silentFrames >= 24) HasSignal = false;
        }
        else
        {
            _silentFrames = 0;
            HasSignal = true;
        }

        // Быстро вверх, плавно вниз — как у настоящих индикаторов уровня.
        for (var i = 0; i < BandCount; i++)
        {
            var target = fresh[i];
            _smoothed[i] += (target - _smoothed[i]) * (target > _smoothed[i] ? 0.55f : 0.18f);
        }

        Bands = (float[])_smoothed.Clone();
        Changed?.Invoke();
    }

    /// <summary>Быстрое преобразование Фурье на месте, основание два.</summary>
    private static void Fft(float[] real, float[] imaginary)
    {
        var count = real.Length;
        for (int i = 1, j = 0; i < count; i++)
        {
            var bit = count >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i >= j) continue;
            (real[i], real[j]) = (real[j], real[i]);
            (imaginary[i], imaginary[j]) = (imaginary[j], imaginary[i]);
        }

        for (var length = 2; length <= count; length <<= 1)
        {
            var angle = -2 * MathF.PI / length;
            var stepReal = MathF.Cos(angle);
            var stepImaginary = MathF.Sin(angle);

            for (var i = 0; i < count; i += length)
            {
                float wReal = 1, wImaginary = 0;
                for (var j = 0; j < length / 2; j++)
                {
                    var evenReal = real[i + j];
                    var evenImaginary = imaginary[i + j];
                    var oddReal = real[i + j + length / 2] * wReal
                        - imaginary[i + j + length / 2] * wImaginary;
                    var oddImaginary = real[i + j + length / 2] * wImaginary
                        + imaginary[i + j + length / 2] * wReal;

                    real[i + j] = evenReal + oddReal;
                    imaginary[i + j] = evenImaginary + oddImaginary;
                    real[i + j + length / 2] = evenReal - oddReal;
                    imaginary[i + j + length / 2] = evenImaginary - oddImaginary;

                    var next = wReal * stepReal - wImaginary * stepImaginary;
                    wImaginary = wReal * stepImaginary + wImaginary * stepReal;
                    wReal = next;
                }
            }
        }
    }

    // --- COM ---

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct WaveFormatEx
    {
        public short FormatTag;
        public short Channels;
        public int SamplesPerSecond;
        public int AverageBytesPerSecond;
        public short BlockAlign;
        public short BitsPerSample;
        public short Size;
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        int NotImpl1();
        [PreserveSig]
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid interfaceId, int contextClass, IntPtr activationParams,
            [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport, Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioClient
    {
        [PreserveSig]
        int Initialize(int shareMode, int streamFlags, long bufferDuration,
            long periodicity, IntPtr format, IntPtr sessionId);
        int GetBufferSize(out uint frames);
        int GetStreamLatency(out long latency);
        int GetCurrentPadding(out uint padding);
        int IsFormatSupported(int shareMode, IntPtr format, IntPtr closestMatch);
        [PreserveSig]
        int GetMixFormat(out IntPtr format);
        int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);
        [PreserveSig]
        int Start();
        [PreserveSig]
        int Stop();
        int Reset();
        int SetEventHandle(IntPtr handle);
        [PreserveSig]
        int GetService(ref Guid interfaceId,
            [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport, Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioCaptureClient
    {
        [PreserveSig]
        int GetBuffer(out IntPtr buffer, out uint frames, out uint flags,
            out long devicePosition, out long counterPosition);
        [PreserveSig]
        int ReleaseBuffer(uint frames);
        [PreserveSig]
        int GetNextPacketSize(out uint frames);
    }
}
