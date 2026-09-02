using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace LiquidIsland.Media;

/// <summary>
/// Достаёт из обложки цвет, которым подсвечивается эквалайзер.
/// </summary>
/// <remarks>
/// Берём не средний цвет — он всегда получается бурым, — а самый насыщенный из
/// тех, что занимают заметную площадь. Расчёт тот же, что и в версии для macOS,
/// чтобы одна и та же обложка давала одинаковый цвет на обеих системах.
/// </remarks>
public static class ArtworkColor
{
    private const int Side = 24;
    private const int Buckets = 12;

    public static Color? Accent(BitmapSource source)
    {
        try
        {
            var scaled = new TransformedBitmap(
                source,
                new ScaleTransform(
                    (double)Side / source.PixelWidth,
                    (double)Side / source.PixelHeight));

            var converted = new FormatConvertedBitmap(scaled, PixelFormats.Bgra32, null, 0);
            var stride = Side * 4;
            var pixels = new byte[stride * Side];
            converted.CopyPixels(pixels, stride, 0);

            var weight = new double[Buckets];
            var hue = new double[Buckets];
            var saturation = new double[Buckets];
            var brightness = new double[Buckets];

            for (var index = 0; index < pixels.Length; index += 4)
            {
                double blue = pixels[index] / 255.0;
                double green = pixels[index + 1] / 255.0;
                double red = pixels[index + 2] / 255.0;
                double alpha = pixels[index + 3] / 255.0;

                var (h, s, v) = ToHsv(red, green, blue);
                if (alpha < 0.5 || s < 0.18 || v < 0.2) continue;

                // Насыщенные и светлые точки весят больше блёклых.
                var w = s * s * v;
                var bucket = Math.Min((int)(h * Buckets), Buckets - 1);
                weight[bucket] += w;
                hue[bucket] += h * w;
                saturation[bucket] += s * w;
                brightness[bucket] += v * w;
            }

            var best = 0;
            for (var i = 1; i < Buckets; i++)
            {
                if (weight[i] > weight[best]) best = i;
            }
            if (weight[best] <= 0) return null;

            var total = weight[best];
            // Подтягиваем к живому, но не кислотному: очень тёмные и блёклые
            // обложки иначе дают невнятный серый.
            return FromHsv(
                hue[best] / total,
                Math.Clamp(saturation[best] / total, 0.55, 0.95),
                Math.Clamp(brightness[best] / total, 0.72, 1.0));
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static (double Hue, double Saturation, double Value) ToHsv(double r, double g, double b)
    {
        var max = Math.Max(r, Math.Max(g, b));
        var min = Math.Min(r, Math.Min(g, b));
        var delta = max - min;

        double hue = 0;
        if (delta > 0)
        {
            if (Math.Abs(max - r) < double.Epsilon) hue = (g - b) / delta % 6;
            else if (Math.Abs(max - g) < double.Epsilon) hue = (b - r) / delta + 2;
            else hue = (r - g) / delta + 4;
            hue /= 6;
            if (hue < 0) hue += 1;
        }

        return (hue, max <= 0 ? 0 : delta / max, max);
    }

    private static Color FromHsv(double hue, double saturation, double value)
    {
        var sector = hue * 6;
        var index = (int)Math.Floor(sector) % 6;
        var fraction = sector - Math.Floor(sector);

        var p = value * (1 - saturation);
        var q = value * (1 - saturation * fraction);
        var t = value * (1 - saturation * (1 - fraction));

        var (r, g, b) = index switch
        {
            0 => (value, t, p),
            1 => (q, value, p),
            2 => (p, value, t),
            3 => (p, q, value),
            4 => (t, p, value),
            _ => (value, p, q)
        };

        return Color.FromRgb((byte)(r * 255), (byte)(g * 255), (byte)(b * 255));
    }
}
