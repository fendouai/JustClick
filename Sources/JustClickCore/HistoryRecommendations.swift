import Foundation

public struct HistoryCandidate: Codable {
    public let key: String
    public let title: String
    public let body: String
    public let count: Int
    public let threadCount: Int
    public let language: PromptLanguage
}
public struct HistoryDiscoveryReport: Codable {
    public let version: Int
    public let provider: String
    public let scannedAt: Double
    public let threadCount: Int
    public let coverage: [String:Int]
    public let candidates: [HistoryCandidate]
    public func selecting(_ keys: Set<String>) -> HistoryDiscoveryReport {
        HistoryDiscoveryReport(version:version,provider:provider,scannedAt:scannedAt,threadCount:threadCount,coverage:coverage,candidates:candidates.filter { keys.contains($0.key) })
    }
}
public enum HistoryRecommendations {
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.components(separatedBy:.whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator:" ").trimmingCharacters(in:CharacterSet(charactersIn:"。.!！?？"))
    }
    public static func applying(_ report: HistoryDiscoveryReport, to library: Library) throws -> Library {
        guard report.version == 1, report.provider == "codex-app-server", report.candidates.count <= 100 else { throw LibraryError.invalid("Unsupported history report") }
        var result = library
        var additions: [Prompt] = []
        for (rank,candidate) in report.candidates.enumerated() {
            guard candidate.count >= 2, candidate.threadCount >= 2,
                  candidate.threadCount <= candidate.count,
                  candidate.key.count == 64, candidate.key.allSatisfy({ $0.isHexDigit }),
                  !candidate.title.isEmpty, candidate.title.count <= 200,
                  !candidate.body.isEmpty, candidate.body.count <= 1200 else { throw LibraryError.invalid("Invalid history candidate") }
            if let index = result.prompts.firstIndex(where: { $0.historyKey == candidate.key || normalized($0.body) == normalized(candidate.body) }) {
                // Keep user-edited text, category, language and pin state on later imports.
                result.prompts[index].historyKey = candidate.key
                result.prompts[index].historyCount = candidate.count
                result.prompts[index].historyThreadCount = candidate.threadCount
                result.prompts[index].historyRank = rank
            } else {
                let raw = String(candidate.key.prefix(32))
                let parts = [String(raw.prefix(8)),String(raw.dropFirst(8).prefix(4)),String(raw.dropFirst(12).prefix(4)),String(raw.dropFirst(16).prefix(4)),String(raw.suffix(12))]
                guard let id = UUID(uuidString:parts.joined(separator:"-")), !result.prompts.contains(where:{$0.id==id}), !additions.contains(where:{$0.id==id}) else { throw LibraryError.invalid("Duplicate history identity") }
                var prompt = Prompt(id:id,title:candidate.title,body:candidate.body,category:candidate.language == .zh ? "我的常用" : "My frequent prompts",pinned:true,language:candidate.language,source:"Codex local history")
                prompt.historyKey = candidate.key; prompt.historyCount = candidate.count
                prompt.historyThreadCount = candidate.threadCount; prompt.historyRank = rank
                additions.append(prompt)
            }
        }
        result.prompts.insert(contentsOf:additions,at:0)
        try result.validate()
        return result
    }
}
