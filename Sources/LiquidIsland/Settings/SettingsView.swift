import SwiftUI

/// Окно настроек в духе системного: разделы слева, сгруппированные строки
/// справа. Каждая правка применяется сразу — остров перестраивается на лету,
/// поэтому кнопки «Применить» здесь нет и быть не должно.
struct SettingsView: View {
    @ObservedObject var store: ThemeStore
    @State private var pane: Pane? = .appearance
    @State private var previewPhase: IslandPhase = .expanded

    enum Pane: String, CaseIterable, Identifiable {
        case appearance, glass, motion, behavior, huds, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .appearance: return "Оформление"
            case .glass: return "Стекло"
            case .motion: return "Анимация"
            case .behavior: return "Поведение"
            case .huds: return "Плашки"
            case .about: return "О программе"
            }
        }

        var icon: String {
            switch self {
            case .appearance: return "paintpalette"
            case .glass: return "drop.halffull"
            case .motion: return "wand.and.rays"
            case .behavior: return "hand.tap"
            case .huds: return "speaker.wave.2"
            case .about: return "info.circle"
            }
        }

        var tint: Color {
            switch self {
            case .appearance: return .pink
            case .glass: return .cyan
            case .motion: return .purple
            case .behavior: return .orange
            case .huds: return .blue
            case .about: return .gray
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(.white)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(item.tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detail
                .navigationTitle(pane?.title ?? "Настройки")
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    @ViewBuilder
    private var detail: some View {
        Form {
            if pane != .about {
                Section {
                    SettingsPreview(store: store, phase: previewPhase)
                        .listRowInsets(EdgeInsets())
                    Picker("Состояние", selection: $previewPhase) {
                        Text("Покой").tag(IslandPhase.closed)
                        Text("Наведение").tag(IslandPhase.hovered)
                        Text("Раскрытый").tag(IslandPhase.expanded)
                    }
                    .pickerStyle(.segmented)
                }
            }

            switch pane ?? .appearance {
            case .appearance: AppearanceSection(store: store)
            case .glass: GlassSection(store: store)
            case .motion: MotionSection(store: store)
            case .behavior: BehaviorSection(store: store)
            case .huds: HUDSection(store: store)
            case .about: AboutSection(store: store)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Оформление

private struct AppearanceSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        Section("Размеры") {
            Stepper(value: store.sizeBinding(\.geometry.compactSize, axis: .width), in: 120...600, step: 4) {
                LabeledValue("Ширина карточки", store.theme.geometry.compactSize.width, unit: "pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.compactSize, axis: .height), in: 20...60, step: 1) {
                LabeledValue("Высота карточки", store.theme.geometry.compactSize.height, unit: "pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.expandedSize, axis: .width), in: 260...800, step: 4) {
                LabeledValue("Ширина раскрытого", store.theme.geometry.expandedSize.width, unit: "pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.expandedSize, axis: .height), in: 100...360, step: 4) {
                LabeledValue("Высота раскрытого", store.theme.geometry.expandedSize.height, unit: "pt")
            }
        }

        Section("Скругления") {
            SliderRow("Верхние углы", store.binding(\.geometry.topRadius), range: 0...24)
            SliderRow("Нижние в покое", store.binding(\.geometry.bottomRadiusClosed), range: 0...24)
            SliderRow("Нижние раскрытого", store.binding(\.geometry.bottomRadiusOpen), range: 0...40)
            SliderRow("Обложка", store.binding(\.geometry.artworkRadius), range: 0...16)
        }

        Section {
            ColorPicker("Тело острова", selection: store.colorBinding(\.palette.background))
            ColorPicker("Название", selection: store.colorBinding(\.palette.primaryText))
            ColorPicker("Исполнитель и время", selection: store.colorBinding(\.palette.secondaryText))
            ColorPicker("Кромка", selection: store.colorBinding(\.palette.rimLight))
            SliderRow("Толщина кромки", store.binding(\.palette.rimWidth), range: 0...2, format: "%.1f")
        } header: {
            Text("Цвета")
        } footer: {
            Text("Прозрачность тела делает остров полупрозрачным во всех состояниях, а не только в раскрытом.")
        }
    }
}

// MARK: - Стекло

private struct GlassSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        Section {
            Toggle("Жидкое стекло", isOn: store.binding(\.palette.useLiquidGlass))
            Picker("Стиль", selection: store.binding(\.palette.glassStyle)) {
                Text("Чистое").tag(IslandTheme.GlassStyle.clear)
                Text("Матовое").tag(IslandTheme.GlassStyle.regular)
            }
            Toggle("Отклик на курсор", isOn: store.binding(\.palette.glassInteractive))
        } footer: {
            Text("Плотность стекла задаётся системой — ползунком «Liquid Glass» в разделе «Внешний вид».")
        }

        Section {
            Toggle(
                "Тонировать стекло",
                isOn: store.isSet(\.palette.glassTint, fallback: CodableColor(white: 0, alpha: 0.34))
            )
            if store.theme.palette.glassTint != nil {
                ColorPicker(
                    "Цвет подкраски",
                    selection: store.optionalColorBinding(
                        \.palette.glassTint,
                        fallback: CodableColor(white: 0, alpha: 0.34)
                    )
                )
            }
        } header: {
            Text("Подкраска")
        } footer: {
            Text("Без подкраски остров выцветает на светлом фоне: стекло становится почти белым вместе с кнопками.")
        }

        Section("Переход") {
            SliderRow("Где чёрный начинает уходить", store.binding(\.geometry.glassFadeStart), range: 0...1, format: "%.2f")
            SliderRow("Где кончается", store.binding(\.geometry.glassFadeEnd), range: 0...1, format: "%.2f")
        }

        Section {
            Toggle("Забирать фокус для стекла", isOn: store.binding(\.palette.activateForGlass))
            Toggle("Возвращать сразу", isOn: store.binding(\.palette.releaseKeyAfterGlass))
            SliderRow("Через сколько вернуть", store.binding(\.palette.releaseKeyDelay), range: 0.05...1, format: "%.2f с")
        } header: {
            Text("Фокус")
        } footer: {
            Text("Система рисует жидкое стекло только в ключевом окне, поэтому остров забирает фокус на момент отрисовки и отдаёт обратно. С выключенным первым переключателем стекло станет плоским размытием.")
        }
    }
}

// MARK: - Анимация

private struct MotionSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        Section {
            SliderRow("Отклик", store.binding(\.motion.openResponse), range: 0.1...1, format: "%.2f с")
            SliderRow("Демпфирование", store.binding(\.motion.openDamping), range: 0.4...1, format: "%.2f")
            SpringCurve(response: store.theme.motion.openResponse, damping: store.theme.motion.openDamping)
        } header: {
            Text("Раскрытие")
        } footer: {
            Text("Демпфирование ниже 0.8 даёт заметную раскачку, единица — движение без отскока.")
        }

        Section("Сворачивание") {
            SliderRow("Отклик", store.binding(\.motion.closeResponse), range: 0.1...1, format: "%.2f с")
            SliderRow("Демпфирование", store.binding(\.motion.closeDamping), range: 0.4...1, format: "%.2f")
            SpringCurve(response: store.theme.motion.closeResponse, damping: store.theme.motion.closeDamping)
        }

        Section("Содержимое") {
            SliderRow("Отклик", store.binding(\.motion.contentResponse), range: 0.1...1, format: "%.2f с")
            SliderRow("Демпфирование", store.binding(\.motion.contentDamping), range: 0.4...1, format: "%.2f")
        }
    }
}

// MARK: - Поведение

private struct BehaviorSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        Section {
            Toggle("Показывать трек при наведении", isOn: store.binding(\.behavior.hoverShowsMedia))
            Toggle("Раскрывать по наведению", isOn: store.binding(\.behavior.expandOnHover))
            if store.theme.behavior.expandOnHover {
                SliderRow("Задержка раскрытия", store.binding(\.behavior.hoverOpenDelay), range: 0...2, format: "%.2f с")
            }
            SliderRow("Задержка сворачивания", store.binding(\.behavior.hoverCloseDelay), range: 0...2, format: "%.2f с")
        } header: {
            Text("Наведение")
        } footer: {
            Text("Раскрытый остров закрывается кликом мимо, а не уводом курсора.")
        }

        Section("Экран") {
            Picker("Показывать на", selection: store.binding(\.behavior.displayMode)) {
                Text("С чёлкой, иначе основной").tag(IslandTheme.DisplayMode.notchedOrMain)
                Text("Только основной").tag(IslandTheme.DisplayMode.main)
                Text("За курсором").tag(IslandTheme.DisplayMode.followMouse)
                Text("На всех").tag(IslandTheme.DisplayMode.all)
            }
            Toggle("Форма выреза без чёлки", isOn: store.binding(\.behavior.alwaysUseNotchShape))
            SliderRow("Отступ от кромки", store.binding(\.geometry.floatingTopInset), range: 0...20)
        }
    }
}

// MARK: - Плашки

private struct HUDSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        Section {
            Toggle("Громкость", isOn: store.binding(\.behavior.showVolumeHUD))
            Toggle("Яркость", isOn: store.binding(\.behavior.showBrightnessHUD))
            Toggle("Подключение зарядки", isOn: store.binding(\.behavior.showPowerHUD))
        } header: {
            Text("Показывать")
        } footer: {
            Text("Плашка питания срабатывает на подключение и отключение — уровень заряда меняется постоянно, и показывать её на каждый процент было бы шумом.")
        }

        Section("Вид") {
            SliderRow("Сколько висит", store.binding(\.behavior.hudDuration), range: 0.5...5, format: "%.1f с")
            Stepper(value: store.sizeBinding(\.geometry.hudSize, axis: .width), in: 160...480, step: 4) {
                LabeledValue("Ширина", store.theme.geometry.hudSize.width, unit: "pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.hudSize, axis: .height), in: 20...60, step: 1) {
                LabeledValue("Высота", store.theme.geometry.hudSize.height, unit: "pt")
            }
        }
    }
}

