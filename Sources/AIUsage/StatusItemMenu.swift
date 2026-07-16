import SwiftUI
import AppKit

enum WindowBridge {
    static var openWindow: OpenWindowAction?
    static var openSettings: OpenSettingsAction?
    static weak var store: UsageStore?
}

enum ActivationPolicy {
    static func windowAppeared() {
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowClosed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let stillOpen = NSApp.windows.contains { w in
                let cls = String(describing: type(of: w))
                return w.isVisible
                    && w.styleMask.contains(.titled)
                    && !cls.contains("StatusBar")
                    && !cls.contains("MenuBarExtra")
                    && !cls.contains("Popover")
            }
            if !stillOpen {
                _ = NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

final class StatusItemRightClickHandler: NSObject {
    static let shared = StatusItemRightClickHandler()
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self,
                  let window = event.window,
                  String(describing: type(of: window)).contains("StatusBarWindow")
            else { return event }
            let isCtrlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            guard event.type == .rightMouseDown || isCtrlClick else { return event }
            self.showMenu(under: window)
            return nil
        }
    }

    private func showMenu(under window: NSWindow) {
        let menu = NSMenu()

        let open = NSMenuItem(title: L.t("Abrir AI Usage", "Open AI Usage"), action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let refresh = NSMenuItem(title: L.t("Actualizar ahora", "Refresh now"), action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: L.t("Ajustes…", "Settings…"), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L.t("Salir completamente", "Quit completely"), action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: window.frame.minX, y: window.frame.minY - 2),
                   in: nil)
    }

    @objc private func openPanel() {
        WindowBridge.openWindow?(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        ActivationPolicy.windowAppeared()
        WindowBridge.openSettings?()
    }

    @objc private func refreshNow() {
        WindowBridge.store?.refresh()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
