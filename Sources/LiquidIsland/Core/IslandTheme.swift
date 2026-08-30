import SwiftUI

/// Все размеры, радиусы, цвета и пружины острова живут здесь.
///
/// Ни одна вью не хардкодит числа: она спрашивает тему. За счёт этого
/// кастомизация (свои размеры, скругления, скорость анимаций, палитра)
/// сводится к правке одного Codable-объекта, который позже можно грузить
/// из ~/Library/Application Support/LiquidIsland/theme.json.
struct IslandTheme: Codable, Equatable {

    // MARK: - Геометрия

    struct Geometry: Codable, Equatable {
        /// Размер «пилюли» в покое на маках без чёлки.
        var closedSize: CGSize = CGSize(width: 148, height: 32)
        /// Насколько остров подрастает при наведении курсора.
        var hoverPadding: CGSize = CGSize(width: 22, height: 4)
        /// Компактный вид: обложка слева, визуализатор справа.
        var compactSize: CGSize = CGSize(width: 260, height: 38)
        /// Развёрнутая панель.
        var expandedSize: CGSize = CGSize(width: 420, height: 172)

        /// Радиус верхних углов (в режиме чёлки — «вывернутых» наружу).
        var topRadius: CGFloat = 10
        /// Радиус нижних углов в покое.
        var bottomRadiusClosed: CGFloat = 14
        /// Радиус нижних углов, когда остров раскрыт.
        var bottomRadiusOpen: CGFloat = 24

        /// Отступ пилюли от верхней кромки экрана на маках без чёлки.
        var floatingTopInset: CGFloat = 4
        /// Внутренние поля контента.
        var contentPadding: EdgeInsets = EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14)
    }

    // MARK: - Цвета

    struct Palette: Codable, Equatable {
        var background: CodableColor = CodableColor(white: 0, alpha: 1)
        var primaryText: CodableColor = CodableColor(white: 1, alpha: 1)
        var secondaryText: CodableColor = CodableColor(white: 1, alpha: 0.6)
        var accent: CodableColor = CodableColor(red: 1, green: 0.42, blue: 0.21, alpha: 1)
        var progressTrack: CodableColor = CodableColor(white: 1, alpha: 0.22)
        var progressFill: CodableColor = CodableColor(white: 1, alpha: 0.85)
        /// Мягкое свечение по краю раскрытого острова.
        var rimLight: CodableColor = CodableColor(white: 1, alpha: 0.10)
    }

    // MARK: - Анимация

    struct Motion: Codable, Equatable {
        var openResponse: Double = 0.38
        var openDamping: Double = 0.72
        var closeResponse: Double = 0.32
        var closeDamping: Double = 0.85
        var contentResponse: Double = 0.28
        var contentDamping: Double = 0.82

        var open: Animation { .spring(response: openResponse, dampingFraction: openDamping) }
        var close: Animation { .spring(response: closeResponse, dampingFraction: closeDamping) }
        var content: Animation { .spring(response: contentResponse, dampingFraction: contentDamping) }
    }

    // MARK: - Поведение

    struct Behavior: Codable, Equatable {
        /// Раскрывать по наведению курсора, а не только по клику.
        var expandOnHover: Bool = true
        /// Задержка перед раскрытием, чтобы остров не дёргался от каждого движения.
        var hoverOpenDelay: Double = 0.18
        /// Задержка перед схлопыванием после ухода курсора.
        var hoverCloseDelay: Double = 0.35
        /// Показывать компактный вид при смене трека.
        var showLiveActivities: Bool = true
        /// Сколько секунд висит всплывающая активность.
        var liveActivityDuration: Double = 3.0
        /// На каких экранах показывать остров.
        var displayMode: DisplayMode = .notchedOrMain
    }

    enum DisplayMode: String, Codable, CaseIterable {
        /// Экран с чёлкой, иначе основной.
        case notchedOrMain
        /// Всегда основной экран.
        case main
        /// Следовать за курсором.
        case followMouse
        /// На всех экранах сразу.
        case all
    }

    var geometry = Geometry()
    var palette = Palette()
    var motion = Motion()
    var behavior = Behavior()
    /// Порядок модулей в раскрытом виде — задел под пользовательскую сборку.
    var modules: [String] = ["media", "shelf", "calendar"]

    static let `default` = IslandTheme()
}

/// Цвет, который умеет лежать в JSON.
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(white: Double, alpha: Double) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

extension EdgeInsets: @retroactive Codable {
    enum Keys: String, CodingKey { case top, leading, bottom, trailing }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            top: try c.decode(CGFloat.self, forKey: .top),
            leading: try c.decode(CGFloat.self, forKey: .leading),
            bottom: try c.decode(CGFloat.self, forKey: .bottom),
            trailing: try c.decode(CGFloat.self, forKey: .trailing)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(top, forKey: .top)
        try c.encode(leading, forKey: .leading)
        try c.encode(bottom, forKey: .bottom)
        try c.encode(trailing, forKey: .trailing)
    }
}
