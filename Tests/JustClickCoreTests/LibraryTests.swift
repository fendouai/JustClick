import Foundation
import CoreGraphics
import JustClickCore

final class LibraryTests {
    var cleanups: [() -> Void] = []
    deinit { cleanups.forEach { $0() } }
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("justclick-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanups.append { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testUnicodeAndMultilineRoundTrip() throws {
        let file = LibraryFile(url: try directory().appendingPathComponent("nested/prompts.json"))
        let library = Library(prompts: [Prompt(title: "验证 ✨", body: "第一行\n第二行：`$HOME`\n\"保留原文\"", category: "开发")])
        try file.save(library)
        expectEqual(try file.load(), library)
    }
    func testSearchMatchesAllTermsAcrossFieldsAndKeepsPinnedOrder() {
        let first = Prompt(title: "Review", body: "Check code", category: "开发")
        let second = Prompt(title: "review status", body: "Check code", category: "开发", pinned: true)
        let third = Prompt(title: "其他", body: "Check logs", category: "运维", pinned: true)
        let library = Library(prompts: [first, second, third])
        expectEqual(library.filtered("REVIEW 开发").map(\.id), [second.id, first.id])
        expectEqual(library.filtered("", category: "运维").map(\.id), [third.id])
        expectTrue(library.filtered("missing").isEmpty)
    }
    func testInvalidSaveDoesNotOverwriteExistingLibrary() throws {
        let file = LibraryFile(url: try directory().appendingPathComponent("prompts.json"))
        let original = Library(); try file.save(original)
        expectThrows(try file.save(Library(prompts: [Prompt(title: "  ", body: "text")])))
        expectEqual(try file.load(), original)
    }
    func testCorruptImportPreservesOriginalAndDoesNotMakeBackup() throws {
        let dir = try directory(); let file = LibraryFile(url: dir.appendingPathComponent("prompts.json"))
        let original = Library(); try file.save(original)
        let source = dir.appendingPathComponent("invalid.json"); try Data("broken".utf8).write(to: source)
        expectThrows(try file.importFile(source))
        expectEqual(try file.load(), original)
        expectFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains("backup") })
    }
    func testValidImportBacksUpOriginal() throws {
        let dir = try directory(); let file = LibraryFile(url: dir.appendingPathComponent("prompts.json"))
        let original = Library(); try file.save(original)
        let source = dir.appendingPathComponent("incoming.json")
        let next = Library(prompts: [Prompt(title: "新", body: "内容")]); try LibraryFile(url: source).save(next)
        expectEqual(try file.importFile(source), next)
        expectEqual(try file.load(), next)
        let backup = try unwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("backup") })
        expectEqual(try LibraryFile(url: backup).load(), original)
    }
    func testDuplicateIDsAndUnknownVersionRejected() throws {
        let prompt = Prompt(title: "名称", body: "正文")
        expectThrows(try Library(prompts: [prompt, prompt]).validate())
        var library = Library(); library.version = 2
        expectThrows(try library.validate())
    }
    func testSizeLimitsAndEmptyLibrary() throws {
        expectNoThrow(try Library(prompts: []).validate())
        expectThrows(try Library(prompts: [Prompt(title: "名称", body: String(repeating: "中", count: 170_000))]).validate())
        let file = LibraryFile(url: try directory().appendingPathComponent("large.json"))
        try Data(repeating: 0x20, count: 10_000_001).write(to: file.url)
        expectThrows(try file.load())
    }
    func testDeliveryRejectsOtherAppsSecureFieldsAndNonEditableControls() {
        expectTrue(InputPolicy.allows(bundle: "com.openai.codex", role: "AXTextArea", editable: true, secure: false))
        expectTrue(InputPolicy.allows(bundle: "com.openai.chat", role: "AXTextField", editable: true, secure: false))
        expectFalse(InputPolicy.allows(bundle: "com.apple.Terminal", role: "AXTextArea", editable: true, secure: false))
        expectFalse(InputPolicy.allows(bundle: "com.openai.codex", role: "AXTextField", editable: true, secure: true))
        expectFalse(InputPolicy.allows(bundle: "com.openai.codex", role: "AXTextArea", editable: false, secure: false))
        expectFalse(InputPolicy.allows(bundle: "com.openai.codex", role: "AXButton", editable: true, secure: false))
    }
    func testComposerRecognitionRejectsSearchSideChatAndUnknownControls() {
        func allows(_ label: String, excluded: Bool = false) -> Bool {
            ComposerPolicy.isComposer(role: "AXTextArea", label: label, enabled: true, editable: true, secure: false, excludedAncestor: excluded)
        }
        expectTrue(allows("prompt-textarea Message Codex"))
        expectTrue(allows("发送给 Codex"))
        expectTrue(allows("Do anything"))
        expectFalse(allows("Search Do anything"))
        expectFalse(allows("Do anything", excluded: true))
        expectFalse(allows("Search messages"))
        expectFalse(allows("Side chat composer"))
        expectFalse(allows("Message Codex", excluded: true))
        expectFalse(allows("untitled text editor"))
        expectTrue(ComposerPolicy.isComposer(role: "AXTextArea", label: "", enabled: true, editable: true, secure: false, excludedAncestor: false, structuralMatch: true))
        expectFalse(ComposerPolicy.isComposer(role: "AXTextField", label: "", enabled: true, editable: true, secure: false, excludedAncestor: false, structuralMatch: true))
        expectFalse(ComposerPolicy.isComposer(role: "AXTextArea", label: "Search messages", enabled: true, editable: true, secure: false, excludedAncestor: false, structuralMatch: true))
        expectFalse(ComposerPolicy.isComposer(role: "AXTextArea", label: "", enabled: true, editable: true, secure: false, excludedAncestor: true, structuralMatch: true))
        expectFalse(ComposerPolicy.isComposer(role: "AXTextArea", label: "composer", enabled: false, editable: true, secure: false, excludedAncestor: false))
    }
    func testSendControlNeverMatchesStopOrCancel() {
        expectEqual(ComposerPolicy.sendKind("Send message"), "send")
        expectEqual(ComposerPolicy.sendKind("排队发送"), "queue")
        expectEqual(ComposerPolicy.sendKind("停止发送"), nil)
        expectEqual(ComposerPolicy.sendKind("Stop generating"), nil)
        expectEqual(ComposerPolicy.sendKind("Cancel submission"), nil)
        expectEqual(ComposerPolicy.sendKind("Start dictation"), nil)
        expectEqual(ComposerPolicy.sendKind("Retry"), nil)
    }
    func testReceiptRequiresNewVisibleMessageAndClearedDraft() {
        expectEqual(DeliveryReceipt.evaluate(contextMatches: true, draft: "", inserted: "prompt", visibleMatchesBefore: 2, visibleMatchesAfter: 3), .confirmed)
        expectEqual(DeliveryReceipt.evaluate(contextMatches: true, draft: "", inserted: "prompt", visibleMatchesBefore: 2, visibleMatchesAfter: 2), .unknown)
        expectEqual(DeliveryReceipt.evaluate(contextMatches: true, draft: nil, inserted: "prompt", visibleMatchesBefore: 2, visibleMatchesAfter: 3), .unknown)
        expectEqual(DeliveryReceipt.evaluate(contextMatches: true, draft: "prompt", inserted: "prompt", visibleMatchesBefore: 2, visibleMatchesAfter: 3), .draftOnly)
        expectEqual(DeliveryReceipt.evaluate(contextMatches: false, draft: "", inserted: "prompt", visibleMatchesBefore: 2, visibleMatchesAfter: 3), .contextChanged)
    }
    func testRepeatClicksAndUncertainDeliveryAreBlocked() {
        var gate = DeliveryGate(); let date = Date(timeIntervalSince1970: 100)
        expectTrue(gate.begin(now: date))
        expectFalse(gate.begin(now: date.addingTimeInterval(2)))
        gate.finish(uncertain: false)
        expectFalse(gate.begin(now: date.addingTimeInterval(0.5)))
        expectTrue(gate.begin(now: date.addingTimeInterval(2)))
        gate.finish(uncertain: true)
        expectFalse(gate.begin(now: date.addingTimeInterval(100)))
        expectTrue(gate.begin(now: date.addingTimeInterval(100), explicitRetry: true))
        expectFalse(gate.begin(now: date.addingTimeInterval(100.1), explicitRetry: true))
        gate.finish(uncertain: true)
        gate.acknowledge()
        expectTrue(gate.begin(now: date.addingTimeInterval(102)))
    }
    func testLanguageLibraryAndFrequentOrdering() throws {
        let lib = Library(prompts:Builtins.prompts)
        expectEqual(lib.browse("",language:.zh,frequent:false).count,40)
        expectEqual(lib.browse("",language:.en,frequent:false).count,40)
        expectEqual(lib.browse("",language:.en,frequent:true).count,8)
        expectTrue(lib.browse("weekly",language:.en,frequent:true).contains { $0.title == "Write a weekly update" })
        expectTrue(lib.browse("周报",language:.zh,frequent:false).contains { $0.title == "生成周报" })
        var edited = lib
        let i = edited.prompts.firstIndex { $0.title == "Write a weekly update" }!
        edited.prompts[i].useCount = 20
        expectEqual(edited.browse("",language:.en,frequent:true)[2].title,"Write a weekly update")
        let legacy = Data(#"{"version":1,"prompts":[{"id":"00000000-0000-4000-8000-000000000001","title":"Old","body":"请保留自定义内容","category":"Custom","pinned":false}]}"#.utf8)
        let restored = try JSONDecoder().decode(Library.self,from:legacy)
        expectEqual(restored.prompts[0].effectiveLanguage,.zh)
        expectEqual(Builtins.merging(into:restored).prompts[0].body,"请保留自定义内容")
        let encoded = try JSONEncoder().encode(edited)
        expectEqual(try JSONDecoder().decode(Library.self,from:encoded),edited)
        expectEqual(UIStrings.text("新增提示词",language:.en),"New prompt")
        expectEqual(UIStrings.text("保存",language:.zh),"保存")
    }
    func testHistoryRecommendationsPreserveEditsAndPins() throws {
        let data = Data(#"{"version":1,"provider":"codex-app-server","scannedAt":1,"threadCount":4,"coverage":{"threads_read":4},"candidates":[{"key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","title":"继续任务","body":"继续任务","count":5,"threadCount":3,"language":"zh"}]}"#.utf8)
        let report = try JSONDecoder().decode(HistoryDiscoveryReport.self,from:data)
        let original = Library()
        expectEqual(try HistoryRecommendations.applying(report.selecting([]),to:original),original)
        var object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let first = (object["candidates"] as! [[String:Any]])[0]
        var other = first
        other["key"] = String(repeating:"b",count:64); other["title"] = "启动服务"; other["body"] = "请启动服务。"
        object["candidates"] = [first,other]
        let multiple = try JSONDecoder().decode(HistoryDiscoveryReport.self,from:JSONSerialization.data(withJSONObject:object))
        let onlySelected = try HistoryRecommendations.applying(multiple.selecting([String(repeating:"b",count:64)]),to:original)
        expectEqual(onlySelected.prompts.count,original.prompts.count+1)
        expectEqual(onlySelected.prompts[0].title,"启动服务")
        var merged = try HistoryRecommendations.applying(report,to:original)
        expectEqual(merged.prompts.count,original.prompts.count+1)
        expectEqual(merged.browse("",language:.zh,frequent:true).first?.title,"继续任务")
        expectEqual(Array(merged.prompts.dropFirst()),original.prompts)
        merged.prompts[0].body = "User edited history prompt"
        merged.prompts[0].pinned = false
        let second = try HistoryRecommendations.applying(report,to:merged)
        expectEqual(second.prompts.count,merged.prompts.count)
        expectEqual(second.prompts[0].body,"User edited history prompt")
        expectFalse(second.prompts[0].pinned)
        expectEqual(second.prompts[0].historyCount,5)
    }
    func testSidebarPlacementHandlesOutsideLeftAndSmallScreens() {
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let right = SidebarPlacement.frame(host: CGRect(x: 100, y: 50, width: 800, height: 750), visible: visible)
        expectTrue(right.minX > 900)
        let left = SidebarPlacement.frame(host: CGRect(x: 650, y: 50, width: 900, height: 750), visible: visible)
        expectTrue(left.maxX < 650)
        let small = CGRect(x: -500, y: -200, width: 300, height: 400)
        let cramped = SidebarPlacement.frame(host: small, visible: small)
        expectTrue(small.contains(cramped))
        let custom = SidebarPlacement.frame(host:CGRect(x:100,y:50,width:800,height:750),visible:visible,preferredWidth:500,preferredHeight:700)
        expectEqual(custom.width,500)
        expectEqual(custom.height,700)
        let limited = SidebarPlacement.frame(host:small,visible:small,preferredWidth:1000,preferredHeight:2000)
        expectTrue(small.contains(limited))
    }
    func testBuiltinLibraryIsValidAndMergesWithoutOverwrite() throws {
        expectEqual(Builtins.prompts.count, 80)
        try Library(prompts: Builtins.prompts).validate()
        let custom = Prompt(title: "继续完成", body: "用户自行修改的内容", category: "自定义")
        let original = Library(prompts: [custom])
        let merged = Builtins.merging(into: original)
        expectEqual(merged.prompts.first, custom)
        expectEqual(merged.prompts.count, 80)
        expectEqual(Builtins.merging(into: merged), merged)
        expectEqual(Set(Builtins.prompts.map(\.id)).count, 80)
        expectTrue(Builtins.prompts.allSatisfy { !$0.body.contains("{{") })
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(value, "Expected true at \(file):\(line)")
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    expectTrue(!value, file: file, line: line)
}
func expectEqual<T: Equatable>(_ left: T, _ right: T, file: StaticString = #filePath, line: UInt = #line) {
    precondition(left == right, "Values differ at \(file):\(line)")
}
func expectThrows<T>(_ operation: @autoclosure () throws -> T) {
    do { _ = try operation() } catch { return }
    preconditionFailure("Expected an error")
}
func expectNoThrow<T>(_ operation: @autoclosure () throws -> T) {
    do { _ = try operation() } catch { preconditionFailure("Unexpected error: \(error)") }
}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(description: "Missing expected value") }
    return value
}

