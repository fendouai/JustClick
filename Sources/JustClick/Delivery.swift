import AppKit
import ApplicationServices
import JustClickCore
import JustClickPasteKit
import ScreenCaptureKit

@MainActor
final class Delivery: PasteBackend {
    struct Target {
        let app: NSRunningApplication
        let element: AXUIElement
        let window: AXUIElement
        let context: String
        let windowFrame: CGRect?
    }
    struct Result {
        let message: String
        var uncertain = false
        var succeeded = false
    }
    private(set) var target: Target?
    private(set) var sourceApp: NSRunningApplication?
    private var preparationIssue = "尚未绑定窗口"
    private let pasteboard: NSPasteboard
    private var rememberedFocus: Target?
    private var sessionWindow: AXUIElement?
    private var sessionContext = ""
    private var sessionProbes: [AX.Node] = []
    private var tokens: [String: Target] = [:]
    private var clipboardTransaction: ClipboardTransaction?
    private var focusCheckedAt = Date.distantPast
    private var visualCandidate: VisualComposer?
    private var visualDiagnostics = ""
    private var positionCache: VisualPositionCache?
    private var cachedWindow: AXUIElement?
    private var cachedPID: pid_t?
    private var cachedContext = ""
    private var cachedProbes: [AX.Node] = []
    private func invalidatePositionCache() { positionCache = nil; cachedWindow = nil; cachedPID = nil; cachedProbes = [] }
    private func cachePosition(_ candidate: VisualComposer, image: CGImage) {
        positionCache = VisualPositionCache(composer:candidate,image:image)
        cachedWindow = sessionWindow; cachedPID = sourceApp?.processIdentifier
        cachedContext = sessionContext; cachedProbes = sessionProbes
    }
    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var trusted: Bool { AXIsProcessTrusted() }
    var windowFrame: CGRect? {
        guard trusted, let sourceApp, let window = window(for: sourceApp) else { return nil }
        return AX.frame(window)
    }

