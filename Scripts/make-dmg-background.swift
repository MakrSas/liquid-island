// Рисует фон установщика: красные стрелки по кругу вокруг ярлыка «Программы».
// Запуск: swift Scripts/make-dmg-background.swift Resources/dmg-background.png
//
// ImageIO в консольном процессе на этой сборке macOS падает при записи, поэтому
// PNG кодируется вручную — тем же способом, что и превью острова.
import AppKit
import Foundation

let width = 1320, height = 840
// Центр ярлыка «Программы» на холсте, в пикселях.
let target = CGPoint(x: 960, y: 420)
let iconHalf: CGFloat = 128

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Начало координат у CoreGraphics снизу — переворачиваем, чтобы считать сверху.
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)

context.setFillColor(NSColor.white.cgColor)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

let red = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1).cgColor
context.setStrokeColor(red)
context.setFillColor(red)
context.setLineCap(.round)
context.setLineWidth(10)

let count = 12
let outer: CGFloat = 260   // хвост стрелки
let inner: CGFloat = 165   // остриё, чуть дальше края значка
let headLength: CGFloat = 34
let headWidth: CGFloat = 26

for step in 0..<count {
    let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(count)
    let direction = CGPoint(x: cos(angle), y: sin(angle))

    let tail = CGPoint(x: target.x + direction.x * outer, y: target.y + direction.y * outer)
    let tip = CGPoint(x: target.x + direction.x * inner, y: target.y + direction.y * inner)
    // Основание наконечника — на длину наконечника позади острия.
    let base = CGPoint(
        x: tip.x + direction.x * headLength,
        y: tip.y + direction.y * headLength
    )

    context.beginPath()
    context.move(to: tail)
    context.addLine(to: base)
    context.strokePath()

    // Наконечник: треугольник поперёк направления.
    let normal = CGPoint(x: -direction.y, y: direction.x)
    context.beginPath()
    context.move(to: tip)
    context.addLine(to: CGPoint(
        x: base.x + normal.x * headWidth,
        y: base.y + normal.y * headWidth
    ))
    context.addLine(to: CGPoint(
        x: base.x - normal.x * headWidth,
        y: base.y - normal.y * headWidth
    ))
    context.closePath()
    context.fillPath()
}

guard let image = context.makeImage() else { exit(1) }

// --- Ручная запись PNG ---
func be32(_ value: UInt32) -> Data {
    Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
          UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
}
let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
    var c = UInt32(index)
    for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
    return c
}
func crc32(_ data: Data) -> UInt32 {
    var c: UInt32 = 0xFFFFFFFF
    for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
    return c ^ 0xFFFFFFFF
}
func adler32(_ data: Data) -> UInt32 {
    var a: UInt32 = 1, b: UInt32 = 0
    for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
    return (b << 16) | a
}
func chunk(_ type: String, _ payload: Data) -> Data {
    var data = be32(UInt32(payload.count))
    let body = Data(type.utf8) + payload
    data.append(body)
    data.append(be32(crc32(body)))
    return data
}

var pixels = [UInt8](repeating: 0, count: width * height * 4)
let out = CGContext(
    data: &pixels, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
out.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var raw = Data(capacity: height * (width * 4 + 1))
for row in 0..<height {
    raw.append(0)
    let start = row * width * 4
    raw.append(contentsOf: pixels[start..<(start + width * 4)])
}
guard let deflated = try? (raw as NSData).compressed(using: .zlib) as Data else { exit(1) }
var stream = Data([0x78, 0x01])
stream.append(deflated)
stream.append(be32(adler32(raw)))

var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
var ihdr = be32(UInt32(width))
ihdr.append(be32(UInt32(height)))
ihdr.append(contentsOf: [8, 6, 0, 0, 0])
png.append(chunk("IHDR", ihdr))
png.append(chunk("IDAT", stream))
png.append(chunk("IEND", Data()))

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
try png.write(to: URL(fileURLWithPath: path))
print(path)