@main
struct Checks {
    static func main() throws {
        let suite = LibraryTests()
        let cases: [(String, () throws -> Void)] = [
            ("Unicode and multiline round trip", suite.testUnicodeAndMultilineRoundTrip),
            ("Search, categories and pin order", suite.testSearchMatchesAllTermsAcrossFieldsAndKeepsPinnedOrder),
            ("Invalid save preserves original", suite.testInvalidSaveDoesNotOverwriteExistingLibrary),
            ("Corrupt import preserves original", suite.testCorruptImportPreservesOriginalAndDoesNotMakeBackup),
            ("Import backs up original", suite.testValidImportBacksUpOriginal),
            ("Duplicate IDs and versions rejected", suite.testDuplicateIDsAndUnknownVersionRejected),
            ("Size limits and empty library", suite.testSizeLimitsAndEmptyLibrary),
            ("Input target policy", suite.testDeliveryRejectsOtherAppsSecureFieldsAndNonEditableControls),
            ("Composer ambiguity and exclusion policy", suite.testComposerRecognitionRejectsSearchSideChatAndUnknownControls),
            ("Stop and cancel controls are rejected", suite.testSendControlNeverMatchesStopOrCancel),
            ("Delivery receipt evidence", suite.testReceiptRequiresNewVisibleMessageAndClearedDraft),
            ("Duplicate and uncertain delivery gate", suite.testRepeatClicksAndUncertainDeliveryAreBlocked),
            ("Sidebar placement", suite.testSidebarPlacementHandlesOutsideLeftAndSmallScreens),
            ("History import preserves edits, pins and identities", suite.testHistoryRecommendationsPreserveEditsAndPins),
            ("Bilingual library, legacy migration and frequent ranking", suite.testLanguageLibraryAndFrequentOrdering),
            ("Builtin library and non-destructive merge", suite.testBuiltinLibraryIsValidAndMergesWithoutOverwrite)
        ]
        for (name, check) in cases { try check(); print("PASS \(name)") }
        print("\(cases.count) checks passed")
    }
}