// MARK: - О программе

private struct AboutSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LiquidIsland").font(.title2.weight(.semibold))
                    Text("Открытый Dynamic Island для macOS")
                        .foregroundStyle(.secondary)
                    Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }

        Section {
            LabeledContent("Расположение") {
                Text(store.configURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Button("Открыть в редакторе") { NSWorkspace.shared.open(store.configURL) }
            Button("Сбросить оформление", role: .destructive) { store.reset() }
        } header: {
            Text("Файл темы")
        } footer: {
            Text("Файл читается на лету: правки в редакторе видны без перезапуска.")
        }
    }
}

// MARK: - Мелкие детали

/// Строка со ползунком и значением справа — как в системных настройках.
private struct SliderRow: View {
    let title: String
    let value: Binding<CGFloat>
    let range: ClosedRange<Double>
    var format: String = "%.0f"

    init(_ title: String, _ value: Binding<CGFloat>, range: ClosedRange<Double>, format: String = "%.0f") {
        self.title = title
        self.value = value
        self.range = range
        self.format = format
    }

    init(_ title: String, _ value: Binding<Double>, range: ClosedRange<Double>, format: String = "%.0f") {
        self.title = title
        self.value = Binding(
            get: { CGFloat(value.wrappedValue) },
            set: { value.wrappedValue = Double($0) }
        )
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = CGFloat($0) }
                    ),
                    in: range
                )
                .frame(minWidth: 160)
                Text(String(format: format, Double(value.wrappedValue)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

private struct LabeledValue: View {
    let title: String
    let value: CGFloat
    let unit: String

    init(_ title: String, _ value: CGFloat, unit: String) {
        self.title = title
        self.value = value
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            Text("\(Int(value)) \(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
