import SwiftUI

/// Привязки к теме для элементов управления.
///
/// Тема снаружи только читается, а меняется через `update` — так запись на
/// диск и рассылка изменений всегда идут вместе. Эти обёртки дают SwiftUI
/// обычный `Binding`, не ломая это правило.
extension ThemeStore {

    func binding<Value>(_ keyPath: WritableKeyPath<IslandTheme, Value>) -> Binding<Value> {
        Binding(
            get: { self.theme[keyPath: keyPath] },
            set: { fresh in self.update { $0[keyPath: keyPath] = fresh } }
        )
    }

    /// Цвет темы как `Color` для `ColorPicker`.
    func colorBinding(_ keyPath: WritableKeyPath<IslandTheme, CodableColor>) -> Binding<Color> {
        Binding(
            get: { self.theme[keyPath: keyPath].color },
            set: { fresh in
                self.update { $0[keyPath: keyPath] = CodableColor(fresh) }
            }
        )
    }

    /// Необязательный цвет: выключенный переключатель означает «без подкраски».
    func optionalColorBinding(
        _ keyPath: WritableKeyPath<IslandTheme, CodableColor?>,
        fallback: CodableColor
    ) -> Binding<Color> {
        Binding(
            get: { (self.theme[keyPath: keyPath] ?? fallback).color },
            set: { fresh in
                self.update { $0[keyPath: keyPath] = CodableColor(fresh) }
            }
        )
    }

    func isSet(_ keyPath: WritableKeyPath<IslandTheme, CodableColor?>, fallback: CodableColor) -> Binding<Bool> {
        Binding(
            get: { self.theme[keyPath: keyPath] != nil },
            set: { on in
                self.update { $0[keyPath: keyPath] = on ? fallback : nil }
            }
        )
    }

    /// Размер как две отдельные величины — так его удобно класть на ползунки.
    func sizeBinding(
        _ keyPath: WritableKeyPath<IslandTheme, CGSize>,
        axis: SizeAxis
    ) -> Binding<CGFloat> {
        Binding(
            get: {
                let size = self.theme[keyPath: keyPath]
                return axis == .width ? size.width : size.height
            },
            set: { fresh in
                self.update {
                    var size = $0[keyPath: keyPath]
                    if axis == .width { size.width = fresh } else { size.height = fresh }
                    $0[keyPath: keyPath] = size
                }
            }
        )
    }
}

enum SizeAxis { case width, height }

extension CodableColor {
    /// Приводим что угодно к sRGB: тема хранится числами, а не ссылкой на
    /// цветовое пространство.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent),
            alpha: Double(ns.alphaComponent)
        )
    }
}
