import SwiftUI
import AppKit

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
        /// Высота держится в пределах меню-бара, чтобы остров не залезал на окна.
        var closedSize: CGSize = CGSize(width: 168, height: 26)
        /// Карточка трека в покое. Высота та же, что у пилюли: остров
        /// расширяется вбок, а не вниз.
        var compactSize: CGSize = CGSize(width: 304, height: 26)
        /// Плашка системного события: громкость, яркость, зарядка.
        /// Совпадает с карточкой трека по обеим сторонам: иначе остров
        /// меняет размер, когда плашка перебивает музыку.
        var hudSize: CGSize = CGSize(width: 304, height: 26)
        /// Предупреждение о низком заряде: две строки и кнопка.
        var warningSize: CGSize = CGSize(width: 360, height: 64)

        /// Насколько остров подрастает при наведении — в основном вниз.
        var hoverPadding: CGSize = CGSize(width: 14, height: 24)
        /// Развёрнутая панель — только чёрная часть, без стеклянного подноса.
        var expandedSize: CGSize = CGSize(width: 420, height: 168)

        /// Где по высоте раскрытого острова чёрный начинает уходить в стекло
        /// и где растворяется полностью. Доли высоты, сверху вниз.
        var glassFadeStart: Double = 0.46
        var glassFadeEnd: Double = 0.76


        /// Радиус верхних углов (в режиме чёлки — «вывернутых» наружу).
        var topRadius: CGFloat = 9
        /// Радиус нижних углов в покое — такой же, как у пустого острова,
        /// когда музыки нет. Появление карточки форму не меняет.
        var bottomRadiusClosed: CGFloat = 8
        /// Радиус обложки задаётся отдельно: подгонять её под кромку,
        /// чтобы смягчить углы острова, — не тот способ.
        var artworkRadius: CGFloat = 5
        var artworkRadiusHovered: CGFloat = 8
        /// Радиус нижних углов, когда остров раскрыт.
        var bottomRadiusOpen: CGFloat = 11

        /// Отступ от верхней кромки экрана. Ноль — остров врастает в кромку,
        /// как аппаратный вырез на новых маках. Больше нуля — «летит» под ней.
        var floatingTopInset: CGFloat = 0
        /// Внутренние поля раскрытого острова.
        var contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16)
        /// Внутренние поля компактной карточки — она гораздо ниже.
        var compactPadding: EdgeInsets = EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 12)
    }

    // MARK: - Цвета

    struct Palette: Codable, Equatable {
        /// Цвет тела острова. Alpha меньше единицы делает остров
        /// полупрозрачным во всех состояниях, не только в раскрытом.
        var background: CodableColor = CodableColor(white: 0, alpha: 1)
        var primaryText: CodableColor = CodableColor(white: 1, alpha: 1)
        var secondaryText: CodableColor = CodableColor(white: 1, alpha: 0.6)
        var accent: CodableColor = CodableColor(red: 1, green: 0.42, blue: 0.21, alpha: 1)
        var progressTrack: CodableColor = CodableColor(white: 1, alpha: 0.22)
        var progressFill: CodableColor = CodableColor(white: 1, alpha: 0.85)
        /// Мягкое свечение по краю острова.
        var rimLight: CodableColor = CodableColor(white: 1, alpha: 0.16)
        var rimWidth: CGFloat = 0.6

        /// Показывать ли стекло в нижней части раскрытого острова.
        var useLiquidGlass: Bool = true
        /// Стиль нативного Liquid Glass. По умолчанию чистое стекло — таким
        /// его показывает док. Матовым его делает системный ползунок
        /// «Liquid Glass», а не мы.
        var glassStyle: GlassStyle = .clear
        /// Подкраска стекла.
        ///
        /// Без неё остров на светлом фоне выцветает: стекло становится почти
        /// белым, и белые кнопки на нём пропадают. Тёмная подкраска держит
        /// контраст при любом фоне и стеклом быть не мешает.
        var glassTint: CodableColor? = CodableColor(white: 0, alpha: 0.34)
        /// Отклик стекла на наведение и нажатие.
        var glassInteractive: Bool = true
        /// Отдавать ключ обратно сразу после отрисовки стекла.
        ///
        /// Проверка гипотезы: если система рисует стекло живым в момент
        /// композиции и дальше держит как есть, окно под островом почти не
        /// заметит потери фокуса. Если стекло гаснет вместе с ключом —
        /// значит цена неизбежна.
        var releaseKeyAfterGlass: Bool = true
        /// Через сколько отдавать ключ.
        var releaseKeyDelay: Double = 0.45

        /// Делать приложение активным, пока остров раскрыт.
        ///
        /// Полноценное жидкое стекло система рисует только активному
        /// приложению; фоновому достаётся приглушённый вариант, и переставить
        /// это снаружи нельзя — приватные поля вью в обоих случаях одинаковы.
        /// Цена — на время раскрытия меняется меню-бар.
        var activateForGlass: Bool = true
    }

    enum GlassStyle: String, Codable, CaseIterable {
        case regular, clear
    }

    // MARK: - Анимация

    struct Motion: Codable, Equatable {
        var openResponse: Double = 0.34
        var openDamping: Double = 0.95
        var closeResponse: Double = 0.28
        var closeDamping: Double = 1.0
        var contentResponse: Double = 0.24
        var contentDamping: Double = 1.0

        var open: Animation { .spring(response: openResponse, dampingFraction: openDamping) }
        var close: Animation { .spring(response: closeResponse, dampingFraction: closeDamping) }
        var content: Animation { .spring(response: contentResponse, dampingFraction: contentDamping) }
    }

    // MARK: - Поведение

    struct Behavior: Codable, Equatable {
        /// Раскрывать полностью по наведению. По умолчанию выключено:
        /// наведение только показывает трек, полный плеер — по клику.
        var expandOnHover: Bool = false
        /// Показывать ли трек при наведении.
        var hoverShowsMedia: Bool = true
        /// Задержка перед раскрытием, чтобы остров не дёргался от каждого движения.
        var hoverOpenDelay: Double = 0.45
        /// Задержка перед схлопыванием после ухода курсора.
        var hoverCloseDelay: Double = 0.35
        /// Показывать плашки системных событий.
        var showVolumeHUD: Bool = true
        var showBrightnessHUD: Bool = true
        var showPowerHUD: Bool = true
        /// Предупреждать о низком заряде.
        var showLowBatteryWarning: Bool = true
        /// При каком проценте предупреждать.
        var lowBatteryThreshold: Int = 20
        /// Сколько секунд висит предупреждение — дольше обычной плашки:
        /// на неё надо успеть нажать.
        var warningDuration: Double = 6
        /// Сколько секунд висит плашка.
        var hudDuration: Double = 1.6

        /// Показывать компактный вид при смене трека.
        var showLiveActivities: Bool = true
        /// Сколько секунд висит всплывающая активность.
        var liveActivityDuration: Double = 3.0
        /// Сворачивать раскрытый остров кликом мимо него.
        var dismissOnOutsideClick: Bool = true

        /// На каких экранах показывать остров.
        var displayMode: DisplayMode = .notchedOrMain
        /// Держать форму выреза даже на экранах без чёлки — остров врастает
        /// в кромку вместо того, чтобы висеть отдельной плашкой.
        var alwaysUseNotchShape: Bool = true
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
    var modules: [String] = ["media"]

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

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
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
