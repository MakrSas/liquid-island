using System.Windows;
using System.Windows.Media;

namespace LiquidIsland.UI;

/// <summary>
/// Ведёт размер острова от текущего к желаемому по пружине.
/// </summary>
/// <remarks>
/// Обычные анимации WPF здесь не годятся: форма острова — это геометрия,
/// которую надо пересчитывать на каждом кадре, а не свойство, которое можно
/// плавно менять. Поэтому считаем сами на такте отрисовки и отдаём наружу
/// текущее значение — тот же приём, которым в версии для macOS стекло идёт
/// за островом кадр в кадр.
/// </remarks>
public sealed class SizeAnimator
{
    private readonly Action<Size> _apply;
    private Size _current;
    private Size _target;
    private double _elapsed;
    private Size _from;
    private bool _running;

    private double _response = 0.34;
    private double _damping = 0.95;
    private DateTime _lastTick;

    public SizeAnimator(Action<Size> apply) => _apply = apply;

    public Size Current => _current;

    /// <summary>Поставить размер сразу, без движения.</summary>
    public void Set(Size size)
    {
        _current = size;
        _target = size;
        _running = false;
        _apply(size);
    }

    public void AnimateTo(Size target, double response, double damping)
    {
        if (target == _target && _running) return;

        _from = _current;
        _target = target;
        _response = Math.Max(response, 0.05);
        _damping = Math.Clamp(damping, 0.05, 1);
        _elapsed = 0;
        _lastTick = DateTime.UtcNow;

        if (!_running)
        {
            _running = true;
            CompositionTarget.Rendering += OnFrame;
        }
    }

    private void OnFrame(object? sender, EventArgs args)
    {
        var now = DateTime.UtcNow;
        _elapsed += (now - _lastTick).TotalSeconds;
        _lastTick = now;

        var progress = Position(_elapsed);
        _current = new Size(
            _from.Width + (_target.Width - _from.Width) * progress,
            _from.Height + (_target.Height - _from.Height) * progress);
        _apply(_current);

        // Останавливаемся, когда движение уже неразличимо: держать такт
        // отрисовки ради сотых долей точки незачем.
        var settled = Math.Abs(_current.Width - _target.Width) < 0.2
            && Math.Abs(_current.Height - _target.Height) < 0.2
            && _elapsed > _response;

        if (!settled) return;

        _current = _target;
        _apply(_current);
        _running = false;
        CompositionTarget.Rendering -= OnFrame;
    }

    /// <summary>
    /// Положение пружины в момент времени, от 0 к 1.
    /// </summary>
    /// <remarks>
    /// Формула та же, что у SwiftUI: отклик задаёт период собственных
    /// колебаний, доля демпфирования — насколько они гасятся. При доле меньше
    /// единицы движение перелетает цель и возвращается, при единице приходит
    /// без отскока. Так остров на двух системах движется одинаково, а не
    /// похоже.
    /// </remarks>
    private double Position(double time)
    {
        var omega = 2 * Math.PI / _response;
        if (_damping < 1)
        {
            var damped = omega * Math.Sqrt(1 - _damping * _damping);
            var decay = Math.Exp(-_damping * omega * time);
            return 1 - decay * (Math.Cos(damped * time)
                + _damping * omega / damped * Math.Sin(damped * time));
        }

        var critical = Math.Exp(-omega * time);
        return 1 - critical * (1 + omega * time);
    }
}
