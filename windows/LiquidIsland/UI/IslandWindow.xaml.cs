using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using LiquidIsland.Core;
using LiquidIsland.Interop;
using LiquidIsland.Media;
using LiquidIsland.Sensors;
using Forms = System.Windows.Forms;

namespace LiquidIsland.UI;

public partial class IslandWindow : Window
{
    private readonly MediaHub _media;
    private readonly SystemHud _hud;
    private readonly DispatcherTimer _mouseWatch = new();
    private SizeAnimator? _animator;
    private readonly DispatcherTimer _pauseWatch = new();

    private IslandPhase _phase = IslandPhase.Closed;
    private IslandPhase? _phaseBeforeEvent;
    private bool _mouseInside;
    private bool _hiddenByPause;
    private int _pageIndex;
    private IntPtr _handle;

    private IslandTheme Theme => ThemeStore.Shared.Theme;

    public IslandWindow(MediaHub media, SystemHud hud)
    {
        InitializeComponent();
        _media = media;
        _hud = hud;

        _media.Changed += OnSourcesChanged;
        _hud.Changed += OnSystemEvent;
        ThemeStore.Shared.Changed += () => Dispatcher.Invoke(Relayout);

        Loaded += OnLoaded;
        MouseLeftButtonUp += (_, _) => Toggle();
        MouseWheel += OnWheel;
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _handle = new WindowInteropHelper(this).Handle;
        NativeMethods.HideFromTaskbar(_handle);
        PlaceOnScreen();

        _animator = new SizeAnimator(Draw);
        _animator.Set(CurrentSize);
        Relayout();

        // Курсор отслеживаем сами: окно почти всё время сквозное, и о движениях
        // мыши оно не узнаёт. Ровно та же причина, что и в версии для macOS.
        _mouseWatch.Interval = TimeSpan.FromMilliseconds(60);
        _mouseWatch.Tick += (_, _) => TrackMouse();
        _mouseWatch.Start();

        _pauseWatch.Tick += (_, _) =>
        {
            _pauseWatch.Stop();
            _hiddenByPause = true;
            Relayout();
        };
    }

    // --- Размещение ---

    private void PlaceOnScreen()
    {
        var screen = Forms.Screen.PrimaryScreen;
        if (screen is null) return;

        var source = PresentationSource.FromVisual(this);
        var scaleX = source?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        var scaleY = source?.CompositionTarget?.TransformToDevice.M22 ?? 1;

        // Окно шире самого острова: анимация раскрытия не должна упираться в
        // его границы, а капсуле с точками нужно место снизу.
        Width = Theme.Geometry.ExpandedSize.Width + 120;
        Height = Theme.Geometry.ExpandedSize.Height + 90;

        var area = screen.WorkingArea;
        Left = (screen.Bounds.X + screen.Bounds.Width / 2) / scaleX - Width / 2;
        Top = screen.Bounds.Y / scaleY;
    }

    // --- Состояния ---

    private Size RestingSize
    {
        get
        {
            if (_hud.Current is { } value)
            {
                return value.IsWarning ? Theme.Geometry.WarningSize : Theme.Geometry.HudSize;
            }
            return ShowsMediaCard ? Theme.Geometry.CompactSize : Theme.Geometry.ClosedSize;
        }
    }

    private Size CurrentSize
    {
        get
        {
            switch (_phase)
            {
                case IslandPhase.Expanded:
                    return Theme.Geometry.ExpandedSize;
                case IslandPhase.Hovered:
                    // Под плашкой остров не подрастает: у громкости и яркости
                    // нет подробностей, которые стоило бы раскрывать.
                    if (_hud.Current is not null) return RestingSize;
                    return new Size(
                        RestingSize.Width + Theme.Geometry.HoverPadding.Width,
                        RestingSize.Height + Theme.Geometry.HoverPadding.Height);
                default:
                    return RestingSize;
            }
        }
    }

    private bool ShowsMediaCard
    {
        get
        {
            if (_hiddenByPause) return false;
            if (_hud.Current is not null) return false;
            return Theme.Behavior.HoverShowsMedia && _media.Sources.Count > 0;
        }
    }

    private NowPlaying ShownTrack =>
        _media.Sources.Count > 0
            ? _media.Sources[Math.Clamp(_pageIndex, 0, _media.Sources.Count - 1)]
            : NowPlaying.Empty;

    private void Toggle()
    {
        _phaseBeforeEvent = null;
        // Разворачивать пустой остров незачем: там нечего показать.
        if (_hud.Current is null && _media.Sources.Count == 0)
        {
            Pulse();
            return;
        }
        Transition(_phase == IslandPhase.Expanded ? IslandPhase.Hovered : IslandPhase.Expanded);
    }

    private void Transition(IslandPhase next)
    {
        if (_phase == next) return;
        _phase = next;
        Relayout();
    }

