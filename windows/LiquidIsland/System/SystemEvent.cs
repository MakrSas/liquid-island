namespace LiquidIsland.System;

public enum SystemEventKind { Volume, Brightness, Power, LowBattery }

/// <summary>Событие системы, которое остров показывает плашкой.</summary>
public sealed record SystemEvent
{
    public SystemEventKind Kind { get; init; }
    /// <summary>Значение для шкалы, 0…1.</summary>
    public double Level { get; init; }
    public bool Muted { get; init; }
    public bool Plugged { get; init; }
    public int Charge { get; init; }

    public bool IsWarning => Kind == SystemEventKind.LowBattery;

    /// <summary>Имя значка из шрифта Segoe Fluent Icons.</summary>
    public string Glyph => Kind switch
    {
        SystemEventKind.Volume when Muted || Level <= 0 => "",
        SystemEventKind.Volume when Level < 0.34 => "",
        SystemEventKind.Volume when Level < 0.67 => "",
        SystemEventKind.Volume => "",
        SystemEventKind.Brightness when Level < 0.5 => "",
        SystemEventKind.Brightness => "",
        SystemEventKind.Power => Plugged ? "" : "",
        _ => ""
    };

    public string Readout => Kind switch
    {
        SystemEventKind.Power or SystemEventKind.LowBattery => $"{Charge}%",
        _ => $"{(int)Math.Round(Level * 100)}"
    };

    public string Title => Kind switch
    {
        SystemEventKind.Volume => "Громкость",
        SystemEventKind.Brightness => "Яркость",
        SystemEventKind.Power => Plugged ? "Зарядка подключена" : "Зарядка отключена",
        _ => $"{Charge}% заряда"
    };
}
