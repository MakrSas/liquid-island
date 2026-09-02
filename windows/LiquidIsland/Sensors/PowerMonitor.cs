using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace LiquidIsland.Sensors;

/// <summary>Следит за питанием: подключением зарядки и уровнем заряда.</summary>
public sealed class PowerMonitor : IDisposable
{
    public event Action<bool, int>? Changed;
    public event Action<int>? LowBattery;

    private readonly DispatcherTimer _timer = new();
    private readonly int _threshold;
    private bool? _lastPlugged;
    private int? _warnedBelow;

    public PowerMonitor(int threshold) => _threshold = threshold;

    public void Start()
    {
        var state = Read();
        _lastPlugged = state?.Plugged;
        // Проверяем сразу: если приложение запустили уже на низком заряде,
        // ждать смены состояния не с чего.
        if (state is { } initial) CheckLowBattery(initial);

        _timer.Interval = TimeSpan.FromSeconds(20);
        _timer.Tick += (_, _) =>
        {
            if (Read() is not { } current) return;
            CheckLowBattery(current);

            // Уровень меняется постоянно, плашку показываем только на
            // подключении и отключении.
            if (current.Plugged == _lastPlugged) return;
            _lastPlugged = current.Plugged;
            Changed?.Invoke(current.Plugged, current.Charge);
        };
        _timer.Start();
    }

    public void Dispose() => _timer.Stop();

    /// <summary>
    /// Предупреждаем один раз на пересечении порога, а не на каждом проценте.
    /// Подключение зарядки сбрасывает счётчик: в следующий разряд предупреждение
    /// придёт снова.
    /// </summary>
    private void CheckLowBattery((bool Plugged, int Charge) state)
    {
        if (state.Plugged)
        {
            _warnedBelow = null;
            return;
        }

        if (state.Charge > _threshold) return;
        if (_warnedBelow is { } previous && state.Charge >= previous - 4) return;

        _warnedBelow = state.Charge;
        LowBattery?.Invoke(state.Charge);
    }

    public static (bool Plugged, int Charge)? Read()
    {
        if (!GetSystemPowerStatus(out var status)) return null;
        // 255 означает «неизвестно»: у настольной машины батареи нет.
        if (status.BatteryLifePercent == 255) return null;
        return (status.ACLineStatus == 1, status.BatteryLifePercent);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public int BatteryLifeTime;
        public int BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out SystemPowerStatus status);
}
