import AppKit
import Foundation

/// Минимальный кодировщик PNG.
///
/// Пишем файл сами: ImageIO на текущей сборке macOS падает при записи
/// изображения из процесса без запущенного интерфейса, а превью нужны
/// именно в таком режиме.
enum PNGEncoder {

    static func encode(_ cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        // Приводим что угодно к 8-битному RGBA sRGB — единственному формату,
        // который мы умеем записывать.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: info
            )
        }) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // PNG хранит строки с байтом фильтра впереди; используем фильтр 0 (none).
        var raw = Data(capacity: height * (width * 4 + 1))
        for row in 0..<height {
            raw.append(0)
            let start = row * width * 4
            raw.append(contentsOf: pixels[start..<(start + width * 4)])
        }

        guard let compressed = zlibStream(raw) else { return nil }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = Data()
        ihdr.append(be32(UInt32(width)))
        ihdr.append(be32(UInt32(height)))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])   // 8 бит, truecolor+alpha
        png.append(chunk("IHDR", ihdr))
        png.append(chunk("IDAT", compressed))
        png.append(chunk("IEND", Data()))
        return png
    }

    // MARK: - Служебное

    private static func be32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    private static func chunk(_ type: String, _ payload: Data) -> Data {
        var data = be32(UInt32(payload.count))
        let body = Data(type.utf8) + payload
        data.append(body)
        data.append(be32(crc32(body)))
        return data
    }

    /// zlib-обёртка вокруг raw deflate из Foundation.
    private static func zlibStream(_ raw: Data) -> Data? {
        guard let deflated = try? (raw as NSData).compressed(using: .zlib) as Data else { return nil }
        var stream = Data([0x78, 0x01])            // CMF/FLG для deflate, окно 32K
        stream.append(deflated)
        stream.append(be32(adler32(raw)))
        return stream
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}