    func remember(_ app: NSRunningApplication?) {
        guard let app, InputPolicy.supportedBundles.contains(app.bundleIdentifier ?? "") else { return }
        if sourceApp?.processIdentifier != app.processIdentifier { target = nil; rememberedFocus = nil; invalidatePositionCache() }
        sourceApp = app
        captureOriginalFocus()
    }
    func clear() { sourceApp = nil; target = nil; rememberedFocus = nil; tokens = [:]; invalidatePositionCache() }
    func capture() {
        remember(NSWorkspace.shared.frontmostApplication)
        target = prepare()
    }
    func window(for app: NSRunningApplication) -> AXUIElement? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        if let window: AXUIElement = AX.value(root, kAXFocusedWindowAttribute) ?? AX.value(root, kAXMainWindowAttribute) { return window }
        let windows: [AXUIElement] = AX.value(root, kAXWindowsAttribute) ?? []
        let visible = windows.filter { (AX.value($0, kAXMinimizedAttribute) as Bool?) != true && AX.frame($0) != nil }
        return visible.count == 1 ? visible.first : nil
    }
    private func context(_ window: AXUIElement, nodes: [AX.Node]) -> String {
        let title: String = AX.value(window, kAXTitleAttribute) ?? ""
        let headings = nodes.filter { !($0.excluded) && $0.role == "AXHeading" }
            .prefix(3).map { AX.text($0.element) ?? AX.label($0.element) }
        let selected = nodes.filter { node in
            let role = node.role
            guard !node.excluded, ["AXRow", "AXButton", "AXRadioButton"].contains(role) else { return false }
            let isSelected: Bool = AX.value(node.element, kAXSelectedAttribute) ?? false
            return !node.excluded && isSelected && ["AXRow", "AXButton", "AXRadioButton"].contains(role)
        }.prefix(4).map { AX.label($0.element) }
        return ([title] + headings + selected).joined(separator: "\u{001F}")
    }
    private func prepare() -> Target? {
        preparationIssue = "无法取得目标 App 或窗口"
        guard trusted, let app = sourceApp, !app.isTerminated,
              InputPolicy.supportedBundles.contains(app.bundleIdentifier ?? ""), let window = window(for: app) else { return nil }
        let nodes = AX.nodes(window)
        let outer = AX.frame(window)
        let buttons = nodes.filter { !$0.excluded && $0.role == "AXButton" }
        let candidates = nodes.filter { node in
            let role = node.role
            guard !node.excluded, ["AXTextArea", "AXTextField"].contains(role) else { return false }
            let enabled: Bool = AX.value(node.element, kAXEnabledAttribute) ?? true
            let secure = (AX.value(node.element, kAXSubroleAttribute) as String?) == "AXSecureTextField"
            guard let rect = AX.frame(node.element), rect.width > 80, rect.height > 15,
                  let outer, outer.intersects(rect) else { return false }
            let pairedButton = buttons.contains { button in
                let name = AX.label(button.element).lowercased()
                guard ComposerPolicy.sendKind(name) != nil || name.contains("stop") || name.contains("停止"),
                      let buttonRect = AX.frame(button.element) else { return false }
                return buttonRect.midX >= rect.midX - 20 && buttonRect.midX <= rect.maxX + 120
                    && buttonRect.midY >= rect.minY - 30 && buttonRect.midY <= rect.maxY + 120
            }
            // Some empty composers expose dictation/add controls but no named Send button.
            // Require both opposite-side anchors, not a microphone elsewhere in the window.
            let nearby = buttons.filter { button in
                guard let buttonRect = AX.frame(button.element) else { return false }
                return buttonRect.midY >= rect.minY - 30 && buttonRect.midY <= rect.maxY + 120
                    && buttonRect.midX >= rect.minX - 40 && buttonRect.midX <= rect.maxX + 120
            }
            let leftAdd = nearby.contains { button in
                let name = AX.label(button.element).lowercased()
                guard let buttonRect = AX.frame(button.element), buttonRect.midX < rect.midX else { return false }
                return ["add files", "attach", "附件", "添加文件", "添加附件"].contains(where: name.contains)
                    || name.trimmingCharacters(in: .whitespacesAndNewlines) == "+"
            }
            let rightDictation = nearby.contains { button in
                let name = AX.label(button.element).lowercased()
                guard let buttonRect = AX.frame(button.element), buttonRect.midX >= rect.midX else { return false }
                return ["dictat", "microphone", "麦克风", "语音输入"].contains(where: name.contains)
            }
            let structural = rect.width >= 180 && rect.midY >= outer.minY + outer.height * 0.65
                && (pairedButton || (leftAdd && rightDictation))
            guard ComposerPolicy.isComposer(role: role, label: AX.label(node.element), enabled: enabled,
                                            editable: AX.editable(node.element), secure: secure, excludedAncestor: node.excluded, structuralMatch: structural) else { return false }
            return true
        }
        // Ambiguous composers (for example a side chat) must not be guessed.
        preparationIssue = candidates.isEmpty ? "没有识别到可编辑的主聊天输入框" : "识别到多个输入框，无法确定主聊天"
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        return Target(app: app, element: candidate.element, window: window,
                      context: context(window, nodes: nodes), windowFrame: AX.frame(window))
    }
    private func matches(_ target: Target) -> Bool {
        guard sourceApp?.processIdentifier == target.app.processIdentifier, !target.app.isTerminated,
              let sessionWindow, CFEqual(sessionWindow, target.window), target.context == sessionContext else { return false }
        return scopeMatches()
    }
    func copy(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    private func captureOriginalFocus() {
        guard trusted, let app = sourceApp,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              Date().timeIntervalSince(focusCheckedAt) >= 1 else { return }
        focusCheckedAt = Date()
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused: AXUIElement = AX.value(root, kAXFocusedUIElementAttribute),
              let focusedWindow: AXUIElement = AX.value(focused, kAXWindowAttribute),
              let current = window(for: app), CFEqual(focusedWindow, current),
              let rect = AX.frame(focused), let outer = AX.frame(current) else { return }
        if let rememberedFocus, CFEqual(rememberedFocus.element, focused), CFEqual(rememberedFocus.window, current),
           rememberedFocus.context.components(separatedBy: "\u{001F}").first == (AX.value(current, kAXTitleAttribute) as String? ?? "") { return }
        let role: String = AX.value(focused, kAXRoleAttribute) ?? ""
        guard ComposerPolicy.isComposer(role: role, label: AX.label(focused), enabled: AX.value(focused, kAXEnabledAttribute) ?? true,
                                       editable: AX.editable(focused), secure: (AX.value(focused, kAXSubroleAttribute) as String?) == "AXSecureTextField",
                                       excludedAncestor: excludedParents(focused, window: current),
                                       structuralMatch: role == "AXTextArea" && rect.width >= 180 && rect.midY > outer.minY + outer.height * 0.65) else { return }
        rememberedFocus = Target(app: app, element: focused, window: current, context: context(current, nodes: AX.nodes(current)), windowFrame: outer)
    }
    private func excludedParents(_ element: AXUIElement, window: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<24 {
            guard let item = current else { return true }
            if CFEqual(item, window) { return false }
            let role: String = AX.value(item, kAXRoleAttribute) ?? ""
            let label = AX.label(item).lowercased()
            if role == "AXDialog" || ["terminal", "终端", "side-chat", "side chat", "sidechat", "侧聊", "password", "密码", "code editor", "in-app-browser", "browser-pane", "browser-content", "浏览器内容"].contains(where: label.contains) { return true }
            current = AX.value(item, kAXParentAttribute)
        }
        return true
    }
    private func register(_ candidate: Target) -> PasteTarget? {
        guard let sessionWindow, CFEqual(candidate.window, sessionWindow), candidate.context == sessionContext else { return nil }
        let token = PasteTarget(id: UUID().uuidString)
        tokens[token.id] = candidate
        return token
    }
    func scopeMatches() -> Bool {
        guard let app = sourceApp, let sessionWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let current = window(for: app), CFEqual(current, sessionWindow) else { return false }
        return context(current, nodes: sessionProbes) == sessionContext
    }
    func snapshot() -> PasteTarget? { rememberedFocus.flatMap(register) }
    func locateAX() -> PasteLookup {
        guard let candidate = prepare(), let token = register(candidate) else {
            return preparationIssue.contains("多个") ? .ambiguous : .absent
        }
        return .target(token)
    }
    func locateOCR() async -> PasteLookup {
        guard CGPreflightScreenCaptureAccess() else {
            preparationIssue = "焦点快照与 AX 都无法定位；本地视觉兜底尚未获得屏幕录制权限"
            return .absent
        }
        guard let app = sourceApp, let sessionWindow, let rect = AX.frame(sessionWindow), scopeMatches() else { return .absent }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let title: String = AX.value(sessionWindow, kAXTitleAttribute) ?? ""
            let windows = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.title == title && abs($0.frame.minX - rect.minX) < 3 && abs($0.frame.minY - rect.minY) < 3 && abs($0.frame.width-rect.width) < 3 && abs($0.frame.height-rect.height) < 3 }
            guard windows.count == 1, let screenWindow = windows.first else { return windows.count > 1 ? .ambiguous : .absent }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(rect.width * 2); configuration.height = Int(rect.height * 2)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: screenWindow), configuration: configuration)
            guard scopeMatches() else { return .absent }
            let lines = try LocalOCR.recognize(image)
            let report = await Task.detached { IconLocator.analyze(image) }.value
            visualDiagnostics = report.summary
            visualCandidate = VisualComposer.locate(image:image,lines:lines,window:rect,report:report)
            if let visualCandidate { cachePosition(visualCandidate,image:image) }
            guard scopeMatches() else { visualCandidate = nil; return .absent }
            preparationIssue = visualDiagnostics + (visualCandidate == nil ? "；未能确认唯一输入区域" : "")
            switch LocalOCR.select(lines, axWindow: rect) {
            case .absent: return .absent
            case .ambiguous: return .ambiguous
            case .target(let hint):
                // A visual hint alone is insufficient: require a real editable AX hit target.
                let root = AXUIElementCreateApplication(app.processIdentifier)
                var found: AXUIElement?
                guard AXUIElementCopyElementAtPosition(root, Float(hint.midX), Float(hint.midY), &found) == .success, let found,
                      AX.editable(found), !excludedParents(found, window: sessionWindow),
                      ["AXTextArea", "AXTextField"].contains(AX.value(found, kAXRoleAttribute) as String? ?? "") else { return .absent }
                let candidate = Target(app: app, element: found, window: sessionWindow, context: sessionContext, windowFrame: rect)
                return register(candidate).map(PasteLookup.target) ?? .absent
            }
        } catch { preparationIssue = "本地视觉定位失败：\(error.localizedDescription)"; return .absent }
    }
    func isValid(_ token: PasteTarget) -> Bool {
        guard let candidate = tokens[token.id], matches(candidate), AX.frame(candidate.element) != nil,
              AX.editable(candidate.element), (AX.value(candidate.element, kAXEnabledAttribute) as Bool?) != false else { return false }
        return !excludedParents(candidate.element, window: candidate.window)
    }
    func focus(_ token: PasteTarget) -> Bool {
        guard let candidate = tokens[token.id], isValid(token) else { return false }
        let root = AXUIElementCreateApplication(candidate.app.processIdentifier)
        AXUIElementSetAttributeValue(candidate.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let focused: AXUIElement = AX.value(root, kAXFocusedUIElementAttribute), CFEqual(focused, candidate.element) { target = candidate; return true }
        // Only click the identified input, never a remembered absolute screen coordinate.
        guard let rect = AX.frame(candidate.element), scopeMatches(),
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: rect.midX, y: rect.midY), mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: rect.midX, y: rect.midY), mouseButton: .left) else { return false }
        down.postToPid(candidate.app.processIdentifier); up.postToPid(candidate.app.processIdentifier)
        guard let focused: AXUIElement = AX.value(root, kAXFocusedUIElementAttribute) else { return false }
        guard CFEqual(focused, candidate.element) else { return false }
        target = candidate
        return true
    }
    func draft(_ token: PasteTarget) -> String? { tokens[token.id].flatMap { AX.text($0.element) } }
    func paste(_ text: String, into token: PasteTarget) -> PasteDispatch {
        guard let candidate = tokens[token.id], isValid(token), draft(token) == "",
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return .notDispatched }
        let transaction = ClipboardTransaction(board: pasteboard)
        guard transaction.begin(text: text), transaction.unchanged, isValid(token) else { _ = transaction.restore(); return .notDispatched }
        clipboardTransaction = transaction
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(candidate.app.processIdentifier); up.postToPid(candidate.app.processIdentifier)
        target = candidate
        return .dispatched
    }
    func readBack(_ token: PasteTarget) -> String? { draft(token) }
    private func messageMatches(_ window: AXUIElement, text: String) -> Int {
        AX.nodes(window).filter { node in
            let role = node.role
            guard !node.excluded, role == "AXStaticText" else { return false }
            let value = AX.text(node.element) ?? AX.label(node.element)
            return value.trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.count
    }
    private func sendButton(_ target: Target) -> (AXUIElement, String)? {
        guard let input = AX.frame(target.element) else { return nil }
        return sendButton(window: target.window, input: input)
    }
    private func sendButton(window: AXUIElement, input: CGRect) -> (AXUIElement, String)? {
        let candidates = AX.nodes(window).compactMap { node -> (AXUIElement, String)? in
            guard !node.excluded, node.role == "AXButton",
                  (AX.value(node.element, kAXEnabledAttribute) as Bool?) == true,
                  let kind = ComposerPolicy.sendKind(AX.label(node.element)), let rect = AX.frame(node.element),
                  rect.width > 4, rect.height > 4,
                  rect.midX >= input.midX - 20, rect.midX <= input.maxX + 120,
                  rect.midY >= input.minY - 30, rect.midY <= input.maxY + 120 else { return nil }
            return (node.element, kind)
        }
        guard candidates.count == 1 else { return nil }
        return candidates.first
    }

    private func visualScreenshot(_ candidate: VisualComposer) async throws -> CGImage? {
        guard CGPreflightScreenCaptureAccess(), scopeMatches(), let app = sourceApp,
              let sessionWindow, AX.frame(sessionWindow) == candidate.window else { return nil }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let title: String = AX.value(sessionWindow, kAXTitleAttribute) ?? ""
        let windows = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.title == title && abs($0.frame.minX-candidate.window.minX) < 3 && abs($0.frame.minY-candidate.window.minY) < 3 && abs($0.frame.width-candidate.window.width) < 3 && abs($0.frame.height-candidate.window.height) < 3 }
        guard windows.count == 1, let window = windows.first else { return nil }
        let config = SCStreamConfiguration()
        config.width = Int(candidate.window.width*2); config.height = Int(candidate.window.height*2); config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        return scopeMatches() && AX.frame(sessionWindow) == candidate.window ? image : nil
    }
    private func visualText(_ image: CGImage, candidate: VisualComposer) throws -> [OCRLine] {
        candidate.inputLines(try LocalOCR.recognize(image))
    }
    private func verifyByCopy(_ expected: String, app: NSRunningApplication) async -> Bool {
        guard scopeMatches(), !Task.isCancelled else { return false }
        let transaction: ClipboardTransaction
        if let current = clipboardTransaction { transaction = current }
        else {
            transaction = ClipboardTransaction(board:pasteboard)
            guard transaction.begin(text:UUID().uuidString) else { return false }
            clipboardTransaction = transaction
        }
        guard transaction.replaceOwnedText("JustClick-readback-" + UUID().uuidString),
              KeyboardTransport.key(0,flags:.maskCommand,to:app.processIdentifier) else { return false }
        try? await Task.sleep(for:.milliseconds(80))
        guard scopeMatches(), !Task.isCancelled,
              KeyboardTransport.key(8,flags:.maskCommand,to:app.processIdentifier) else { return false }
        for _ in 0..<12 {
            try? await Task.sleep(for:.milliseconds(60))
            guard scopeMatches(), !Task.isCancelled else { return false }
            if !transaction.unchanged {
                let matches = transaction.adoptVerifiedCopy(expected)
                // Collapse the selection without replacing or retyping any text.
                if matches { _ = KeyboardTransport.key(124,to:app.processIdentifier) }
                return matches
            }
        }
        return false
    }

    /// Real pixel-based fallback: no AX editable element is required. Verify blank state
    /// before dispatch and visible text after dispatch. Unknown results are never retried.
    private func fillVisually(_ text: String, send: Bool, candidate: VisualComposer, initialImage: CGImage? = nil) async -> Result {
        var dispatched = false
        do {
            let captured: CGImage?
            if let initialImage { captured = initialImage } else { captured = try await visualScreenshot(candidate) }
            guard let image = captured else { return Result(message:"无法确认原窗口，未输入。") }
            let located: VisualComposer?
            if let cache = positionCache, cache.matches(image,window:candidate.window) { located = cache.composer }
            else { located = VisualComposer.locate(image:image,lines:try LocalOCR.recognize(image),window:candidate.window) }
            guard let app = sourceApp, let sessionWindow, let fresh = located,
                  abs(fresh.click.x-candidate.click.x) < 8, abs(fresh.click.y-candidate.click.y) < 8 else {
                return Result(message:"图标定位后输入框或窗口已变化，未输入。")
            }
            cachePosition(fresh,image:image)
            let point = fresh.click
            guard scopeMatches(),
                  let down = CGEvent(mouseEventSource:nil, mouseType:.leftMouseDown, mouseCursorPosition:point, mouseButton:.left),
                  let up = CGEvent(mouseEventSource:nil, mouseType:.leftMouseUp, mouseCursorPosition:point, mouseButton:.left) else { return Result(message:"无法聚焦视觉输入区域，未输入。") }
            down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
            try await Task.sleep(for:.milliseconds(150))
            // Recheck the empty composer after focus; preserve any existing draft.
            guard !Task.isCancelled, scopeMatches() else { return Result(message:"点击后窗口或聊天已变化，未粘贴。") }
            guard let before = try await visualScreenshot(fresh) else { return Result(message:"点击后无法重新截取同一窗口，未粘贴。") }
            let beforeLines = try LocalOCR.recognize(before)
            if positionCache?.matches(before,window:fresh.window) != true {
                let beforeReport = IconLocator.analyze(before)
                guard let current = VisualComposer.locate(image:before,lines:beforeLines,window:fresh.window,report:beforeReport),
                      abs(current.click.x-fresh.click.x) < 8, abs(current.click.y-fresh.click.y) < 8 else {
                    invalidatePositionCache()
                    return Result(message:"点击后重新检查：\(beforeReport.summary)，输入位置变化，未粘贴。")
                }
            }
            let inputLines = fresh.inputLines(beforeLines)
            var alreadyFilled = VisualComposer.agrees(inputLines,with:text)
            if send && !alreadyFilled && VisualComposer.hasVisibleDraftEvidence(inputLines,expected:text) { alreadyFilled = await verifyByCopy(text,app:app) }
            guard alreadyFilled || VisualComposer.permitsEmptyInput(inputLines) else {
                return Result(message:"输入区域检测到 \(inputLines.count) 段文字、\(inputLines.map(\.text).joined().count) 个字符，未认定为空输入框，未粘贴。")
            }
            if !alreadyFilled {
                let transaction = ClipboardTransaction(board:pasteboard)
                guard transaction.begin(text:text), transaction.unchanged,
                      let keyDown = CGEvent(keyboardEventSource:nil,virtualKey:9,keyDown:true),
                      let keyUp = CGEvent(keyboardEventSource:nil,virtualKey:9,keyDown:false) else { _ = transaction.restore(); return Result(message:"剪贴板准备失败，未输入。") }
                clipboardTransaction = transaction
                guard scopeMatches(), !Task.isCancelled else { return Result(message:"窗口已变化，未粘贴。") }
                keyDown.flags = .maskCommand; keyUp.flags = .maskCommand
                keyDown.postToPid(app.processIdentifier); keyUp.postToPid(app.processIdentifier); dispatched = true
            }
            var verified = false
            for _ in 0..<4 {
                try await Task.sleep(for:.milliseconds(250))
                guard let after = try await visualScreenshot(fresh) else { break }
                if VisualComposer.agrees(try visualText(after,candidate:fresh),with:text) { verified = true; break }
            }
            if !verified, let after = try await visualScreenshot(fresh),
               VisualComposer.hasVisibleDraftEvidence(try visualText(after,candidate:fresh),expected:text) {
                verified = await verifyByCopy(text,app:app)
            }
            guard verified else { return Result(message:"已尝试粘贴，但视觉及复制回读均未确认完整内容；请检查输入框，不会重复粘贴或发送。", uncertain:true) }
            guard send else { return Result(message:"已通过＋和麦克风定位并填入，内容核对通过，尚未发送。", succeeded: true) }
            guard let beforeSend = try await visualScreenshot(fresh), scopeMatches(), !Task.isCancelled else { return Result(message:"发送前窗口已变化，未发送。",uncertain:true) }
            let visuallyConfirmed = VisualComposer.agrees(try visualText(beforeSend,candidate:fresh),with:text)
            var confirmedBeforeSend = visuallyConfirmed
            if !confirmedBeforeSend, VisualComposer.hasVisibleDraftEvidence(try visualText(beforeSend,candidate:fresh),expected:text) {
                confirmedBeforeSend = await verifyByCopy(text,app:app)
            }
            guard confirmedBeforeSend else { return Result(message:"发送前未能核对完整文字，未发送。",uncertain:true) }
            let beforeCount = messageMatches(sessionWindow,text:text)
            let visualBefore = fresh.messageOccurrences(try LocalOCR.recognize(beforeSend),expected:text)
            guard scopeMatches(), !Task.isCancelled else { return Result(message:"发送前窗口已变化，未发送。",uncertain:true) }
            if let (button, _) = sendButton(window:sessionWindow,input:fresh.input), AX.actions(button).contains(kAXPressAction) {
                guard AXUIElementPerformAction(button,kAXPressAction as CFString) == .success else {
                    return Result(message:"文字已填入，但发送操作结果不确定，请检查聊天。",uncertain:true)
                }
            } else {
                guard KeyboardTransport.pressReturn(to:app.processIdentifier) else {
                    return Result(message:"文字已填入，但 Return 未能执行，请手动发送。")
                }
            }
            for _ in 0..<6 {
                try await Task.sleep(for:.milliseconds(200))
                guard let after = try await visualScreenshot(fresh) else { break }
                let lines = try LocalOCR.recognize(after)
                if VisualComposer.permitsEmptyInput(try visualText(after,candidate:fresh)),
                   (messageMatches(sessionWindow,text:text) > beforeCount || fresh.messageOccurrences(lines,expected:text) > visualBefore) {
                    return Result(message:"已通过图标定位、填入并发送，聊天回执核对通过。", succeeded: true)
                }
            }
            return Result(message:"已操作发送，但未确认聊天回执；请检查，不会重复发送。",uncertain:true)
        } catch {
            return Result(message:dispatched ? "粘贴后视觉核对中断，请检查输入框；不会重复输入。" : "本地图标定位未完成：\(error.localizedDescription)", uncertain:dispatched)
        }
    }

    func deliver(_ text: String, send: Bool) async -> Result {
        guard trusted else { return Result(message: "自动填入与发送需要辅助功能权限。请在设置中授权 JustClick；复制按钮仍可用。") }
        guard let app = sourceApp, !app.isTerminated else { return Result(message: "没有绑定 Codex 窗口。请切回当前聊天。") }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard foreground == app.processIdentifier || foreground == ProcessInfo.processInfo.processIdentifier else {
            return Result(message: "已切换到其他 App，未发送。请切回 Codex 后再试。")
        }
        guard let lockedWindow = window(for: app) else { return Result(message: "无法取得当前 Codex 窗口，未输入。") }
        sessionWindow = lockedWindow
        let reuseContext = cachedPID == app.processIdentifier && cachedWindow.map { CFEqual($0,lockedWindow) } == true
            && positionCache?.composer.window == AX.frame(lockedWindow)
            && context(lockedWindow,nodes:cachedProbes) == cachedContext
        let lockedNodes = reuseContext ? cachedProbes : AX.nodes(lockedWindow)
        sessionContext = context(lockedWindow, nodes: lockedNodes)
        sessionProbes = lockedNodes.filter { node in
            node.role == "AXHeading" || (!node.excluded && ["AXRow", "AXButton", "AXRadioButton"].contains(node.role) && (AX.value(node.element, kAXSelectedAttribute) as Bool?) == true)
        }
        tokens = [:]; target = nil; visualCandidate = nil; visualDiagnostics = ""
        guard app.activate(options: []) else { return Result(message: "无法激活 Codex，未发送。") }
        try? await Task.sleep(for: .milliseconds(150))
        defer { _ = clipboardTransaction?.restore(); clipboardTransaction = nil; tokens = [:] }
        if reuseContext, let cache = positionCache {
            do {
                if let image = try await visualScreenshot(cache.composer), cache.matches(image,window:cache.composer.window) {
                    let result = await fillVisually(text,send:send,candidate:cache.composer,initialImage:image)
                    if result.uncertain { invalidatePositionCache() }
                    return Result(message:"位置缓存命中：跳过完整定位。\n" + result.message,uncertain:result.uncertain, succeeded:result.succeeded)
                }
            } catch { /* A failed fast path falls back to normal discovery. */ }
            invalidatePositionCache()
        }
        let filled = await PastePipeline.fill(text, backend: self, checks: 20, acceptMatchingDraft: send)
        if filled.status == .noTarget, let visualCandidate {
            let result = await fillVisually(text, send: send, candidate: visualCandidate)
            return Result(message: visualDiagnostics + "。\n" + result.message, uncertain: result.uncertain, succeeded: result.succeeded)
        }
        guard filled.status == .filled, let target = self.target else {
            let messages: [PasteStatus: String] = [
                .draftPresent: "输入框已有草稿，已保留，未发送。",
                .unreadableDraft: "无法核对输入框内容，未输入。",
                .contextChanged: "窗口或聊天已变化，已停止；请检查草稿。",
                .ambiguous: "发现多个可能的输入框，未猜测或发送。",
                .noTarget: preparationIssue + "，未输入。",
                .dispatchFailed: "粘贴未能执行，未发送。",
                .verificationFailed: "已尝试正常粘贴，但内容核对失败；不会重复粘贴。",
                .cancelled: "输入操作已取消。",
                .emptyText: "提示词内容为空。"
            ]
            return Result(message: messages[filled.status] ?? "填入失败，未发送。", uncertain: filled.uncertain)
        }
        let visibleBefore = send ? messageMatches(target.window, text: text) : 0
        guard send else { return Result(message: "已核对并填入，尚未发送。", succeeded: true) }
        guard matches(target), AX.text(target.element) == text else {
            return Result(message: "已填入，但发送前窗口或内容发生变化，未发送。")
        }
        let control = sendButton(target)
        let kind = control?.1 ?? "send"
        let press: AXError
        if let (button, _) = control {
            if AX.actions(button).contains(kAXPressAction) {
                press = AXUIElementPerformAction(button, kAXPressAction as CFString)
            } else if let rect = AX.frame(button), matches(target),
                      let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: rect.midX, y: rect.midY), mouseButton: .left),
                      let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: rect.midX, y: rect.midY), mouseButton: .left) {
                down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier); press = .success
            } else { press = .cannotComplete }
        } else {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            let focused: AXUIElement? = AX.value(root,kAXFocusedUIElementAttribute)
            guard let focused, CFEqual(focused,target.element), matches(target), !Task.isCancelled else { return Result(message:"输入框焦点已变化，未按 Enter。") }
            press = KeyboardTransport.pressReturn(to:app.processIdentifier) ? .success : .cannotComplete
        }
        guard press == .success else { return Result(message: "发送控件操作失败，草稿已保留。请核对后手动发送。", uncertain: true) }
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(150))
            guard matches(target) else { return Result(message: "发送后聊天上下文变化，结果无法确认；请检查原聊天，勿直接重试。", uncertain: true) }
            let receipt = DeliveryReceipt.evaluate(contextMatches: true, draft: AX.text(target.element), inserted: text,
                                                   visibleMatchesBefore: visibleBefore, visibleMatchesAfter: messageMatches(target.window, text: text))
            if receipt == .confirmed { return Result(message: kind == "queue" ? "已核对当前界面的新增内容，排队请求已受理。" : "已核对当前界面的新增消息，发送已确认。", succeeded: true) }
        }
        return Result(message: "已请求\(kind == "queue" ? "排队" : "发送")，但无法确认回执。请先检查 Codex，再解除重试锁定。", uncertain: true)
    }
    func requestAccess() {
        PermissionGuide.show()
    }
}
