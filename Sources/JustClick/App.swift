import AppKit
import SwiftUI
import Carbon
import JustClickCore

final class PromptPanel: NSPanel {
    var dismissSidebar: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissSidebar?() }
    override func close() { dismissSidebar?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = Model()
    var status: NSStatusItem!
    var panel: PromptPanel!
    var manager: NSWindow!
    var hotKey: EventHotKeyRef?
    var hotKeyConflict = false
    var handler: EventHandlerRef?
    var keyboardMonitor: Any?
    var outsideMonitor: Any?
    var localMouseMonitor: Any?
    var companion: Companion?
    var reopenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        reopenObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("local.justclick.show-sidebar"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPicker(capture: true) }
        }
        configureMainMenu()
        panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.delegate = self
        panel.minSize = NSSize(width:28,height:28)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true
        model.resetWindowSize = { [weak self] in
            Preferences.defaults.removeObject(forKey:"quickPreferredWidth")
            Preferences.defaults.removeObject(forKey:"quickPreferredHeight")
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
        panel.contentView = NSHostingView(rootView: QuickPanelView(model: model))
        manager = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 780),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        manager.title = "JustClick"
        manager.minSize = NSSize(width: 420, height: 600)
        manager.isReleasedWhenClosed = false
        manager.contentView = NSHostingView(rootView: PickerView(model: model))
        manager.center()
        model.openManager = { [weak self] page in
            guard let self else { return }
            self.model.query = ""; self.model.category = nil; self.model.page = page
            if page == .discovery { self.model.openDiscovery() }
            self.manager.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        model.resizeQuick = { [weak self] in
            guard let self else { return }
            if self.model.keepExpanded && !self.model.collapsed { self.panel.styleMask.insert(.resizable) }
            else { self.panel.styleMask.remove(.resizable) }
            self.companion?.position(self.model.delivery.windowFrame)
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, !self.model.showEditor,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            // NSTextField consumes arrows before SwiftUI's onMoveCommand.
            if event.keyCode == UInt16(kVK_DownArrow) { self.moveQuick(1); return nil }
            if event.keyCode == UInt16(kVK_UpArrow) { self.moveQuick(-1); return nil }
            if event.keyCode == UInt16(kVK_Escape) { self.companion?.closeMenu(); return nil }
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
        model.collapsed = !model.keepExpanded
        panel.dismissSidebar = { [weak self] in self?.companion?.closeMenu() }
        model.anchorMoved = { [weak self] in self?.companion?.rememberPosition() }
        model.closeQuick = { [weak self] in self?.companion?.closeMenu() }
        model.modeChanged = { [weak self] in
            guard let self else { return }
            if self.model.menuBarOnly { self.companion?.dismiss() }
            else { self.model.collapsed = true; self.companion?.resume() }
            self.buildMenu()
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.keepExpanded, !self.model.busy else { return }
                self.companion?.closeMenu()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window === self.manager, !self.model.keepExpanded, !self.model.busy { self.companion?.closeMenu() }
            return event
        }
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
                    let originalLanguage = self.model.language
                    self.model.language = .zh
                    let chineseQuick = self.model.quickResults.count == 8 && self.model.quickResults.allSatisfy { $0.effectiveLanguage == .zh }
                    self.model.language = .en
                    let englishQuick = self.model.quickResults.count == 8 && self.model.quickResults.allSatisfy { $0.effectiveLanguage == .en }
                    self.model.language = originalLanguage
                    self.model.query = "no-management-match"
                    let independentSearch = self.model.quickResults.count == 8
                    self.model.query = ""
                    self.model.collapsed = true
                    let collapsedWidth = self.panel.frame.width == 28 && self.panel.frame.height == 28
                    self.model.collapsed = false
                    let fivePrompts = self.model.visibleQuickResults.count == 5
                    self.model.menuBarOnly = true
                    let menuModeHidden = !self.panel.isVisible
                    self.showPicker(capture: false)
                    self.companion?.closeMenu()
                    let menuModeClosed = !self.panel.isVisible
                    self.model.menuBarOnly = false
                    self.showPicker(capture: false)
                    self.model.collapsed = false
                    let expandedWidth = self.panel.frame.width >= 260
                    let stableOrder = self.model.quickResults.map(\.id)
                    if let prompt = self.model.quickResults.last { self.model.recordUsage(prompt) }
                    let stableAfterUsage = stableOrder == self.model.quickResults.map(\.id)
                    let probe = Prompt(title: "native-check", body: sample, category: "测试")
                    let saved = self.model.save(probe)
                    let diskMatches = (try? self.model.file.load().prompts.contains(probe)) == true
                    self.model.query = "native-check"
                    let searchMatches = self.model.results.map(\.id) == [probe.id]
                    self.model.query = ""
                    let restored = self.model.persist(original)
                    self.model.restoreQuickOrder()
                    self.model.selected = self.model.results.first?.id
                    modelRoundTrip = saved && diskMatches && searchMatches && restored && stableAfterUsage && chineseQuick && englishQuick && independentSearch && collapsedWidth && expandedWidth && fivePrompts && menuModeHidden && menuModeClosed
                }
                let result: [String: Any] = [
                    "windowVisible": self.panel.isVisible,
                    "quickCount": self.model.quickResults.count,
                    "managerAvailable": self.manager.contentView != nil,
                    "quickWidth": self.panel.frame.width,
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
        add(model.language == .zh ? "仅菜单栏模式" : "Menu bar only", action: #selector(toggleMenuOnly), to: menu)
        menu.items.last?.state = model.menuBarOnly ? .on : .off
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
    @objc func addPrompt() { model.openManager?(.library); model.edit() }
    @objc func usePrompt(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let prompt = model.library.prompts.first(where: { $0.id.uuidString == id }) else { return }
        model.use(prompt)
    }
    @objc func toggleMenuOnly() { model.menuBarOnly.toggle() }
    @objc func access() { model.delivery.requestAccess() }
    @objc func quit() { NSApp.terminate(nil) }
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel,
              NSApp.currentEvent?.type == .leftMouseDragged else { return }
        companion?.rememberPosition()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel, !model.collapsed else { return }
        Preferences.defaults.set(Double(window.frame.width),forKey:"quickPreferredWidth")
        Preferences.defaults.set(Double(window.frame.height),forKey:"quickPreferredHeight")
    }

    func moveQuick(_ delta: Int) {
        let items = model.visibleQuickResults
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == model.quickSelected } ?? 0
        model.quickSelected = items[max(0, min(items.count - 1, index + delta))].id
    }
    func showPicker(capture: Bool) {
        model.collapsed = false
        if capture { model.delivery.capture() }
        model.quickQuery = ""; model.quickSelected = model.quickResults.first?.id
        companion?.position(model.delivery.windowFrame)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func toggle() {
        if panel.isVisible && panel.isKeyWindow && !model.collapsed { companion?.closeMenu() }
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
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
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
