using System.Windows.Threading;
using LiquidIsland.Core;

namespace LiquidIsland.Sensors;

/// <summary>
/// Собирает системные события и отдаёт их острову.
/// </summary>
/// <remarks>
/// Первое значение каждого источника проглатывается: при запуске нам сообщают
/// текущее состояние, а показывать плашку на пустом месте незачем.
/// </remarks>
public sealed class SystemHud : IDisposable
{
    public event Action? Changed;

    public SystemEvent? Current { get; private set; }

    private readonly VolumeMonitor _volume = new();
    private readonly BrightnessMonitor _brightness = new();
    private PowerMonitor? _power;
    private readonly DispatcherTimer _hide = new();

    public void Start()
    {
        var behavior = ThemeStore.Shared.Theme.Behavior;

        _volume.Changed += (level, muted) => Present(new SystemEvent
        {
            Kind = SystemEventKind.Volume,
            Level = level,
            Muted = muted
        });
        _volume.Start();

        _brightness.Changed += level => Present(new SystemEvent
        {
            Kind = SystemEventKind.Brightness,
            Level = level
        });
        _brightness.Start();

        _power = new PowerMonitor(behavior.LowBatteryThreshold);
        _power.Changed += (plugged, charge) => Present(new SystemEvent
        {
            Kind = SystemEventKind.Power,
            Plugged = plugged,
            Charge = charge,
            Level = charge / 100.0
        });
        _power.LowBattery += charge => Present(new SystemEvent
        {
            Kind = SystemEventKind.LowBattery,
            Charge = charge,
            Level = charge / 100.0
        });
        _power.Start();

        _hide.Tick += (_, _) =>
        {
            _hide.Stop();
            Current = null;
            Changed?.Invoke();
        };
    }

    public void Dispose()
    {
        _volume.Dispose();
        _brightness.Dispose();
        _power?.Dispose();
        _hide.Stop();
    }

    private void Present(SystemEvent fresh)
    {
        var behavior = ThemeStore.Shared.Theme.Behavior;
        var allowed = fresh.Kind switch
        {
            SystemEventKind.Volume => behavior.ShowVolumeHud,
            SystemEventKind.Brightness => behavior.ShowBrightnessHud,
            SystemEventKind.Power => behavior.ShowPowerHud,
            _ => behavior.ShowLowBatteryWarning
        };
        if (!allowed) return;

        Current = fresh;
        Changed?.Invoke();

        // Предупреждению нужно больше времени: на него надо успеть нажать.
        _hide.Stop();
        _hide.Interval = TimeSpan.FromSeconds(
            fresh.IsWarning ? behavior.WarningDuration : behavior.HudDuration);
        _hide.Start();
    }

    /// <summary>Показать предупреждение вручную — для проверки вида.</summary>
    public void TestLowBattery(int charge = 20) => Present(new SystemEvent
    {
        Kind = SystemEventKind.LowBattery,
        Charge = charge,
        Level = charge / 100.0
    });
}
