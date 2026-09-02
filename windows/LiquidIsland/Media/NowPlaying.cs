using System.Windows.Media;

namespace LiquidIsland.Media;

/// <summary>Что играет прямо сейчас.</summary>
public sealed record NowPlaying
{
    public string Title { get; init; } = string.Empty;
    public string Artist { get; init; } = string.Empty;
    public ImageSource? Artwork { get; init; }
    public TimeSpan Duration { get; init; }
    public TimeSpan Elapsed { get; init; }
    public bool IsPlaying { get; init; }

    /// <summary>Кто играет: идентификатор приложения из системы.</summary>
    public string SourceId { get; init; } = string.Empty;

    /// <summary>Можно ли отсюда управлять воспроизведением.</summary>
    public bool SupportsTransport { get; init; } = true;

    /// <summary>Цвет, вытянутый из обложки: им подсвечивается эквалайзер.</summary>
    public Color? Accent { get; init; }

    public static readonly NowPlaying Empty = new();

    public bool IsEmpty => Title.Length == 0 && Artist.Length == 0;

    public double Progress => Duration > TimeSpan.Zero
        ? Math.Clamp(Elapsed.TotalSeconds / Duration.TotalSeconds, 0, 1)
        : 0;
}

public enum MediaCommand { PlayPause, Next, Previous }
