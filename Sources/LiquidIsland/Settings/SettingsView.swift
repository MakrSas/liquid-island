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
            case .appearance: return "paintbrush"
            case .glass: return "square.on.square.dashed"
            case .motion: return "waveform.path"
            case .behavior: return "cursorarrow.motionlines"
            case .huds: return "slider.horizontal.3"
            case .about: return "info.circle"
            }
        }

        /// Цвета взяты в тон системных Настроек: там почти всё синее и серое,
        /// а насыщенные оттенки достаются немногим разделам.
        var tint: Color {
            switch self {
            case .appearance: return Color(nsColor: .systemGray)
            case .glass: return Color(nsColor: .systemTeal)
            case .motion: return Color(nsColor: .systemIndigo)
            case .behavior: return Color(nsColor: .systemBlue)
            case .huds: return Color(nsColor: .systemRed)
            case .about: return Color(nsColor: .systemGray)
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
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 20, height: 20)
                            .background(
                                item.tint,
                                in: RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            )
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detail
                .navigationTitle(pane?.title ?? "Настройки")
                .toolbar {
                    if pane != .about {
                        ToolbarItem(placement: .principal) {
                            Picker("Состояние", selection: $previewPhase) {
                                Image(systemName: "capsule")
                                    .help("Покой")
                                    .tag(IslandPhase.closed)
                                Image(systemName: "cursorarrow")
                                    .help("Наведение")
                                    .tag(IslandPhase.hovered)
                                Image(systemName: "rectangle.expand.vertical")
                                    .help("Раскрытый")
                                    .tag(IslandPhase.expanded)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if pane != .about {
                // Превью закреплено: настраивая размеры и цвета, его нужно
                // видеть, а не искать прокруткой.
                SettingsPreview(store: store, phase: previewPhase)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            form
        }
    }

    @ViewBuilder
    private var form: some View {
        Form {
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
                Text("Ширина карточки: \(Int(store.theme.geometry.compactSize.width)) pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.compactSize, axis: .height), in: 20...60, step: 1) {
                Text("Высота карточки: \(Int(store.theme.geometry.compactSize.height)) pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.expandedSize, axis: .width), in: 260...800, step: 4) {
                Text("Ширина раскрытого: \(Int(store.theme.geometry.expandedSize.width)) pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.expandedSize, axis: .height), in: 100...360, step: 4) {
                Text("Высота раскрытого: \(Int(store.theme.geometry.expandedSize.height)) pt")
            }
        }

        Section("Скругления") {
            LabeledContent {
                Slider(value: store.binding(\.geometry.topRadius).double, in: 0...24)
            } label: {
                Text("Верхние углы")
                Text(String(format: "%.0f pt", Double(store.theme.geometry.topRadius)))
            }
            LabeledContent {
                Slider(value: store.binding(\.geometry.bottomRadiusClosed).double, in: 0...24)
            } label: {
                Text("Нижние в покое")
                Text(String(format: "%.0f pt", Double(store.theme.geometry.bottomRadiusClosed)))
            }
            LabeledContent {
                Slider(value: store.binding(\.geometry.bottomRadiusOpen).double, in: 0...40)
            } label: {
                Text("Нижние раскрытого")
                Text(String(format: "%.0f pt", Double(store.theme.geometry.bottomRadiusOpen)))
            }
            LabeledContent {
                Slider(value: store.binding(\.geometry.artworkRadius).double, in: 0...16)
            } label: {
                Text("Обложка")
                Text(String(format: "%.0f pt", Double(store.theme.geometry.artworkRadius)))
            }
        }

        Section {
            ColorPicker("Тело острова", selection: store.colorBinding(\.palette.background))
            ColorPicker("Название", selection: store.colorBinding(\.palette.primaryText))
            ColorPicker("Исполнитель и время", selection: store.colorBinding(\.palette.secondaryText))
            ColorPicker("Кромка", selection: store.colorBinding(\.palette.rimLight))
            LabeledContent {
                Slider(value: store.binding(\.palette.rimWidth).double, in: 0...2)
            } label: {
                Text("Толщина кромки")
                Text(String(format: "%.1f", Double(store.theme.palette.rimWidth)))
            }
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
            LabeledContent {
                Slider(value: store.binding(\.geometry.glassFadeStart).double, in: 0...1)
            } label: {
                Text("Где чёрный начинает уходить")
                Text(String(format: "%.2f", Double(store.theme.geometry.glassFadeStart)))
            }
            LabeledContent {
                Slider(value: store.binding(\.geometry.glassFadeEnd).double, in: 0...1)
            } label: {
                Text("Где кончается")
                Text(String(format: "%.2f", Double(store.theme.geometry.glassFadeEnd)))
            }
        }

        Section {
            Toggle("Забирать фокус для стекла", isOn: store.binding(\.palette.activateForGlass))
            Toggle("Возвращать сразу", isOn: store.binding(\.palette.releaseKeyAfterGlass))
            LabeledContent {
                Slider(value: store.binding(\.palette.releaseKeyDelay).double, in: 0.05...1)
            } label: {
                Text("Через сколько вернуть")
                Text(String(format: "%.2f с", Double(store.theme.palette.releaseKeyDelay)))
            }
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
            LabeledContent {
                Slider(value: store.binding(\.motion.openResponse).double, in: 0.1...1)
            } label: {
                Text("Отклик")
                Text(String(format: "%.2f с", Double(store.theme.motion.openResponse)))
            }
            LabeledContent {
                Slider(value: store.binding(\.motion.openDamping).double, in: 0.4...1)
            } label: {
                Text("Демпфирование")
                Text(String(format: "%.2f", Double(store.theme.motion.openDamping)))
            }
            SpringCurve(response: store.theme.motion.openResponse, damping: store.theme.motion.openDamping)
        } header: {
            Text("Раскрытие")
        } footer: {
            Text("Демпфирование ниже 0.8 даёт заметную раскачку, единица — движение без отскока.")
        }

        Section("Сворачивание") {
            LabeledContent {
                Slider(value: store.binding(\.motion.closeResponse).double, in: 0.1...1)
            } label: {
                Text("Отклик")
                Text(String(format: "%.2f с", Double(store.theme.motion.closeResponse)))
            }
            LabeledContent {
                Slider(value: store.binding(\.motion.closeDamping).double, in: 0.4...1)
            } label: {
                Text("Демпфирование")
                Text(String(format: "%.2f", Double(store.theme.motion.closeDamping)))
            }
            SpringCurve(response: store.theme.motion.closeResponse, damping: store.theme.motion.closeDamping)
        }

        Section("Содержимое") {
            LabeledContent {
                Slider(value: store.binding(\.motion.contentResponse).double, in: 0.1...1)
            } label: {
                Text("Отклик")
                Text(String(format: "%.2f с", Double(store.theme.motion.contentResponse)))
            }
            LabeledContent {
                Slider(value: store.binding(\.motion.contentDamping).double, in: 0.4...1)
            } label: {
                Text("Демпфирование")
                Text(String(format: "%.2f", Double(store.theme.motion.contentDamping)))
            }
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
                LabeledContent {
                Slider(value: store.binding(\.behavior.hoverOpenDelay).double, in: 0...2)
            } label: {
                Text("Задержка раскрытия")
                Text(String(format: "%.2f с", Double(store.theme.behavior.hoverOpenDelay)))
            }
            }
            LabeledContent {
                Slider(value: store.binding(\.behavior.hoverCloseDelay).double, in: 0...2)
            } label: {
                Text("Задержка сворачивания")
                Text(String(format: "%.2f с", Double(store.theme.behavior.hoverCloseDelay)))
            }
        } header: {
            Text("Наведение")
            Toggle("Сворачивать кликом мимо", isOn: store.binding(\.behavior.dismissOnOutsideClick))
        } footer: {
            Text("Раскрытый остров не сворачивается от увода курсора — только кликом мимо него или переходом в другое приложение.")
        }

        Section("Экран") {
            Picker("Показывать на", selection: store.binding(\.behavior.displayMode)) {
                Text("С чёлкой, иначе основной").tag(IslandTheme.DisplayMode.notchedOrMain)
                Text("Только основной").tag(IslandTheme.DisplayMode.main)
                Text("За курсором").tag(IslandTheme.DisplayMode.followMouse)
                Text("На всех").tag(IslandTheme.DisplayMode.all)
            }
            Toggle("Форма выреза без чёлки", isOn: store.binding(\.behavior.alwaysUseNotchShape))
            LabeledContent {
                Slider(value: store.binding(\.geometry.floatingTopInset).double, in: 0...20)
            } label: {
                Text("Отступ от кромки")
                Text(String(format: "%.0f pt", Double(store.theme.geometry.floatingTopInset)))
            }
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
            LabeledContent {
                Slider(value: store.binding(\.behavior.hudDuration).double, in: 0.5...5)
            } label: {
                Text("Сколько висит")
                Text(String(format: "%.1f с", Double(store.theme.behavior.hudDuration)))
            }
            Stepper(value: store.sizeBinding(\.geometry.hudSize, axis: .width), in: 160...480, step: 4) {
                Text("Ширина: \(Int(store.theme.geometry.hudSize.width)) pt")
            }
            Stepper(value: store.sizeBinding(\.geometry.hudSize, axis: .height), in: 20...60, step: 1) {
                Text("Высота: \(Int(store.theme.geometry.hudSize.height)) pt")
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
            Button("Сбросить оформление") { store.reset() }
        } header: {
            Text("Файл темы")
        } footer: {
            Text("Файл читается на лету: правки в редакторе видны без перезапуска.")
        }
    }
}