    private void OnSourcesChanged() => Dispatcher.Invoke(() =>
    {
        var track = ShownTrack;
        if (track.IsPlaying)
        {
            _pauseWatch.Stop();
            if (_hiddenByPause) _hiddenByPause = false;
        }
        else if (Theme.Behavior.HideWhenPaused && !_hiddenByPause)
        {
            _pauseWatch.Interval = TimeSpan.FromSeconds(Theme.Behavior.HideWhenPausedAfter);
            _pauseWatch.Start();
        }
        Relayout();
    });

    private void OnSystemEvent() => Dispatcher.Invoke(() =>
    {
        // Системное событие сворачивает раскрытый остров и возвращает его,
        // когда плашка отработала: громкость человек меняет прямо сейчас и
        // ждёт увидеть именно её.
        if (_hud.Current is not null)
        {
            if (Theme.Behavior.CollapseForSystemEvents && _phase == IslandPhase.Expanded)
            {
                _phaseBeforeEvent = _phase;
                _phase = IslandPhase.Closed;
            }
        }
        else if (_phaseBeforeEvent is { } saved)
        {
            _phaseBeforeEvent = null;
            // Возвращаем только если за это время остров не тронули руками.
            if (Theme.Behavior.RestoreAfterSystemEvent && _phase == IslandPhase.Closed)
            {
                _phase = saved;
            }
        }
        Relayout();
    });

    // --- Мышь ---

    private void TrackMouse()
    {
        if (!NativeMethods.GetCursorPos(out var point)) return;

        var source = PresentationSource.FromVisual(this);
        var scaleX = source?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        var scaleY = source?.CompositionTarget?.TransformToDevice.M22 ?? 1;
        var cursor = new Point(point.X / scaleX, point.Y / scaleY);

        var size = CurrentSize;
        var rect = new Rect(
            Left + Width / 2 - size.Width / 2 - 4,
            Top + Theme.Geometry.FloatingTopInset - 4,
            size.Width + 8,
            size.Height + 8);

        var inside = rect.Contains(cursor);
        // Окно ловит мышь только там, где нарисована фигура; всё остальное
        // должно проходить насквозь к окнам под ним.
        NativeMethods.SetClickThrough(_handle, !inside);

        if (inside == _mouseInside) return;
        _mouseInside = inside;

        if (inside)
        {
            if (_phase != IslandPhase.Expanded) Transition(IslandPhase.Hovered);
        }
        else if (_phase != IslandPhase.Expanded)
        {
            Transition(IslandPhase.Closed);
        }
    }

    private void OnWheel(object sender, System.Windows.Input.MouseWheelEventArgs args)
    {
        if (_media.Sources.Count < 2) return;
        _pageIndex = (_pageIndex + (args.Delta > 0 ? 1 : -1) + _media.Sources.Count)
            % _media.Sources.Count;
        Relayout();
    }

