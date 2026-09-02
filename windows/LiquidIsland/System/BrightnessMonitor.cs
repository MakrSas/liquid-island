using System.Management;
using System.Windows.Threading;

namespace LiquidIsland.System;

/// <summary>
/// Следит за яркостью встроенной панели.
/// </summary>
/// <remarks>
/// Значение живёт в WMI и только у ноутбучных экранов: у внешнего монитора его
/// нет, и это не поломка, а отсутствие такого понятия. Уведомлений WMI по этому
/// классу не даёт, поэтому опрашиваем — запрос дешёвый.
/// </remarks>
public sealed class BrightnessMonitor : IDisposable
{
    public event Action<double>? Changed;

    private readonly DispatcherTimer _timer = new();
    private int _last = -1;

    public bool IsAvailable { get; private set; }

    public void Start()
    {
        _last = Read();
        IsAvailable = _last >= 0;
        if (!IsAvailable) return;

        _timer.Interval = TimeSpan.FromMilliseconds(400);
        _timer.Tick += (_, _) =>
        {
            var value = Read();
            if (value < 0 || value == _last) return;
            _last = value;
            Changed?.Invoke(value / 100.0);
        };
        _timer.Start();
    }

    public void Dispose() => _timer.Stop();

    private static int Read()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "root\\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness");
            foreach (var item in searcher.Get())
            {
                return Convert.ToInt32(item["CurrentBrightness"]);
            }
        }
        catch (Exception)
        {
            // Внешний монитор или запрет доступа к WMI — яркости просто нет.
        }
        return -1;
    }
}
