import AppKit
import SwiftUI
import Carbon
import JustClickCore

final class PromptPanel: NSPanel {
    var dismissSidebar: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissSidebar?(); orderOut(nil) }
    override func close() { dismissSidebar?(); orderOut(nil) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = Model()
    var status: NSStatusItem!
    var panel: PromptPanel!
    var hotKey: EventHotKeyRef?
    var hotKeyConflict = false
    var handler: EventHandlerRef?
    var keyboardMonitor: Any?
    var companion: Companion?
    var reopenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        reopenObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("local.justclick.show-sidebar"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPicker(capture: true) }
        }
        configureMainMenu()
        panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.delegate = self
        panel.minSize = NSSize(width:320,height:480)
        model.resetWindowSize = { [weak self] in
            Preferences.defaults.removeObject(forKey:"sidebarPreferredWidth")
            Preferences.defaults.removeObject(forKey:"sidebarPreferredHeight")
            guard let self else { return }
            self.companion?.position(self.model.delivery.windowFrame)
        }
        panel.title = "JustClick — 提示词侧栏"
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: PickerView(model: model))
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, !self.model.showEditor, self.model.page == .library,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            // NSTextField consumes arrows before SwiftUI's onMoveCommand.
            if event.keyCode == UInt16(kVK_DownArrow) { self.model.move(1); return nil }
            if event.keyCode == UInt16(kVK_UpArrow) { self.model.move(-1); return nil }
            if event.keyCode == UInt16(kVK_Escape) { self.companion?.dismiss(); self.panel.orderOut(nil); return nil }
            return event
        }
        model.hide = { [weak self] in self?.companion?.dismiss(); self?.panel.orderOut(nil) }
        model.refreshMenu = { [weak self] in
            self?.buildMenu()
            
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "text.badge.bolt", accessibilityDescription: "JustClick 提示词")
        if status.button?.image == nil { status.button?.title = "JC" }
        buildMenu(); registerHotKey()
        companion = Companion(model: model, panel: panel)
        panel.dismissSidebar = { [weak self] in self?.companion?.dismiss() }
        model.refreshCompanion = { [weak self] in self?.companion?.resume() }
        if !CommandLine.arguments.contains("--smoke-test") { companion?.start() }
        if CommandLine.arguments.contains("--show") { showPicker(capture: true) }
        if CommandLine.arguments.contains("--smoke-test") {
            showPicker(capture: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                let board = NSPasteboard.withUniqueName()
                let sample = "JustClick 验证\n保留多行与 Unicode ✨"
                let clipboardRoundTrip = Delivery(pasteboard: board).copy(sample) && board.string(forType: .string) == sample
                board.releaseGlobally()
                var modelRoundTrip = false
                if ProcessInfo.processInfo.environment["JUSTCLICK_DATA_DIR"] != nil {
                    let original = self.model.library
                    let probe = Prompt(title: "native-check", body: sample, category: "测试")
                    let saved = self.model.save(probe)
                    let diskMatches = (try? self.model.file.load().prompts.contains(probe)) == true
                    self.model.query = "native-check"
                    let searchMatches = self.model.results.map(\.id) == [probe.id]
                    self.model.query = ""
                    let restored = self.model.persist(original)
                    self.model.selected = self.model.results.first?.id
                    modelRoundTrip = saved && diskMatches && searchMatches && restored
                }
                let result: [String: Any] = [
                    "windowVisible": self.panel.isVisible,
                    "promptCount": self.model.library.prompts.count,
                    "builtinCount": Builtins.prompts.count,
                    "menuItems": self.status.menu?.items.count ?? 0,
                    "hotKeyRegistered": self.hotKey != nil,
                    "hotKeyConflictReported": self.hotKeyConflict,
                    "sidebarWidth": self.panel.frame.width,
                    "automaticModeEnabled": self.model.autoShow,
                    "accessibilityTrusted": self.model.delivery.trusted,
                    "clipboardRoundTrip": clipboardRoundTrip,
                    "modelRoundTrip": modelRoundTrip,
                    "editingMenuReady": NSApp.mainMenu?.items.contains(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSText.paste(_:)) }) == true }) == true,
                    "dataFile": self.model.file.url.path
                ]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                    FileHandle.standardOutput.write(data); print("")
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quit = NSMenuItem(title: "退出 JustClick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit); applicationItem.submenu = applicationMenu; main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; edit.insertItem(redo, at: 1)
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func buildMenu() {
        let menu = NSMenu(); menu.delegate = self
        add("打开提示词菜单  ⌃⌥P", action: #selector(openPicker), to: menu)
        menu.addItem(.separator())
        for prompt in model.results.prefix(12) {
            let item = NSMenuItem(title: prompt.title, action: #selector(usePrompt(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = prompt.id.uuidString; item.toolTip = prompt.body
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let result = NSMenuItem(title: model.t(model.message), action: nil, keyEquivalent: ""); result.isEnabled = false; menu.addItem(result)
        add("新增提示词…", action: #selector(addPrompt), to: menu)
        add("开启辅助功能权限…", action: #selector(access), to: menu)
        add("退出 JustClick", action: #selector(quit), to: menu)
        status.menu = menu
    }
    func menuWillOpen(_ menu: NSMenu) { model.delivery.remember(NSWorkspace.shared.frontmostApplication) }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: model.t(title), action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    @objc func openPicker() { showPicker(capture: false) }
    @objc func addPrompt() { showPicker(capture: false); model.edit() }
    @objc func usePrompt(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let prompt = model.library.prompts.first(where: { $0.id.uuidString == id }) else { return }
        model.use(prompt)
    }
    @objc func access() { model.delivery.requestAccess() }
    @objc func quit() { NSApp.terminate(nil) }
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        Preferences.defaults.set(Double(window.frame.width),forKey:"sidebarPreferredWidth")
        Preferences.defaults.set(Double(window.frame.height),forKey:"sidebarPreferredHeight")
    }

    func showPicker(capture: Bool) {
        if capture { model.delivery.capture() }
        model.query = ""; model.category = nil; model.selected = model.results.first?.id
        companion?.position(model.delivery.windowFrame)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func toggle() {
        if panel.isVisible && panel.isKeyWindow { companion?.dismiss(); panel.orderOut(nil) }
        else { showPicker(capture: true) }
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.toggle() }
            return noErr
        }
        let install = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                                         Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard install == noErr else { model.message = "快捷键注册失败，仍可使用菜单栏。"; return }
        let id = EventHotKeyID(signature: OSType(0x4A434C4B), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id,
                                        GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr {
            hotKeyConflict = result == OSStatus(eventHotKeyExistsErr)
            model.message = "⌃⌥P 注册失败（\(result)），自动侧栏和菜单栏仍可用。"; buildMenu()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPicker(capture: true); return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        Preferences.cleanUpTestDomain()
        companion?.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let reopenObserver { DistributedNotificationCenter.default().removeObserver(reopenObserver) }
    }
}

@main
enum JustClickApp {
    @MainActor static func main() {
        if !CommandLine.arguments.contains("--smoke-test"), let bundle = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.justclick.show-sidebar"), object: nil, userInfo: nil, deliverImmediately: true)
            existing.activate(options: [])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
