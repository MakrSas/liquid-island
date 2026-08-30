import SwiftUI
import Combine

/// Хранилище темы: читает JSON с диска, отдаёт его вью и следит за правками.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: IslandTheme

    private let url: URL
    private var watcher: DispatchSourceFileSystemObject?

    static let shared = ThemeStore()

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiquidIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("theme.json")

        theme = ThemeStore.read(from: url) ?? .default
        if !FileManager.default.fileExists(atPath: url.path) { write(theme) }
        startWatching()
    }

    private static func read(from url: URL) -> IslandTheme? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IslandTheme.self, from: data)
    }

    func update(_ transform: (inout IslandTheme) -> Void) {
        var copy = theme
        transform(&copy)
        theme = copy
        write(copy)
    }

    func reset() {
        theme = .default
        write(theme)
    }

    private func write(_ theme: IslandTheme) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(theme) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Правки theme.json подхватываются на лету — удобно подбирать вид.
    private func startWatching() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if let fresh = ThemeStore.read(from: self.url) { self.theme = fresh }
            // Многие редакторы пересоздают файл — перевешиваем наблюдателя.
            self.watcher?.cancel()
            self.watcher = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.startWatching() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    var configURL: URL { url }
}
