import AppKit

/// Достаёт из обложки цвет, которым можно подсветить интерфейс.
///
/// Берём не средний цвет — он всегда получается бурым, — а самый насыщенный
/// из тех, что занимают заметную площадь. Так эквалайзер окрашивается в тон
/// обложки, как на iPhone.
enum ArtworkColor {

    static func accent(from image: NSImage) -> NSColor? {
        guard let bitmap = downsample(image, side: 24) else { return nil }

        // Копим цвета по «корзинам» оттенка: побеждает та, что и заметна,
        // и достаточно сочная.
        let bucketCount = 12
        var weight = [Double](repeating: 0, count: bucketCount)
        var sumHue = [Double](repeating: 0, count: bucketCount)
        var sumSat = [Double](repeating: 0, count: bucketCount)
        var sumBri = [Double](repeating: 0, count: bucketCount)

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                guard a > 0.5, s > 0.18, b > 0.2 else { continue }

                // Насыщенные и светлые пиксели весят больше блёклых.
                let w = Double(s * s * b)
                let index = min(Int(h * CGFloat(bucketCount)), bucketCount - 1)
                weight[index] += w
                sumHue[index] += Double(h) * w
                sumSat[index] += Double(s) * w
                sumBri[index] += Double(b) * w
            }
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > 0 else { return nil }

        let w = weight[best]
        // Подтягиваем к живому, но не кислотному: очень тёмные и очень блёклые
        // обложки иначе дают невнятный серый.
        let saturation = min(max(sumSat[best] / w, 0.55), 0.95)
        let brightness = min(max(sumBri[best] / w, 0.72), 1.0)
        return NSColor(
            hue: CGFloat(sumHue[best] / w),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: 1
        )
    }

    private static func downsample(_ image: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: side * 4, bitsPerPixel: 32
        ) else { return nil }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
