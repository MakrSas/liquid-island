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
    private readonly AudioLevels _levels = new();
    private readonly DispatcherTimer _mouseWatch = new();
    private SizeAnimator? _animator;
    private readonly DispatcherTimer _pauseWatch = new();
    private readonly DispatcherTimer _hoverExit = new();

    private IslandPhase _phase = IslandPhase.Closed;
    private IslandPhase? _phaseBeforeEvent;
    private bool _mouseInside;
    private bool _mouseWasDown;
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
        _levels.Changed += () => Dispatcher.Invoke(RefreshWaveform);
        _levels.Start();
        ThemeStore.Shared.Changed += () => Dispatcher.Invoke(Relayout);

        Loaded += OnLoaded;
        MouseLeftButtonUp += (_, _) => Toggle();
        MouseWheel += OnWheel;

        PreviousButton.Click += (_, _) => Send(MediaCommand.Previous);
        PlayPauseButton.Click += (_, _) => Send(MediaCommand.PlayPause);
        NextButton.Click += (_, _) => Send(MediaCommand.Next);
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
        _mouseWatch.Interval = TimeSpan.FromMilliseconds(33);
        _mouseWatch.Tick += (_, _) => TrackMouse();
        _mouseWatch.Start();

        _hoverExit.Tick += (_, _) =>
        {
            _hoverExit.Stop();
            if (_mouseInside || _phase == IslandPhase.Expanded) return;
            Transition(IslandPhase.Closed);
        };

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

    /// <summary>Команда уходит тому источнику, который сейчас показан.</summary>
    private void Send(MediaCommand command)
    {
        _media.Send(command, ShownTrack.SourceId);
    }

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

        // Клик мимо сворачивает раскрытый остров. Ловим переход из отпущенного
        // в нажатое, иначе одно удержание считалось бы за десяток кликов.
        var down = NativeMethods.IsMouseDown();
        if (down && !_mouseWasDown && !inside
            && _phase == IslandPhase.Expanded
            && Theme.Behavior.DismissOnOutsideClick)
        {
            _phaseBeforeEvent = null;
            Transition(IslandPhase.Closed);
        }
        _mouseWasDown = down;

        // Окно ловит мышь только там, где нарисована фигура; всё остальное
        // должно проходить насквозь к окнам под ним.
        NativeMethods.SetClickThrough(_handle, !inside);

        if (inside == _mouseInside) return;
        _mouseInside = inside;

        if (inside)
        {
            _hoverExit.Stop();
            if (_phase != IslandPhase.Expanded) Transition(IslandPhase.Hovered);
        }
        else if (_phase != IslandPhase.Expanded)
        {
            // Небольшая задержка: остров не должен схлопываться от того, что
            // курсор на мгновение задел его край по дороге.
            _hoverExit.Interval = TimeSpan.FromSeconds(Theme.Behavior.HoverCloseDelay);
            _hoverExit.Stop();
            _hoverExit.Start();
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
    private Size _drawnSize = Size.Empty;

    private void Draw(Size size)
    {
        var geometry = Theme.Geometry;
        var radius = _phase == IslandPhase.Expanded
            ? geometry.BottomRadiusOpen
            : geometry.BottomRadiusClosed;

        // Геометрию пересобираем только на реальном изменении: на такте
        // отрисовки это самая дорогая часть кадра.
        if (Math.Abs(size.Width - _drawnSize.Width) > 0.05
            || Math.Abs(size.Height - _drawnSize.Height) > 0.05)
        {
            IslandBody.Data = IslandShape.Build(size, geometry.TopRadius, radius);
            _drawnSize = size;
        }
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
        var geometry = Theme.Geometry;

        // Насколько остров раскрыт: ноль в покое, единица в полном размере.
        // Всё, что меняется при раскрытии, считается от этой доли — тогда
        // содержимое едет вместе с островом, а не перескакивает между двумя
        // заготовленными видами.
        var resting = RestingSize.Height;
        var full = geometry.ExpandedSize.Height;
        var openness = full > resting
            ? Math.Clamp((size.Height - resting) / (full - resting), 0, 1)
            : 0;

        var padding = Lerp(geometry.CompactPadding, geometry.ContentPadding, openness);
        ContentLayer.Margin = padding;
        ContentLayer.Width = Math.Max(size.Width - padding.Left - padding.Right, 0);
        ContentLayer.Height = Math.Max(size.Height - padding.Top - padding.Bottom, 0);

        if (_hud.Current is { } value)
        {
            Show(HudCard);
            Hide(MediaCard);
            PlayerExtras.Visibility = Visibility.Collapsed;
            HudGlyph.Text = value.Glyph;
            HudReadout.Text = value.Readout;
            HudFill.Width = Math.Max(ContentLayer.Width - 60, 0) * value.Level;
            return;
        }

        Hide(HudCard);
        if (!ShowsMediaCard && openness <= 0)
        {
            Hide(MediaCard);
            PlayerExtras.Visibility = Visibility.Collapsed;
            return;
        }

        var track = ShownTrack;
        Show(MediaCard);
        TitleText.Text = track.Title.Length > 0 ? track.Title : "Ничего не играет";
        ArtistText.Text = track.Artist;

        // Строка исполнителя появляется вместе с высотой, а не по щелчку фазы.
        var reveal = Math.Clamp(openness * 2, 0, 1);
        ArtistText.Opacity = _phase == IslandPhase.Closed ? 0 : Math.Max(reveal, 0.001);

        // Кегль в WPF не интерполируется, поэтому текст растёт масштабом.
        var textScale = 1 + 0.18 * openness;
        // Якорь слева: при росте от центра строка уезжала бы вбок вместе с
        // масштабом, и это читалось бы как прыжок.
        TextColumn.RenderTransformOrigin = new Point(0, 0.5);
        TextScale.ScaleX = textScale;
        TextScale.ScaleY = textScale;

        var artworkSize = Lerp(HoverArtworkSize, 56, openness);
        ArtworkBox.Width = artworkSize;
        ArtworkBox.Height = artworkSize;
        ArtworkBox.CornerRadius = new CornerRadius(
            Lerp(geometry.ArtworkRadiusHovered, 12, openness));
        ArtworkScale.CenterX = artworkSize / 2.0;
        ArtworkScale.CenterY = artworkSize / 2.0;

        // На паузе обложка гаснет и поджимается: остров подсказывает, что
        // звука нет, ещё до того, как карточка уйдёт совсем.
        var dimmed = Theme.Behavior.DimArtworkWhenPaused && !track.IsPlaying;
        var scale = dimmed ? geometry.PausedArtworkScale : 1;
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

        UpdatePlayer(track, openness);
        UpdateWaveform(track, openness);
    }

    /// <summary>Размер обложки в промежуточном состоянии под курсором.</summary>
    private double HoverArtworkSize => _phase == IslandPhase.Closed ? 18 : 34;

    private void UpdatePlayer(NowPlaying track, double openness)
    {
        // Полоса и кнопки проявляются во второй половине раскрытия: раньше
        // им просто не хватает высоты, и они наезжают на шапку.
        var reveal = Math.Clamp((openness - 0.45) / 0.55, 0, 1);
        if (reveal <= 0)
        {
            PlayerExtras.Visibility = Visibility.Collapsed;
            return;
        }
        PlayerExtras.Visibility = Visibility.Visible;

        // Прозрачность задаётся напрямую и каждый кадр, поэтому анимацию с
        // этого свойства снимаем: иначе она перебивает присваивание и плеер
        // остаётся невидимым навсегда.
        PlayerExtras.BeginAnimation(OpacityProperty, null);
        PlayerExtras.Opacity = reveal;

        ProgressFill.Width = Math.Max(ContentLayer.Width, 0) * track.Progress;
        ElapsedText.Text = Format(track.Elapsed);
        RemainingText.Text = "-" + Format(track.Duration - track.Elapsed);

        // Значок паузы и воспроизведения — из шрифта Segoe Fluent Icons.
        PlayPauseButton.Content = track.IsPlaying ? "\uE769" : "\uE768";
        var enabled = track.SupportsTransport;
        PreviousButton.IsEnabled = enabled;
        PlayPauseButton.IsEnabled = enabled;
        NextButton.IsEnabled = enabled;
        PlayerExtras.Opacity = enabled ? reveal : reveal * 0.4;
        // Высота карточки больше не задаётся руками: строки сетки разводят её
        // с плеером сами. Раньше значение оставалось от раскрытого вида и в
        // покое обрезало текст.
    }

    /// <summary>
    /// Показывает часть острова затуханием с лёгким уменьшением.
    /// </summary>
    /// <remarks>
    /// В версии для macOS смена содержимого идёт таким же переходом, и без
    /// него подмена читается рывком: плашка исчезает, карточка появляется, а
    /// между ними пустой кадр.
    /// </remarks>
    private void Show(FrameworkElement element)
    {
        if (element.Visibility == Visibility.Visible && element.Opacity > 0.99) return;

        element.Visibility = Visibility.Visible;
        var motion = Theme.Motion;
        var duration = new Duration(TimeSpan.FromSeconds(motion.ContentResponse));

        element.BeginAnimation(OpacityProperty,
            new DoubleAnimation(0, 1, duration) { EasingFunction = Ease() });

        if (element.RenderTransform is not ScaleTransform scale)
        {
            scale = new ScaleTransform(1, 1);
            element.RenderTransformOrigin = new Point(0.5, 0.5);
            element.RenderTransform = scale;
        }
        var grow = new DoubleAnimation(0.94, 1, duration) { EasingFunction = Ease() };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
    }

    private void Hide(FrameworkElement element)
    {
        if (element.Visibility != Visibility.Visible) return;

        var duration = new Duration(TimeSpan.FromSeconds(Theme.Motion.ContentResponse * 0.8));
        var fade = new DoubleAnimation(element.Opacity, 0, duration) { EasingFunction = Ease() };
        // Прячем только когда затухание закончилось, иначе элемент исчезал бы
        // мгновенно, а анимация шла бы в пустоту.
        fade.Completed += (_, _) =>
        {
            if (element.Opacity <= 0.01) element.Visibility = Visibility.Collapsed;
        };
        element.BeginAnimation(OpacityProperty, fade);
    }

    private static IEasingFunction Ease() =>
        new CubicEase { EasingMode = EasingMode.EaseOut };

    private static string Format(TimeSpan value)
    {
        if (value < TimeSpan.Zero) value = TimeSpan.Zero;
        return $"{(int)value.TotalMinutes}:{value.Seconds:D2}";
    }

    private static double Lerp(double from, double to, double amount) =>
        from + (to - from) * amount;

    private static Thickness Lerp(Thickness from, Thickness to, double amount) => new(
        Lerp(from.Left, to.Left, amount),
        Lerp(from.Top, to.Top, amount),
        Lerp(from.Right, to.Right, amount),
        Lerp(from.Bottom, to.Bottom, amount));

    private double _waveHeight = 10;
    private SolidColorBrush _waveBrush = new(Colors.White);
    private int _dotCount = -1;

    private void UpdateWaveform(NowPlaying track, double openness)
    {
        _waveHeight = Lerp(10, 16, openness);

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

        // Кисть меняем только когда цвет обложки действительно другой:
        // создавать её тридцать раз в секунду незачем.
        var color = track.Accent ?? Colors.White;
        if (_waveBrush.Color != color)
        {
            _waveBrush = new SolidColorBrush(color);
            _waveBrush.Freeze();
            foreach (var child in Waveform.Children)
            {
                if (child is Border bar) bar.Background = _waveBrush;
            }
        }

        RefreshWaveform();
    }

    /// <summary>
    /// Обновляет высоту полосок по уровням звука.
    /// </summary>
    /// <remarks>
    /// Зовётся отдельно от общей перерисовки: уровни приходят тридцать раз в
    /// секунду, а пересчитывать из-за них геометрию острова незачем.
    /// </remarks>
    private void RefreshWaveform()
    {
        var bands = _levels.Bands;
        var playing = ShownTrack.IsPlaying;

        for (var i = 0; i < Waveform.Children.Count; i++)
        {
            if (Waveform.Children[i] is not Border bar) continue;

            // В тишине полоски стоят: рисовать движение под беззвучие — врать.
            if (!playing || !_levels.HasSignal || bands.Length <= i)
            {
                bar.Height = _waveHeight * 0.22;
                continue;
            }

            bar.Height = _waveHeight * (0.18 + 0.82 * bands[i]);
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

        // Точки пересобираем только когда их стало больше или меньше. Раньше
        // они создавались заново на каждом кадре анимации и мерцали.
        if (_dotCount != count)
        {
            _dotCount = count;
            Dots.Children.Clear();
            for (var i = 0; i < count; i++)
            {
                Dots.Children.Add(new Ellipse
                {
                    Width = geometry.DotSize,
                    Height = geometry.DotSize,
                    Margin = new Thickness(geometry.DotSpacing / 2, 0, geometry.DotSpacing / 2, 0),
                    Fill = Brushes.White
                });
            }
        }

        for (var i = 0; i < Dots.Children.Count; i++)
        {
            Dots.Children[i].Opacity = i == _pageIndex ? 0.9 : 0.3;
        }

        DotsCapsule.Height = geometry.DotsCapsuleHeight;
        DotsCapsule.Padding = new Thickness(geometry.DotsCapsulePadding, 0, geometry.DotsCapsulePadding, 0);
        DotsCapsule.CornerRadius = new CornerRadius(geometry.DotsCapsuleHeight / 2);
        DotsOffset.Y = size.Height + geometry.FloatingTopInset + geometry.DotsCapsuleGap;
    }
}
