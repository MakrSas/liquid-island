using System.Windows;
using System.Windows.Media;

namespace LiquidIsland.UI;

/// <summary>
/// Форма острова: верхние углы вывернуты наружу и втекают в кромку экрана,
/// нижние скруглены обычным образом.
/// </summary>
/// <remarks>
/// Это тот же контур, что и в версии для macOS. Чёлки в Windows нет ни у
/// одного ноутбука, но форма всё равно нужна такая: остров вырастает из
/// верхней кромки, а не висит под ней отдельной плашкой.
/// </remarks>
public static class IslandShape
{
    public static Geometry Build(Size size, double topRadius, double bottomRadius)
    {
        var top = Math.Min(topRadius, size.Width / 2);
        var bottom = Math.Min(bottomRadius, Math.Min(size.Width / 2, size.Height));

        var figure = new PathFigure
        {
            StartPoint = new Point(-top, 0),
            IsClosed = true,
            IsFilled = true
        };

        // Слева от острова: подходим к кромке экрана и заворачиваем внутрь.
        figure.Segments.Add(new QuadraticBezierSegment(
            new Point(0, 0), new Point(0, top), true));

        figure.Segments.Add(new LineSegment(new Point(0, size.Height - bottom), true));
        figure.Segments.Add(new QuadraticBezierSegment(
            new Point(0, size.Height), new Point(bottom, size.Height), true));

        figure.Segments.Add(new LineSegment(new Point(size.Width - bottom, size.Height), true));
        figure.Segments.Add(new QuadraticBezierSegment(
            new Point(size.Width, size.Height),
            new Point(size.Width, size.Height - bottom), true));

        figure.Segments.Add(new LineSegment(new Point(size.Width, top), true));
        // Выворот вправо, к кромке экрана.
        figure.Segments.Add(new QuadraticBezierSegment(
            new Point(size.Width, 0), new Point(size.Width + top, 0), true));

        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        geometry.Freeze();
        return geometry;
    }
}
