import Foundation

public enum PromptLanguage: String, Codable, CaseIterable {
    case zh, en
    public static var preferred: Self { Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en }
}

public struct Prompt: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var body: String
    public var category: String
    public var pinned: Bool
    public var language: PromptLanguage?
    public var source: String?
    public var sourceURL: String?
    public var useCount: Int?
    public var lastUsedAt: Date?
    public var historyKey: String?
    public var historyCount: Int?
    public var historyThreadCount: Int?
    public var historyRank: Int?

    public init(id: UUID = UUID(), title: String, body: String, category: String = "常用", pinned: Bool = false, language: PromptLanguage? = nil, source: String? = nil, sourceURL: String? = nil) {
        self.id = id; self.title = title; self.body = body; self.category = category; self.pinned = pinned
        self.language = language; self.source = source; self.sourceURL = sourceURL
    }
    public var effectiveLanguage: PromptLanguage {
        language ?? (body.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } ? .zh : .en)
    }

    public static let samples = [
        Prompt(title: "继续完成", body: "请继续当前任务，直到完成并验证。遇到问题先尝试解决，完成后简要说明结果和验证情况。", pinned: true),
        Prompt(title: "汇报进度", body: "请简要说明已完成什么、还有什么、当前阻碍是什么，以及下一步准备做什么。", pinned: true),
        Prompt(title: "检查问题", body: "请检查当前实现，找出实际存在的问题，按影响排序，并给出具体修复建议。", category: "开发"),
        Prompt(title: "执行验证", body: "请执行与当前修改相关的验证，修复发现的问题，并说明通过了哪些检查、还有哪些限制。", category: "开发"),
        Prompt(title: "简洁解释", body: "请用简单、直接的中文解释，先说结论，再说明关键原因，避免不必要的术语。", category: "表达")
    ]
}

public struct Library: Codable, Equatable {
    public var version: Int = 1
    public var prompts: [Prompt]
    public init(prompts: [Prompt] = Prompt.samples) { self.prompts = prompts }

    public func validate() throws {
        guard version == 1 else { throw LibraryError.invalid("不支持的文件版本：\(version)") }
        guard prompts.count <= 2000 else { throw LibraryError.invalid("最多支持 2000 条提示词") }
        guard Set(prompts.map(\.id)).count == prompts.count else { throw LibraryError.invalid("提示词 ID 重复") }
        for prompt in prompts {
            guard !prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !prompt.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryError.invalid("名称和内容不能为空")
            }
            guard prompt.title.count <= 200, prompt.body.utf8.count <= 500_000,
                  prompt.category.count <= 100 else { throw LibraryError.invalid("提示词内容过长") }
        }
    }

    public func filtered(_ query: String, category: String? = nil) -> [Prompt] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return prompts.enumerated().filter { _, p in
            (category == nil || p.category == category) && terms.allSatisfy {
                "\(p.title) \(p.category) \(p.body)".localizedStandardContains($0)
            }
        }.sorted {
            $0.element.pinned == $1.element.pinned ? $0.offset < $1.offset : $0.element.pinned
        }.map(\.element)
    }
    public func browse(_ query: String, category: String? = nil, language: PromptLanguage, frequent: Bool) -> [Prompt] {
        let matching = filtered(query,category:category).filter { $0.effectiveLanguage == language }
        guard frequent, query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, category == nil else { return matching }
        return Array(matching.enumerated().sorted { a,b in
            if a.element.pinned != b.element.pinned { return a.element.pinned }
            if a.element.historyRank != b.element.historyRank { return (a.element.historyRank ?? Int.max) < (b.element.historyRank ?? Int.max) }
            if (a.element.useCount ?? 0) != (b.element.useCount ?? 0) { return (a.element.useCount ?? 0) > (b.element.useCount ?? 0) }
            if a.element.lastUsedAt != b.element.lastUsedAt { return (a.element.lastUsedAt ?? .distantPast) > (b.element.lastUsedAt ?? .distantPast) }
            return a.offset < b.offset
        }.prefix(8).map(\.element))
    }
}

public enum LibraryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public struct LibraryFile {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Library {
        let data = try Data(contentsOf: url)
        guard data.count <= 10_000_000 else { throw LibraryError.invalid("文件超过 10 MB") }
        let library = try JSONDecoder().decode(Library.self, from: data)
        try library.validate()
        return library
    }

    public func save(_ library: Library) throws {
        try library.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(library)
        guard data.count <= 10_000_000 else { throw LibraryError.invalid("文件超过 10 MB") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Validate first; preserve the previous library before replacing it.
    public func importFile(_ source: URL) throws -> Library {
        let incoming = try LibraryFile(url: source).load()
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent("prompts-backup-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: backup)
        }
        try save(incoming)
        return incoming
    }
}

public enum InputPolicy {
    public static let supportedBundles: Set<String> = ["com.openai.codex", "com.openai.chat", "com.openai.chatgpt"]
    public static func allows(bundle: String, role: String, editable: Bool, secure: Bool) -> Bool {
        supportedBundles.contains(bundle) && ["AXTextArea", "AXTextField"].contains(role) && editable && !secure
    }
}
