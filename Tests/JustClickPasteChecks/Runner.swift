import AppKit
import ApplicationServices
import JustClickPasteKit
import Darwin

@MainActor
final class ChatFixtureEditor: NSTextView {
    var submitted = ""
    override func insertNewline(_ sender: Any?) { submitted = string; string = "" }
}

@MainActor
final class Fixture: NSObject, PasteBackend {
    enum Mode { case snapshot, ax, ocr }
    let window: NSWindow
    let editor: ChatFixtureEditor
    let search: NSTextField
    let hint: NSTextField
    let intendedTitle = "JustClick isolated paste fixture"
    var mode: Mode = .snapshot
    var tokenValid = true
    var pasteCount = 0
    var axFocusPerformed = false
    var axElement: AXUIElement?
    var occlusion = false
    var lastImage: CGImage?
    let target = PasteTarget(id: "fixture-primary-composer")
    var capturedSnapshot: PasteTarget?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 640, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = intendedTitle; window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let scroll = NSScrollView(frame: NSRect(x: 40, y: 25, width: 540, height: 100))
        scroll.borderType = .bezelBorder
        editor = ChatFixtureEditor(frame: scroll.bounds)
        editor.isRichText = false; editor.font = .systemFont(ofSize: 16)
        editor.setAccessibilityLabel("Message test chat")
        editor.setAccessibilityIdentifier("fixture-composer")
        scroll.documentView = editor
        content.addSubview(scroll)
        search = NSTextField(frame: NSRect(x: 40, y: 265, width: 540, height: 30))
        search.placeholderString = "Search test library"; search.setAccessibilityIdentifier("fixture-search")
        content.addSubview(search)
        hint = NSTextField(labelWithString: "Do anything")
        hint.font = .systemFont(ofSize: 20); hint.textColor = .gray
        hint.frame = NSRect(x: 56, y: 66, width: 350, height: 28)
        content.addSubview(hint)
        window.contentView = content
        super.init()
        window.orderFront(nil)
        window.makeFirstResponder(editor)
    }
    func reset(_ mode: Mode) {
        self.mode = mode; editor.string = ""; window.title = intendedTitle
        tokenValid = true; pasteCount = 0; axFocusPerformed = false; axElement = nil; occlusion = false
        hint.isHidden = false
        window.makeFirstResponder(editor)
        capturedSnapshot = window.firstResponder === editor ? target : nil
        // Simulate the sidebar's search taking focus after the real editor was captured.
        window.makeFirstResponder(search)
    }
    func scopeMatches() -> Bool { window.title == intendedTitle && !occlusion }
    func snapshot() -> PasteTarget? { mode == .snapshot ? capturedSnapshot : nil }
    func isValid(_ target: PasteTarget) -> Bool { target == self.target && tokenValid }
    func focus(_ target: PasteTarget) -> Bool {
        guard isValid(target) else { return false }
        if mode == .ax, let axElement {
            guard AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { return false }
            axFocusPerformed = true
        } else { guard window.makeFirstResponder(editor) else { return false } }
        return window.firstResponder === editor
    }
    func draft(_ target: PasteTarget) -> String? { isValid(target) ? editor.string : nil }
    func paste(_ text: String, into target: PasteTarget) -> PasteDispatch {
        guard scopeMatches(), isValid(target), window.firstResponder === editor, editor.string.isEmpty else { return .notDispatched }
        let transaction = ClipboardTransaction()
        guard transaction.begin(text: text) else { return .notDispatched }
        hint.isHidden = true
        editor.paste(nil) // The real AppKit paste path, not a direct assignment to string.
        pasteCount += 1
        _ = transaction.restore() // Native paste is synchronous in this fixture.
        return .dispatched
    }
    func readBack(_ target: PasteTarget) -> String? { isValid(target) ? editor.string : nil }
    func locateAX() -> PasteLookup {
        guard mode == .ax else { return .absent }
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var pending = [app]; var matches: [AXUIElement] = []
        for _ in 0..<150 {
            guard let element = pending.popLast() else { break }
            if let id: String = attribute(element, kAXIdentifierAttribute), id == "fixture-composer" { matches.append(element) }
            let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
            pending.append(contentsOf: children)
        }
        guard matches.count <= 1 else { return .ambiguous }
        guard let element = matches.first else { return .absent }
        axElement = element
        return .target(target)
    }
    func locateOCR() async -> PasteLookup {
        guard mode == .ocr, let content = window.contentView,
              let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return .absent }
        content.cacheDisplay(in: content.bounds, to: representation)
        guard let image = representation.cgImage else { return .absent }
        lastImage = image
        do {
            let lines = try LocalOCR.recognize(image)
            // The image covers this fixture's content plane, not the external desktop.
            let plane = CGRect(x: 0, y: 0, width: 640, height: 360)
            switch LocalOCR.select(lines, axWindow: plane) {
            case .absent: return .absent
            case .ambiguous: return .ambiguous
            case .target(let rect):
                let appKitPoint = NSPoint(x: rect.midX, y: 360 - rect.midY)
                guard NSRect(x: 40, y: 25, width: 540, height: 100).contains(appKitPoint) else { return .absent }
                return .target(target)
            }
        } catch { return .absent }
    }
    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

