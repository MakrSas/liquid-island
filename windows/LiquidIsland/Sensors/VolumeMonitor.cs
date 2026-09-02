using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace LiquidIsland.Sensors;

/// <summary>
/// Следит за громкостью системного вывода.
/// </summary>
/// <remarks>
/// Значение опрашивается, а не приходит уведомлением. Уведомления в этом API
/// требуют реализовать COM-интерфейс на стороне приложения, а опрос стоит
/// один вызов и заметно надёжнее в сопровождении.
/// </remarks>
public sealed class VolumeMonitor : IDisposable
{
    public event Action<double, bool>? Changed;

    private readonly DispatcherTimer _timer = new();
    private IAudioEndpointVolume? _endpoint;
    private double _lastLevel = -1;
    private bool _lastMuted;

    public void Start()
    {
        _endpoint = OpenEndpoint();
        if (_endpoint is null) return;

        (_lastLevel, _lastMuted) = Read();

        _timer.Interval = TimeSpan.FromMilliseconds(150);
        _timer.Tick += (_, _) =>
        {
            var (level, muted) = Read();
            // Мелкое дрожание значения изменением не считаем.
            if (Math.Abs(level - _lastLevel) < 0.001 && muted == _lastMuted) return;
            _lastLevel = level;
            _lastMuted = muted;
            Changed?.Invoke(level, muted);
        };
        _timer.Start();
    }

    public void Dispose()
    {
        _timer.Stop();
        if (_endpoint is not null) Marshal.ReleaseComObject(_endpoint);
        _endpoint = null;
    }

    private (double Level, bool Muted) Read()
    {
        if (_endpoint is null) return (0, false);
        try
        {
            _endpoint.GetMasterVolumeLevelScalar(out var level);
            _endpoint.GetMute(out var muted);
            return (level, muted);
        }
        catch (Exception)
        {
            return (_lastLevel < 0 ? 0 : _lastLevel, _lastMuted);
        }
    }

    private static IAudioEndpointVolume? OpenEndpoint()
    {
        try
        {
            var enumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"))!;
            var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(enumeratorType)!;
            enumerator.GetDefaultAudioEndpoint(0, 1, out var device);

            var interfaceId = typeof(IAudioEndpointVolume).GUID;
            device.Activate(ref interfaceId, 1, IntPtr.Zero, out var instance);
            return (IAudioEndpointVolume)instance;
        }
        catch (Exception)
        {
            return null;
        }
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

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume
    {
        int NotImpl1();
        int NotImpl2();
        int GetChannelCount(out int count);
        int SetMasterVolumeLevel(float level, ref Guid context);
        int SetMasterVolumeLevelScalar(float level, ref Guid context);
        int GetMasterVolumeLevel(out float level);
        [PreserveSig]
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(uint channel, float level, ref Guid context);
        int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
        int GetChannelVolumeLevel(uint channel, out float level);
        int GetChannelVolumeLevelScalar(uint channel, out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig]
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }
}
