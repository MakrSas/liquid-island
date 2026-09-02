using System.IO;
using System.Windows.Media.Imaging;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace LiquidIsland.Media;

/// <summary>
/// Собирает сведения о проигрываемом из системы.
/// </summary>
/// <remarks>
/// В Windows это штатный API без разрешений и приватных фреймворков: он отдаёт
/// название, исполнителя, обложку и состояние сразу для всех приложений. На
/// macOS то же самое пришлось собирать из скриптов и звука, потому что Apple
/// закрыла системный источник. Здесь всё проще, и сразу видно каждый источник
/// по отдельности.
/// </remarks>
public sealed class MediaHub
{
    public event Action? Changed;

    /// <summary>Все звучащие источники, первым — активный.</summary>
    public IReadOnlyList<NowPlaying> Sources { get; private set; } = Array.Empty<NowPlaying>();

    public NowPlaying Current => Sources.Count > 0 ? Sources[0] : NowPlaying.Empty;

    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private readonly System.Windows.Threading.DispatcherTimer _timer = new();

    public async Task StartAsync()
    {
        try
        {
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }
        catch (Exception)
        {
            // Система без поддержки медиасессий: остров просто останется пустым.
            return;
        }

        _manager.SessionsChanged += (_, _) => Refresh();

        // Позиция и время меняются без уведомлений, поэтому опрашиваем — но
        // редко: раз в секунду достаточно, чтобы полоса шла ровно.
        _timer.Interval = TimeSpan.FromSeconds(1);
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();

        Refresh();
    }

    public void Stop() => _timer.Stop();

    private async void Refresh()
    {
        if (_manager is null) return;

        try
        {
            var sessions = _manager.GetSessions();
            var current = _manager.GetCurrentSession();
            var collected = new List<NowPlaying>();

            foreach (var session in sessions)
            {
                var track = await ReadAsync(session);
                if (track is null) continue;

                // Активная сессия идёт первой: остальные листаются точками.
                if (session.SourceAppUserModelId == current?.SourceAppUserModelId)
                {
                    collected.Insert(0, track);
                }
                else
                {
                    collected.Add(track);
                }
            }

            Sources = collected;
            Changed?.Invoke();
        }
        catch (Exception)
        {
            // Сессия может исчезнуть прямо во время опроса — не повод падать.
        }
    }

    private static async Task<NowPlaying?> ReadAsync(GlobalSystemMediaTransportControlsSession session)
    {
        try
        {
            var properties = await session.TryGetMediaPropertiesAsync();
            if (properties is null) return null;

            var playback = session.GetPlaybackInfo();
            var timeline = session.GetTimelineProperties();

            var title = properties.Title ?? string.Empty;
            var artist = properties.Artist ?? string.Empty;
            if (title.Length == 0 && artist.Length == 0) return null;

            var artwork = await LoadArtworkAsync(properties.Thumbnail);

            return new NowPlaying
            {
                Title = title,
                Artist = artist,
                Artwork = artwork,
                Duration = timeline.EndTime - timeline.StartTime,
                Elapsed = timeline.Position - timeline.StartTime,
                IsPlaying = playback?.PlaybackStatus
                    == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                SourceId = session.SourceAppUserModelId ?? string.Empty,
                SupportsTransport = playback?.Controls.IsPlayPauseToggleEnabled ?? false,
                Accent = artwork is null ? null : ArtworkColor.Accent(artwork)
            };
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static async Task<BitmapImage?> LoadArtworkAsync(IRandomAccessStreamReference? reference)
    {
        if (reference is null) return null;

        try
        {
            using var stream = await reference.OpenReadAsync();
            using var net = stream.AsStreamForRead();
            using var buffer = new MemoryStream();
            await net.CopyToAsync(buffer);
            buffer.Position = 0;

            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = buffer;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>Переслать команду тому приложению, которое сейчас показано.</summary>
    public async void Send(MediaCommand command, string sourceId)
    {
        if (_manager is null) return;

        try
        {
            var session = _manager.GetSessions()
                .FirstOrDefault(item => item.SourceAppUserModelId == sourceId)
                ?? _manager.GetCurrentSession();
            if (session is null) return;

            switch (command)
            {
                case MediaCommand.PlayPause:
                    await session.TryTogglePlayPauseAsync();
                    break;
                case MediaCommand.Next:
                    await session.TrySkipNextAsync();
                    break;
                case MediaCommand.Previous:
                    await session.TrySkipPreviousAsync();
                    break;
            }
        }
        catch (Exception)
        {
            // Приложение могло закрыться между опросом и нажатием.
        }
    }
}