@MainActor
final class ControlledBackend: PasteBackend {
    var scope = true
    var saved: PasteTarget? = PasteTarget(id: "snapshot")
    var ax: PasteLookup = .target(PasteTarget(id: "ax"))
    var ocr: PasteLookup = .target(PasteTarget(id: "ocr"))
    var invalidIDs: Set<String> = []
    var failedFocusIDs: Set<String> = []
    var value: String? = ""
    var accepted = true
    var corrupt = false
    var switchAfterPaste = false
    var switchDuringOCR = false
    var pasteCount = 0
    func scopeMatches() -> Bool { scope }
    func snapshot() -> PasteTarget? { saved }
    func locateAX() -> PasteLookup { ax }
    func locateOCR() async -> PasteLookup { if switchDuringOCR { scope = false }; return ocr }
    func isValid(_ target: PasteTarget) -> Bool { !invalidIDs.contains(target.id) }
    func focus(_ target: PasteTarget) -> Bool { !failedFocusIDs.contains(target.id) }
    func draft(_ target: PasteTarget) -> String? { value }
    func paste(_ text: String, into target: PasteTarget) -> PasteDispatch {
        guard accepted else { return .notDispatched }
        pasteCount += 1; value = corrupt ? "partial" : text
        if switchAfterPaste { scope = false }
        return .dispatched
    }
    func readBack(_ target: PasteTarget) -> String? { value }
}