    private void Pulse()
    {
        // Отклик на нажатие: остров чуть подрастает и возвращается.
        var grow = new DoubleAnimation(1, 1.05, new Duration(TimeSpan.FromMilliseconds(120)))
        {
            AutoReverse = true,
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        var scale = new ScaleTransform(1, 1);
        IslandLayer.RenderTransformOrigin = new Point(0.5, 0);
        IslandLayer.RenderTransform = scale;
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
    }

    // --- Отрисовка ---

    /// <summary>Пересчитать желаемое состояние и поехать к нему пружиной.</summary>
    private void Relayout()
    {
        if (_animator is null) return;

        var motion = Theme.Motion;
        // Сворачивание идёт своей пружиной: она короче и без отскока.
        var closing = CurrentSize.Width < _animator.Current.Width;
        _animator.AnimateTo(
            CurrentSize,
            closing ? motion.CloseResponse : motion.OpenResponse,
            closing ? motion.CloseDamping : motion.OpenDamping);
    }

    /// <summary>Отрисовать остров в заданном размере. Зовётся на каждом кадре.</summary>
    private void Draw(Size size)
    {
        var geometry = Theme.Geometry;
        var radius = _phase == IslandPhase.Expanded
            ? geometry.BottomRadiusOpen
            : geometry.BottomRadiusClosed;

        IslandBody.Data = IslandShape.Build(size, geometry.TopRadius, radius);
        IslandBody.StrokeThickness = Theme.Palette.RimWidth;
        RimBrush.Color = ThemeStore.ParseColor(Theme.Palette.RimLight);

        IslandLayer.Width = size.Width;
        IslandLayer.Height = size.Height;
        IslandLayer.Margin = new Thickness(0, geometry.FloatingTopInset, 0, 0);

        // Заливка: чёрный сверху, прозрачность снизу — там проступает акрил.
        var background = ThemeStore.ParseColor(Theme.Palette.Background);
        var opaque = _phase != IslandPhase.Expanded || !Theme.Palette.UseAcrylic;
        FillTop.Color = background;
        FillMid.Color = background;
        FillMid.Offset = opaque ? 1 : geometry.GlassFadeStart;
        FillBottom.Color = opaque ? background : Color.FromArgb(0, background.R, background.G, background.B);
        FillBottom.Offset = opaque ? 1 : geometry.GlassFadeEnd;

        UpdateContent(size);
        UpdateDots(size);
    }

    private void UpdateContent(Size size)
    {
        var padding = _phase == IslandPhase.Expanded
            ? Theme.Geometry.ContentPadding
            : Theme.Geometry.CompactPadding;
        ContentLayer.Margin = padding;
        ContentLayer.Width = Math.Max(size.Width - padding.Left - padding.Right, 0);
        ContentLayer.Height = Math.Max(size.Height - padding.Top - padding.Bottom, 0);

        if (_hud.Current is { } value)
        {
            HudCard.Visibility = Visibility.Visible;
            MediaCard.Visibility = Visibility.Collapsed;
            HudGlyph.Text = value.Glyph;
            HudReadout.Text = value.Readout;
            HudFill.Width = Math.Max(ContentLayer.Width - 60, 0) * value.Level;
            return;
        }

        HudCard.Visibility = Visibility.Collapsed;
        if (!ShowsMediaCard && _phase != IslandPhase.Expanded)
        {
            MediaCard.Visibility = Visibility.Collapsed;
            return;
        }

        var track = ShownTrack;
        MediaCard.Visibility = Visibility.Visible;
        TitleText.Text = track.Title.Length > 0 ? track.Title : "Ничего не играет";
        ArtistText.Text = track.Artist;

        var expanded = _phase == IslandPhase.Expanded;
        var hovered = _phase == IslandPhase.Hovered;
        ArtistText.Visibility = expanded || hovered ? Visibility.Visible : Visibility.Collapsed;

        var artworkSize = expanded ? 56 : hovered ? 34 : 18;
        ArtworkBox.Width = artworkSize;
        ArtworkBox.Height = artworkSize;
        ArtworkBox.CornerRadius = new CornerRadius(
            expanded ? 12 : hovered ? Theme.Geometry.ArtworkRadiusHovered : Theme.Geometry.ArtworkRadius);
        ArtworkScale.CenterX = artworkSize / 2.0;
        ArtworkScale.CenterY = artworkSize / 2.0;

        // На паузе обложка гаснет и поджимается: остров подсказывает, что
        // звука нет, ещё до того, как карточка уйдёт совсем.
        var dimmed = Theme.Behavior.DimArtworkWhenPaused && !track.IsPlaying;
        var scale = dimmed ? Theme.Geometry.PausedArtworkScale : 1;
        ArtworkScale.ScaleX = scale;
        ArtworkScale.ScaleY = scale;
        ArtworkBox.Opacity = dimmed ? 0.55 : 1;

        // Присваиваем всегда, в том числе пустую: иначе от прошлого трека
        // осталась бы чужая обложка.
        ArtworkBrush.ImageSource = track.Artwork;
        ArtworkFallback.Visibility = track.Artwork is null
            ? Visibility.Visible
            : Visibility.Collapsed;
        ArtworkFallback.FontSize = artworkSize * 0.45;

        UpdateWaveform(track);
    }

    private void UpdateWaveform(NowPlaying track)
    {
        var color = track.Accent ?? Colors.White;
        if (Waveform.Children.Count == 0)
        {
            for (var i = 0; i < 4; i++)
            {
                Waveform.Children.Add(new Border
                {
                    Width = 2.5,
                    CornerRadius = new CornerRadius(1.25),
                    Margin = new Thickness(1, 0, 1, 0),
                    VerticalAlignment = VerticalAlignment.Center
                });
            }
        }

        var height = _phase == IslandPhase.Expanded ? 16 : 10;
        for (var i = 0; i < Waveform.Children.Count; i++)
        {
            if (Waveform.Children[i] is not Border bar) continue;
            bar.Background = new SolidColorBrush(color);
            // Пока звук не снимается, рисунок задаётся высотой полосок: в
            // тишине они стоят ровно, при игре различаются.
            bar.Height = track.IsPlaying ? height * (0.4 + 0.6 * ((i % 3) + 1) / 3.0) : height * 0.22;
        }
    }

    private void UpdateDots(Size size)
    {
        var count = _media.Sources.Count;
        var visible = count > 1
            && _phase != IslandPhase.Closed
            && _hud.Current is null
            && (ShowsMediaCard || _phase == IslandPhase.Expanded);

        DotsCapsule.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (!visible) return;

        var geometry = Theme.Geometry;
        Dots.Children.Clear();
        for (var i = 0; i < count; i++)
        {
            Dots.Children.Add(new Ellipse
            {
                Width = geometry.DotSize,
                Height = geometry.DotSize,
                Margin = new Thickness(geometry.DotSpacing / 2, 0, geometry.DotSpacing / 2, 0),
                Fill = new SolidColorBrush(Colors.White),
                Opacity = i == _pageIndex ? 0.9 : 0.3
            });
        }

        DotsCapsule.Height = geometry.DotsCapsuleHeight;
        DotsCapsule.Padding = new Thickness(geometry.DotsCapsulePadding, 0, geometry.DotsCapsulePadding, 0);
        DotsCapsule.CornerRadius = new CornerRadius(geometry.DotsCapsuleHeight / 2);
        DotsOffset.Y = size.Height + geometry.FloatingTopInset + geometry.DotsCapsuleGap;
    }
}
