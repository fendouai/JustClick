import AppKit
import JustClickCore

/// Window tracking reads AX geometry only; conversation text is read on a click.
@MainActor
final class Companion {
    let model: Model
    let panel: PromptPanel
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var dismissed = false
    private var lastPID: pid_t?
    var isPositioning = false
    private var lastWindow: CGRect?

    init(model: Model, panel: PromptPanel) { self.model = model; self.panel = panel }
    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(activation: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh(activation: true)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observer = nil
    }
    func dismiss() { dismissed = true; panel.orderOut(nil) }
    func closeMenu() {
        model.collapsed = true
        if model.menuBarOnly { dismiss() }
    }
    func resume() { dismissed = false; refresh(activation: true) }
    func refresh(activation: Bool = false) {
        model.permissionGranted = model.delivery.trusted
        model.screenPermissionGranted = CGPreflightScreenCaptureAccess()
        guard !model.busy, !model.showEditor, NSApp.modalWindow == nil, let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard InputPolicy.supportedBundles.contains(app.bundleIdentifier ?? "") else {
            lastPID = nil; dismissed = false; lastWindow = nil
            model.delivery.clear(); model.targetName = "未绑定 Codex"
            if model.autoShow && !model.keepExpanded { model.collapsed = true; panel.orderOut(nil) }
            return
        }
        model.delivery.remember(app)
        let title: String? = model.delivery.window(for: app).flatMap { AX.value($0, kAXTitleAttribute) }
        model.targetName = (app.localizedName ?? "Codex") + (title.flatMap { $0.isEmpty ? nil : " · " + $0 } ?? "")
        guard model.autoShow, !model.menuBarOnly else { return }
        let changedApp = lastPID != app.processIdentifier
        lastPID = app.processIdentifier
        if activation || changedApp { dismissed = false }
        guard !dismissed else { return }
        let geometry = model.delivery.windowFrame
        if changedApp || geometry != lastWindow || !panel.isVisible {
            lastWindow = geometry
            position(geometry)
        }
        // Does not activate JustClick or take the composer's keyboard focus.
        panel.orderFront(nil)
    }
    func position(_ axFrame: CGRect?) {
        guard let primary = NSScreen.screens.first else { return }
        let host = axFrame.map { CGRect(x: $0.minX, y: primary.frame.maxY - $0.maxY, width: $0.width, height: $0.height) }
        let screen = host.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } } ?? NSScreen.main ?? primary
        let rect = host ?? CGRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY, width: screen.visibleFrame.width - 350, height: screen.visibleFrame.height)
        isPositioning = true
        defer { isPositioning = false }
        let visible = screen.visibleFrame
        let offsetX = Preferences.defaults.object(forKey: "anchorX") as? Double ?? 1
        let offsetY = Preferences.defaults.object(forKey: "anchorY") as? Double ?? 0.5
        let anchor = CGPoint(x: min(max(rect.minX + rect.width * offsetX - 28, visible.minX), visible.maxX - 28),
                             y: min(max(rect.minY + rect.height * offsetY, visible.minY), visible.maxY - 28))
        let size: NSSize
        if model.collapsed { size = NSSize(width: 28, height: 28) }
        else if model.keepExpanded {
            size = NSSize(width: min(visible.width, CGFloat(Preferences.defaults.object(forKey: "quickPreferredWidth") as? Double ?? 360)),
                          height: min(visible.height, CGFloat(Preferences.defaults.object(forKey: "quickPreferredHeight") as? Double ?? 590)))
        } else { size = NSSize(width: min(280, visible.width), height: min(390, visible.height)) }
        panel.minSize = model.collapsed ? NSSize(width: 28, height: 28) : NSSize(width: 260, height: 320)
        let origin = model.collapsed ? anchor : CGPoint(x: max(visible.minX, anchor.x + 28 - size.width),
                                                        y: min(max(anchor.y + 28 - size.height, visible.minY), visible.maxY - size.height))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
    func rememberPosition() {
        guard !isPositioning, model.collapsed, let primary = NSScreen.screens.first else { return }
        let ax = model.delivery.windowFrame
        let host = ax.map { CGRect(x: $0.minX, y: primary.frame.maxY - $0.maxY, width: $0.width, height: $0.height) } ?? (panel.screen ?? primary).visibleFrame
        guard host.width > 0, host.height > 0 else { return }
        Preferences.defaults.set(Double((panel.frame.minX + 28 - host.minX) / host.width), forKey: "anchorX")
        Preferences.defaults.set(Double((panel.frame.minY - host.minY) / host.height), forKey: "anchorY")
    }
}