@MainActor
final class Checks: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run(); NSApp.terminate(nil) }
            catch { FileHandle.standardError.write(Data("FAIL \(error)\n".utf8)); Foundation.exit(1) }
        }
    }
    struct Failure: Error { let message: String }
    func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure(message: message) } }
    func run() async throws {
        let fixture = Fixture(); defer { fixture.window.close() }
        var passed = 0; var skipped = 0
        let text = "JustClick fixture paste\n中文、多行与 emoji ✨\n$HOME stays literal"
        fixture.reset(.snapshot)
        try require(fixture.window.firstResponder !== fixture.editor && fixture.capturedSnapshot != nil, "original focus captured before sidebar focus")
        var outcome = await PastePipeline.fill(text, backend: fixture)
        try require(outcome.status == .filled && outcome.route == .snapshot && fixture.editor.string == text && fixture.pasteCount == 1, "real snapshot/native paste")
        passed += 1; print("PASS native fixture: snapshot restores focus and pastes Unicode/multiline")
        fixture.reset(.ax)
        try? await Task.sleep(for: .milliseconds(100))
        if AXIsProcessTrusted(), case .target = fixture.locateAX() {
            outcome = await PastePipeline.fill(text, backend: fixture)
            try require(outcome.status == .filled && outcome.route == .accessibility && fixture.axFocusPerformed, "real AX restoration")
            passed += 1; print("PASS native fixture: actual AX lookup/focus + native paste")
        } else { skipped += 1; print("SKIP actual AX lookup: runner not trusted or own fixture not exposed; mock AX checks are separate") }
        fixture.reset(.ocr)
        outcome = await PastePipeline.fill(text, backend: fixture)
        try require(outcome.status == .filled && outcome.route == .ocr && fixture.editor.string == text, "Vision OCR/native paste")
        passed += 1; print("PASS native fixture: real local Vision OCR + coordinate validation + native paste")
        fixture.reset(.snapshot); fixture.editor.string = "existing draft"
        outcome = await PastePipeline.fill(text, backend: fixture)
        try require(outcome.status == .draftPresent && fixture.editor.string == "existing draft" && fixture.pasteCount == 0, "draft preservation")
        passed += 1; print("PASS native fixture: existing draft preserved")

        // Exercise exactly the event transport used by the installed adapter, on this test app only.
        fixture.reset(.snapshot)
        let menu = NSMenu(); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a"))
        editMenu.addItem(NSMenuItem(title:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c"))
        editItem.submenu = editMenu; menu.addItem(editItem); NSApp.mainMenu = menu
        fixture.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        fixture.window.makeFirstResponder(fixture.editor)
        try? await Task.sleep(for: .milliseconds(250))
        print("CHECK fixture active=\(NSApp.isActive) key=\(fixture.window.isKeyWindow)")
        let keyboardClipboard = ClipboardTransaction()
        try require(keyboardClipboard.begin(text: text), "keyboard paste clipboard")
        let sender = Process()
        sender.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        sender.arguments = ["--send-keys-to-own-fixture"]
        try sender.run()
        for _ in 0..<30 {
            if fixture.editor.string == text { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let keyboardMatches = fixture.editor.string == text
        for _ in 0..<20 {
            if !sender.isRunning { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if sender.isRunning { sender.terminate() }
        sender.waitUntilExit()
        try require(sender.terminationStatus == 0, "fixture-only keyboard sender")
        _ = keyboardClipboard.restore()
        try require(keyboardMatches, "actual process-scoped Command+V")
        passed += 1; print("PASS native fixture: cross-process CGEvent postToPid Command+V transport")

        let copyTransaction = ClipboardTransaction()
        try require(copyTransaction.begin(text:"copy-sentinel"),"prepare copy verification")
        let copier = Process()
        copier.executableURL = URL(fileURLWithPath:CommandLine.arguments[0]).resolvingSymlinksInPath()
        copier.arguments = ["--copy-from-own-fixture"]
        try copier.run()
        for _ in 0..<30 {
            if !copyTransaction.unchanged { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        let exactCopy = copyTransaction.adoptVerifiedCopy(text)
        for _ in 0..<20 { if !copier.isRunning { break }; try await Task.sleep(for:.milliseconds(50)) }
        if copier.isRunning { copier.terminate() }; copier.waitUntilExit()
        _ = copyTransaction.restore()
        try require(exactCopy && copier.terminationStatus == 0 && fixture.editor.string == text,"exact copy readback preserves draft")
        passed += 1; print("PASS native fixture: Cmd+A/C returns exact Unicode draft without changing it")
        let submitter = Process()
        submitter.executableURL = URL(fileURLWithPath:CommandLine.arguments[0]).resolvingSymlinksInPath()
        submitter.arguments = ["--send-return-to-own-fixture"]
        try submitter.run()
        for _ in 0..<30 {
            if fixture.editor.submitted == text { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        for _ in 0..<20 {
            if !submitter.isRunning { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        if submitter.isRunning { submitter.terminate() }
        submitter.waitUntilExit()
        try require(submitter.terminationStatus == 0 && fixture.editor.submitted == text && fixture.editor.string.isEmpty, "actual paste then Return submission to own fixture")
        passed += 1; print("PASS native fixture: pasted Unicode/multiline text submitted once via cross-process Return")

        func controlled(_ name: String, configure: (ControlledBackend) -> Void, status: PasteStatus, route: PasteRoute? = nil, count: Int, uncertain: Bool = false) async throws {
            let backend = ControlledBackend(); configure(backend)
            let result = await PastePipeline.fill(text, backend: backend, checks: 2, delay: .milliseconds(1))
            try require(result.status == status && backend.pasteCount == count, name)
            try require(result.uncertain == uncertain, name + " uncertainty")
            if let route { try require(result.route == route, name + " route") }
            passed += 1; print("PASS controlled backend: \(name)")
        }
        try await controlled("expired snapshot falls back to AX", configure: { $0.invalidIDs = ["snapshot"] }, status: .filled, route: .accessibility, count: 1)
        try await controlled("lost focus falls back to AX", configure: { $0.failedFocusIDs = ["snapshot"] }, status: .filled, route: .accessibility, count: 1)
        try await controlled("AX absent falls back to OCR", configure: { $0.saved = nil; $0.ax = .absent }, status: .filled, route: .ocr, count: 1)
        try await controlled("ambiguous AX stops before OCR", configure: { $0.saved = nil; $0.ax = .ambiguous }, status: .ambiguous, count: 0)
        try await controlled("context changes during OCR", configure: { $0.saved = nil; $0.ax = .absent; $0.switchDuringOCR = true }, status: .contextChanged, count: 0)
        try await controlled("partial paste never retries", configure: { $0.corrupt = true }, status: .verificationFailed, count: 1, uncertain: true)
        try await controlled("switch after dispatch is uncertain", configure: { $0.switchAfterPaste = true }, status: .contextChanged, count: 1, uncertain: true)
        try await controlled("unreadable draft stops", configure: { $0.value = nil }, status: .unreadableDraft, count: 0)
        try await controlled("dispatch failure never retries", configure: { $0.accepted = false }, status: .dispatchFailed, count: 0)
        let matching = ControlledBackend(); matching.value = text
        let reuse = await PastePipeline.fill(text,backend:matching,acceptMatchingDraft:true)
        try require(reuse.status == .filled && matching.pasteCount == 0, "send existing matching draft without duplicate paste")
        matching.value = "unrelated draft"
        let preserve = await PastePipeline.fill(text,backend:matching,acceptMatchingDraft:true)
        try require(preserve.status == .draftPresent && matching.pasteCount == 0, "send mode preserves unrelated draft")
        passed += 1; print("PASS fill-then-send reuses exact draft, preserves unrelated draft")
        let emptyBackend = ControlledBackend()
        let emptyResult = await PastePipeline.fill("", backend: emptyBackend)
        try require(emptyResult.status == .emptyText && emptyBackend.pasteCount == 0, "empty request")
        passed += 1; print("PASS controlled backend: empty text rejected")
        let cancelledBackend = ControlledBackend()
        let cancelledTask = Task { @MainActor in await PastePipeline.fill(text, backend: cancelledBackend) }
        cancelledTask.cancel()
        let cancelledResult = await cancelledTask.value
        try require(cancelledResult.status == .cancelled && cancelledBackend.pasteCount == 0 && !cancelledResult.uncertain, "cancel before paste")
        passed += 1; print("PASS controlled backend: cancellation before input")

        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("previous", forType: .string)
        let transaction = ClipboardTransaction(board: board)
        try require(transaction.begin(text: text), "clipboard begin")
        try require(board.string(forType: .string) == text && transaction.restore() && board.string(forType: .string) == "previous", "clipboard restore")
        passed += 1; print("PASS clipboard: previous contents restored")
        try require(transaction.begin(text: text), "clipboard second begin")
        board.clearContents(); board.setString("new user copy", forType: .string)
        try require(!transaction.restore() && board.string(forType: .string) == "new user copy", "clipboard race")
        passed += 1; print("PASS clipboard: newer user copy preserved")
        let verifiedBoard = NSPasteboard.withUniqueName(); defer { verifiedBoard.releaseGlobally() }
        verifiedBoard.setString("original clipboard",forType:.string)
        let verifiedTransaction = ClipboardTransaction(board:verifiedBoard)
        try require(verifiedTransaction.begin(text:text) && verifiedTransaction.replaceOwnedText("sentinel"),"prepare copy readback sentinel")
        verifiedBoard.clearContents(); verifiedBoard.setString(text,forType:.string)
        try require(verifiedTransaction.adoptVerifiedCopy(text) && verifiedTransaction.restore(),"adopt exact copied draft")
        try require(verifiedBoard.string(forType:.string) == "original clipboard","restore clipboard after exact readback")
        passed += 1; print("PASS copy readback ownership restores original clipboard")
        let duplicate = [OCRLine(text: "Message test chat", confidence: 1, bounds: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.1)), OCRLine(text: "Ask Codex", confidence: 1, bounds: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.1))]
        if case .ambiguous = LocalOCR.select(duplicate, axWindow: CGRect(x: 0, y: 0, width: 800, height: 600)) { passed += 1; print("PASS OCR selector: ambiguity rejected") }
        else { throw Failure(message: "OCR ambiguity") }
        print("RESULT passed=\(passed) skipped=\(skipped). Only the isolated fixture was tested; real Codex paste/send NOT verified.")
    }
}

@main
struct Runner {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--send-keys-to-own-fixture") || CommandLine.arguments.contains("--send-return-to-own-fixture") || CommandLine.arguments.contains("--copy-from-own-fixture") {
            // This helper can only target its own test-runner parent, never a user app.
            var path = [CChar](repeating: 0, count: 4096)
            let count = path.withUnsafeMutableBytes { proc_pidpath(getppid(), $0.baseAddress, UInt32($0.count)) }
            let own = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
            guard count > 0, URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path == own,
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { exit(1) }
            print("CHECK keyboard helper trusted=\(AXIsProcessTrusted())")
            if CommandLine.arguments.contains("--copy-from-own-fixture") {
                guard KeyboardTransport.key(0,flags:.maskCommand,to:getppid()) else { exit(1) }
                Thread.sleep(forTimeInterval:0.1)
                guard KeyboardTransport.key(8,flags:.maskCommand,to:getppid()) else { exit(1) }
            } else if CommandLine.arguments.contains("--send-return-to-own-fixture") {
                guard KeyboardTransport.pressReturn(to:getppid()) else { exit(1) }
            } else {
                down.flags = .maskCommand; up.flags = .maskCommand
                down.postToPid(getppid()); up.postToPid(getppid())
            }
            Thread.sleep(forTimeInterval: 0.3)
            return
        }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let delegate = Checks(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
