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
    func resume() { dismissed = false; refresh(activation: true) }
    func refresh(activation: Bool = false) {
        model.permissionGranted = model.delivery.trusted
        model.screenPermissionGranted = CGPreflightScreenCaptureAccess()
        guard !model.busy, !model.showEditor, NSApp.modalWindow == nil, let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard InputPolicy.supportedBundles.contains(app.bundleIdentifier ?? "") else {
            lastPID = nil; dismissed = false; lastWindow = nil
            model.delivery.clear(); model.targetName = "未绑定 Codex"
            if model.autoShow { panel.orderOut(nil) }
            return
        }
        model.delivery.remember(app)
        model.targetName = app.localizedName ?? "Codex"
        guard model.autoShow else { return }
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
        let width = (Preferences.defaults.object(forKey:"sidebarPreferredWidth") as? NSNumber).map { CGFloat($0.doubleValue) }
        let height = (Preferences.defaults.object(forKey:"sidebarPreferredHeight") as? NSNumber).map { CGFloat($0.doubleValue) }
        panel.setFrame(SidebarPlacement.frame(host: rect, visible: screen.visibleFrame,preferredWidth:width,preferredHeight:height), display: true)
    }
}
