using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Media;

namespace LiquidIsland.Core;

/// <summary>
/// Все размеры, цвета, пружины и поведение острова.
/// </summary>
/// <remarks>
/// Имена ключей намеренно совпадают с версией для macOS: файл настроек у двух
/// сборок один и тот же по смыслу, и человек, перешедший с одной системы на
/// другую, переносит своё оформление копированием файла.
/// </remarks>
public sealed class IslandTheme
{
    public Geometry Geometry { get; set; } = new();
    public Palette Palette { get; set; } = new();
    public Motion Motion { get; set; } = new();
    public Behavior Behavior { get; set; } = new();

    public static IslandTheme Default => new();
}

public sealed class Geometry
{
    /// <summary>Пилюля в покое, когда музыки нет.</summary>
    public Size ClosedSize { get; set; } = new(168, 26);

    /// <summary>Карточка трека. Высота та же — остров растёт вбок, не вниз.</summary>
    public Size CompactSize { get; set; } = new(304, 26);

    /// <summary>Плашка события. Совпадает с карточкой, чтобы остров не дёргался.</summary>
    public Size HudSize { get; set; } = new(304, 26);

    /// <summary>Предупреждение о низком заряде: две строки и кнопка.</summary>
    public Size WarningSize { get; set; } = new(360, 64);

    /// <summary>Насколько остров подрастает под курсором — в основном вниз.</summary>
    public Size HoverPadding { get; set; } = new(14, 24);

    /// <summary>Раскрытый плеер.</summary>
    public Size ExpandedSize { get; set; } = new(420, 168);

    public double TopRadius { get; set; } = 9;
    public double BottomRadiusClosed { get; set; } = 8;
    public double BottomRadiusOpen { get; set; } = 11;

    public double ArtworkRadius { get; set; } = 5;
    public double ArtworkRadiusHovered { get; set; } = 8;
    /// <summary>Во сколько раз обложка поджимается на паузе.</summary>
    public double PausedArtworkScale { get; set; } = 0.82;

    /// <summary>Отступ от кромки экрана. Ноль — остров врастает в неё.</summary>
    public double FloatingTopInset { get; set; }

    public Thickness ContentPadding { get; set; } = new(16, 12, 16, 14);
    public Thickness CompactPadding { get; set; } = new(7, 4, 12, 4);

    /// <summary>Где размытие начинает проступать и где чёрный кончается совсем.</summary>
    public double GlassFadeStart { get; set; } = 0.44;
    public double GlassFadeEnd { get; set; } = 0.72;

    public double DotSize { get; set; } = 5;
    public double DotSpacing { get; set; } = 6;
    public double DotsCapsuleHeight { get; set; } = 20;
    public double DotsCapsulePadding { get; set; } = 12;
    public double DotsCapsuleGap { get; set; } = 7;
}

public sealed class Palette
{
    public string Background { get; set; } = "#FF000000";
    public string PrimaryText { get; set; } = "#FFFFFFFF";
    public string SecondaryText { get; set; } = "#99FFFFFF";
    public string Accent { get; set; } = "#FFFF6B36";
    public string ProgressTrack { get; set; } = "#38FFFFFF";
    public string ProgressFill { get; set; } = "#D9FFFFFF";
    public string RimLight { get; set; } = "#29FFFFFF";
    public double RimWidth { get; set; } = 0.6;

    /// <summary>
    /// Размытие под нижней частью раскрытого острова.
    /// </summary>
    /// <remarks>
    /// Жидкого стекла в Windows нет: ближайшее — акрил, размытие с зерном.
    /// Поэтому ключ здесь называется по сути, а не по имени эффекта из macOS.
    /// </remarks>
    public bool UseAcrylic { get; set; } = true;

    /// <summary>Подкраска акрила. Без неё остров выцветает на светлом фоне.</summary>
    public string AcrylicTint { get; set; } = "#57000000";
}

public sealed class Motion
{
    public double OpenResponse { get; set; } = 0.34;
    public double OpenDamping { get; set; } = 0.95;
    public double CloseResponse { get; set; } = 0.28;
    public double CloseDamping { get; set; } = 1.0;
    public double ContentResponse { get; set; } = 0.24;
    public double ContentDamping { get; set; } = 1.0;
}

public sealed class Behavior
{
    public bool ExpandOnHover { get; set; }
    public bool HoverShowsMedia { get; set; } = true;
    public double HoverOpenDelay { get; set; } = 0.45;
    public double HoverCloseDelay { get; set; } = 0.35;
    public bool DismissOnOutsideClick { get; set; } = true;

    public bool ShowVolumeHud { get; set; } = true;
    public bool ShowBrightnessHud { get; set; } = true;
    public bool ShowPowerHud { get; set; } = true;
    public double HudDuration { get; set; } = 1.6;

    public bool ShowLowBatteryWarning { get; set; } = true;
    public int LowBatteryThreshold { get; set; } = 20;
    public double WarningDuration { get; set; } = 6;

    public bool CollapseForSystemEvents { get; set; } = true;
    public bool RestoreAfterSystemEvent { get; set; } = true;

    public bool DimArtworkWhenPaused { get; set; } = true;
    public bool HideWhenPaused { get; set; } = true;
    public double HideWhenPausedAfter { get; set; } = 30;

    [JsonConverter(typeof(JsonStringEnumConverter))]
    public DotsPlacement DotsPlacement { get; set; } = DotsPlacement.Inside;

    [JsonConverter(typeof(JsonStringEnumConverter))]
    public DisplayMode DisplayMode { get; set; } = DisplayMode.Main;
}

public enum DotsPlacement { Inside, Below }

/// <summary>
/// На каком экране показывать остров. Чёлки в Windows нет ни у кого, поэтому
/// вариант с ней из списка убран.
/// </summary>
public enum DisplayMode { Main, FollowMouse, All }
