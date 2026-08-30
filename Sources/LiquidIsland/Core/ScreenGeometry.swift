import AppKit

/// Описывает физический вырез (или его отсутствие) на конкретном экране.
struct NotchMetrics: Equatable {
    /// Есть ли у экрана настоящая аппаратная чёлка.
    var hasHardwareNotch: Bool
    /// Размер выреза в координатах экрана (points).
    var notchSize: CGSize
    /// Высота меню-бара — по ней выравниваем «закрытое» состояние на маках без чёлки.
    var menuBarHeight: CGFloat

    /// Размер «пилюли» в закрытом состоянии.
    var closedSize: CGSize {
        if hasHardwareNotch { return notchSize }
        return CGSize(width: 148, height: max(menuBarHeight - 6, 22))
    }

    static func measure(for screen: NSScreen) -> NotchMetrics {
        let menuBar = NSStatusBar.system.thickness
        let safeTop = screen.safeAreaInsets.top

        // На маках с чёлкой safeAreaInsets.top > 0, а слева/справа от выреза
        // остаются вспомогательные области меню-бара.
        if safeTop > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchMetrics(
                hasHardwareNotch: true,
                notchSize: CGSize(width: width, height: safeTop),
                menuBarHeight: menuBar
            )
        }

        return NotchMetrics(
            hasHardwareNotch: false,
            notchSize: .zero,
            menuBarHeight: menuBar
        )
    }
}

@MainActor
extension NSScreen {
    /// Экран, на котором сейчас находится курсор.
    static var withMouse: NSScreen? {
        let point = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// Экран со встроенной чёлкой, если такой подключён.
    static var withNotch: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// Главный актор обязателен: с macOS 15 `deviceDescription` изолирован им,
    /// и обращение со стороны роняет процесс.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
