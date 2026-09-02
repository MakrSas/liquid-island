using System.Windows;
using System.Windows.Media.Animation;

namespace LiquidIsland.UI;

/// <summary>
/// Пружина, повторяющая движение из версии для macOS.
/// </summary>
/// <remarks>
/// В SwiftUI пружина задаётся откликом и долей демпфирования: отклик — период
/// собственных колебаний, доля — насколько они гасятся. В WPF такого нет, но
/// формула известна, и её можно посчитать самим: тогда движение совпадёт, а
/// не будет похожим.
/// </remarks>
public sealed class SpringEase : EasingFunctionBase
{
    public double Response { get; set; } = 0.34;
    public double Damping { get; set; } = 0.95;

    protected override double EaseInCore(double normalizedTime)
    {
        var omega = 2 * Math.PI / Math.Max(Response, 0.0001);
        var zeta = Math.Min(Math.Max(Damping, 0.0001), 1);

        // Время нормировано на длительность анимации, а формула считает в
        // секундах: разворачиваем обратно.
        var t = normalizedTime * Duration;

        if (zeta < 1)
        {
            var damped = omega * Math.Sqrt(1 - zeta * zeta);
            var decay = Math.Exp(-zeta * omega * t);
            return 1 - decay * (Math.Cos(damped * t) + zeta * omega / damped * Math.Sin(damped * t));
        }

        var critical = Math.Exp(-omega * t);
        return 1 - critical * (1 + omega * t);
    }

    /// <summary>Сколько секунд показываем — с запасом относительно отклика.</summary>
    public double Duration => Math.Max(Response * 3.5, 0.6);

    protected override Freezable CreateInstanceCore() =>
        new SpringEase { Response = Response, Damping = Damping };

    public static Duration DurationFor(double response) =>
        new(TimeSpan.FromSeconds(Math.Max(response * 3.5, 0.6)));
}
