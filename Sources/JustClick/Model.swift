import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import JustClickCore

@MainActor
final class Model: ObservableObject {
    @Published var collapsed = true {
        didSet { Preferences.defaults.set(collapsed, forKey: "quickCollapsed"); resizeQuick?() }
    }
    @Published var keepExpanded = Preferences.defaults.bool(forKey: "quickPinned") {
        didSet { Preferences.defaults.set(keepExpanded, forKey: "quickPinned"); resizeQuick?() }
    }
    @Published var menuBarOnly = Preferences.defaults.bool(forKey: "menuBarOnly") {
        didSet { Preferences.defaults.set(menuBarOnly, forKey: "menuBarOnly"); modeChanged?() }
    }
    var modeChanged: (() -> Void)?
    var anchorMoved: (() -> Void)?
    var closeQuick: (() -> Void)?
    @Published var deliveryFeedback = false
    var visibleQuickResults: [Prompt] { quickQuery.isEmpty && !keepExpanded ? Array(quickResults.prefix(5)) : quickResults }
    @Published var quickQuery = ""
    @Published var quickSelected: UUID?
    @Published private var quickOrder: [UUID] = []
    var openManager: ((Page) -> Void)?
    var resizeQuick: (() -> Void)?
    var quickResults: [Prompt] {
        let matching = library.browse(quickQuery, language: language, frequent: false)
        if !quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return matching }
        return quickOrder.compactMap { id in matching.first { $0.id == id } }
    }
    func refreshQuickOrder() {
        quickOrder = library.browse("", language: language, frequent: true).map(\.id)
        Preferences.defaults.set(quickOrder.map(\.uuidString), forKey: "quickOrder-" + language.rawValue)
    }
    func restoreQuickOrder() {
        let saved = Preferences.defaults.stringArray(forKey: "quickOrder-" + language.rawValue) ?? []
        quickOrder = saved.compactMap(UUID.init(uuidString:)).filter { id in library.prompts.contains { $0.id == id && $0.effectiveLanguage == language } }
        if quickOrder.isEmpty { refreshQuickOrder() }
    }
    enum Page: String { case library, discovery }
    @Published var page: Page = .library
    @Published var historyReport: HistoryDiscoveryReport?
    @Published var selectedHistoryKeys: Set<String> = []
    @Published var library = Library()
    @Published var language: PromptLanguage = PromptLanguage(rawValue:Preferences.defaults.string(forKey:"promptLanguage") ?? "") ?? .preferred {
        didSet {
            Preferences.defaults.set(language.rawValue,forKey:"promptLanguage")
            query = ""; quickQuery = ""; category = nil; selected = results.first?.id; refreshMenu?()
            selectedHistoryKeys = []
            restoreQuickOrder()
        }
    }
    @Published var frequentOnly = true
    @Published var query = ""
    @Published var category: String? = nil
    @Published var selected: UUID?
    @Published var message = "切回 Codex 后自动显示。点击文字填入，点击纸飞机填入并发送。"
    @Published var editing: Prompt?
    @Published var showEditor = false
    @Published var autoShow = Preferences.defaults.object(forKey: "autoShow") as? Bool ?? true {
        didSet { Preferences.defaults.set(autoShow, forKey: "autoShow"); refreshCompanion?() }
    }
    @Published var permissionGranted = AXIsProcessTrusted()
    @Published var screenPermissionGranted = CGPreflightScreenCaptureAccess()
    @Published var targetName = "未绑定 Codex"
    @Published var retryLocked = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var busy = false
    @Published var historyBusy = false
    let delivery = Delivery()
    let file: LibraryFile
    var hide: (() -> Void)?
    var refreshMenu: (() -> Void)?
    var refreshCompanion: (() -> Void)?
    var resetWindowSize: (() -> Void)?
    private var deliveryGate = DeliveryGate()
    private(set) var loadFailed = false

    init() {
        let override = ProcessInfo.processInfo.environment["JUSTCLICK_DATA_DIR"]
        let directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JustClick")
        file = LibraryFile(url: directory.appendingPathComponent("prompts.json"))
        do {
            if FileManager.default.fileExists(atPath: file.url.path) { library = try file.load() }
            else { try file.save(library) }
        } catch {
            loadFailed = true
            library = Library(prompts: [])
            message = "无法读取提示词库：\(error.localizedDescription)。原文件已保留，请导入有效备份恢复。"
        }
        selected = library.filtered("").first?.id
        let marker = file.url.deletingLastPathComponent().appendingPathComponent("builtins-v\(Builtins.version).installed")
        if !loadFailed, !FileManager.default.fileExists(atPath: marker.path) {
            if installBuiltins() {
                do { try Data("installed".utf8).write(to: marker, options: .atomic) }
                catch { message = "提示词已添加，但升级标记未保存：\(error.localizedDescription)" }
            }
        }
        restoreQuickOrder()
    }

    var results: [Prompt] { library.browse(query,category:category,language:language,frequent:frequentOnly) }
    var languageCount: Int { library.prompts.filter { $0.effectiveLanguage == language }.count }
    func t(_ text: String) -> String { UIStrings.text(text,language:language) }
    var current: Prompt? { results.first { $0.id == selected } ?? results.first }
    var categories: [String] { Array(Set(library.prompts.filter { $0.effectiveLanguage == language }.map(\.category))).sorted() }
    @discardableResult
    func installBuiltins() -> Bool {
        guard !loadFailed else { message = "请先恢复提示词库，再添加内置提示词。"; return false }
        let merged = Builtins.merging(into: library)
        do {
            if merged != library {
                let backup = file.url.deletingLastPathComponent().appendingPathComponent("prompts-backup-\(UUID().uuidString).json")
                try LibraryFile(url: backup).save(library)
                try file.save(merged)
                library = merged
            }
            selected = results.first?.id
            message = "内置提示词已添加，原有内容与修改已保留。"
            refreshMenu?()
            return true
        } catch { message = "添加内置库失败：\(error.localizedDescription)"; return false }
    }
    func move(_ delta: Int) {
        guard !results.isEmpty else { selected = nil; return }
        let index = results.firstIndex { $0.id == selected } ?? 0
        selected = results[max(0, min(results.count - 1, index + delta))].id
    }
    func edit(_ prompt: Prompt? = nil) {
        editing = prompt ?? Prompt(title:"",body:"",category:language == .zh ? "常用" : "Everyday",language:language)
        showEditor = true
    }
    @discardableResult
    func persist(_ next: Library) -> Bool {
        guard !loadFailed else { message = "请先导入有效备份，避免覆盖无法读取的原文件。"; return false }
        do { try file.save(next); library = next; restoreQuickOrder(); refreshMenu?(); return true }
        catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
    func save(_ prompt: Prompt) -> Bool {
        var next = library
        if let index = next.prompts.firstIndex(where: { $0.id == prompt.id }) { next.prompts[index] = prompt }
        else { next.prompts.append(prompt) }
        guard persist(next) else { return false }
        page = .library
        if prompt.effectiveLanguage != language { language = prompt.effectiveLanguage }
        if !results.contains(where: { $0.id == prompt.id }) {
            category = nil
            query = prompt.title
        }
        selected = prompt.id; message = "已保存“\(prompt.title)”。"; return true
    }
    func remove(_ prompt: Prompt) {
        let alert = NSAlert()
        alert.messageText = t("删除") + " “\(prompt.title)” ?"
        alert.informativeText = t("删除前会备份当前提示词库，可从数据目录重新导入。")
        alert.addButton(withTitle:t("删除")); alert.addButton(withTitle:t("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let backup = file.url.deletingLastPathComponent().appendingPathComponent("prompts-backup-\(UUID().uuidString).json")
            try LibraryFile(url: backup).save(library)
            var next = library; next.prompts.removeAll { $0.id == prompt.id }
            if persist(next) { message = "已删除，原库已备份。" }
        } catch { message = "备份失败，未删除：\(error.localizedDescription)" }
    }
    func recordUsage(_ prompt: Prompt) {
        var next = library
        guard let index = next.prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        next.prompts[index].useCount = min(1_000_000,(next.prompts[index].useCount ?? 0)+1)
        next.prompts[index].lastUsedAt = Date()
        _ = persist(next)
    }
    func duplicate(_ prompt: Prompt) {
        var copy = prompt; copy.id = UUID(); copy.title += language == .zh ? " 副本" : " Copy"
        copy.pinned = false; copy.useCount = nil; copy.lastUsedAt = nil
        copy.historyKey = nil; copy.historyCount = nil; copy.historyThreadCount = nil; copy.historyRank = nil
        editing = copy; showEditor = true
    }
    var historyCandidates: [HistoryCandidate] { historyReport?.candidates.filter { $0.language == language } ?? [] }
    func historyIsAdded(_ candidate: HistoryCandidate) -> Bool { library.prompts.contains { $0.historyKey == candidate.key } }
    func openDiscovery() {
        page = .discovery
        if historyReport == nil {
            let url = file.url.deletingLastPathComponent().appendingPathComponent("history-candidates.json")
            if let data = try? Data(contentsOf:url), data.count <= 2_000_000,
               let report = try? JSONDecoder().decode(HistoryDiscoveryReport.self,from:data), report.version == 1, report.provider == "codex-app-server", report.candidates.count <= 100 {
                historyReport = report
            }
        }
    }
    func addSelectedHistory() {
        guard let report = historyReport, !selectedHistoryKeys.isEmpty else { return }
        do {
            let selectedReport = report.selecting(selectedHistoryKeys)
            let merged = try HistoryRecommendations.applying(selectedReport,to:library)
            if merged != library {
                let backup = file.url.deletingLastPathComponent().appendingPathComponent("prompts-backup-\(UUID().uuidString).json")
                try LibraryFile(url:backup).save(library)
                guard persist(merged) else { return }
            }
            message = language == .zh ? "已加入所选 \(selectedReport.candidates.count) 条提示词。" : "Added \(selectedReport.candidates.count) selected prompts."
            selectedHistoryKeys = []
            refreshMenu?()
        } catch { message = error.localizedDescription }
    }
    func discoverHistory() {
        guard !historyBusy, !loadFailed else { return }
        page = .discovery
        historyBusy = true
        message = "正在本地读取 Codex 历史并整理常用提示词…"
        Task {
            defer { historyBusy = false }
            do {
                let report = try await HistoryImportService.discover(to:file.url.deletingLastPathComponent().appendingPathComponent("history-candidates.json"))
                historyReport = report
                selectedHistoryKeys = []
                let count = report.candidates.count
                message = language == .zh
                    ? "已读取 \(report.coverage["threads_read"] ?? 0) 个会话，发现 \(count) 条候选，请勾选后加入。"
                    : "Read \(report.coverage["threads_read"] ?? 0) chats; found \(count) suggestions. Select the ones to add."
                if (report.coverage["threads_failed"] ?? 0) > 0 || (report.coverage["thread_limit_reached"] ?? 0) > 0 || (report.coverage["time_limit_reached"] ?? 0) > 0 {
                    message += language == .zh ? " 部分历史未覆盖，详见本地报告。" : " Coverage is partial; see the local report."
                }
                refreshMenu?()
            } catch { message = (language == .zh ? "历史读取失败，原库未覆盖：" : "History import failed; library preserved: ") + error.localizedDescription }
        }
    }
    func pin(_ prompt: Prompt) { var updated = prompt; updated.pinned.toggle(); _ = save(updated) }
    func reorder(_ prompt: Prompt, _ delta: Int) {
        var next = library
        guard let index = next.prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        let other = index + delta
        guard next.prompts.indices.contains(other) else { return }
        next.prompts.swapAt(index, other); _ = persist(next)
    }
    func use(_ prompt: Prompt, copyOnly: Bool = false, send: Bool = false) {
        if copyOnly {
            recordUsage(prompt)
            message = delivery.copy(prompt.body) ? "已复制“\(prompt.title)”，可按 ⌘V 粘贴。" : "复制失败。"
            return
        }
        guard !busy else { return }
        guard delivery.trusted else {
            message = "完成弹窗中的辅助功能授权后，回到 Codex 点击纸飞机即可发送。"
            delivery.requestAccess()
            permissionGranted = delivery.trusted
            return
        }
        // Every invocation here is an explicit user action, not an automatic retry.
        guard deliveryGate.begin(explicitRetry: true) else { return }
        retryLocked = false
        recordUsage(prompt)
        busy = true
        deliveryFeedback = true
        Task {
            let result = await delivery.deliver(prompt.body, send: send)
            message = result.message
            deliveryGate.finish(uncertain: result.uncertain)
            retryLocked = result.uncertain
            busy = false
            if result.succeeded && !keepExpanded { closeQuick?() }
            refreshMenu?()
            refreshCompanion?()
        }
    }
    func acknowledgeDelivery() {
        deliveryGate.acknowledge(); retryLocked = false
        message = "重试锁定已解除。请确认原聊天没有重复消息，再操作。"
    }
    func toggleLogin() {
        Task {
            do {
                if SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
                loginEnabled = SMAppService.mainApp.status == .enabled
                message = SMAppService.mainApp.status == .requiresApproval
                    ? "请到系统设置的登录项中允许 JustClick。"
                    : loginEnabled ? "已开启登录时启动。" : "已关闭登录时启动。"
            } catch { message = "登录项设置失败：\(error.localizedDescription)。请在系统设置中手动添加此应用。" }
        }
    }
    func importLibrary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            library = try file.importFile(url); loadFailed = false
            selected = results.first?.id; message = "已导入；原库已备份。"; refreshMenu?()
        } catch { message = "导入失败：\(error.localizedDescription)" }
    }
    func exportLibrary() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "justclick-prompts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try LibraryFile(url: url).save(library); message = "已导出提示词库。" }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }
}
