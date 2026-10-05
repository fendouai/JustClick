import Foundation

public struct PasteTarget: Equatable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

public enum PasteRoute: String, Sendable { case snapshot, accessibility, ocr }
public enum PasteLookup { case target(PasteTarget), absent, ambiguous }
public enum PasteDispatch { case dispatched, notDispatched }
public enum PasteStatus: String, Sendable {
    case filled, draftPresent, unreadableDraft, contextChanged, ambiguous, noTarget, dispatchFailed, verificationFailed, cancelled, emptyText
}
public struct PasteOutcome {
    public let status: PasteStatus
    public let route: PasteRoute?
    public let trace: [String]
    public var uncertain: Bool { status == .verificationFailed || ([.contextChanged, .cancelled].contains(status) && trace.contains("paste:dispatched")) }
}

/// Implementations bind one intended app/window/context before beginning a request.
@MainActor
public protocol PasteBackend: AnyObject {
    func scopeMatches() -> Bool
    func snapshot() -> PasteTarget?
    func locateAX() -> PasteLookup
    func locateOCR() async -> PasteLookup
    func isValid(_ target: PasteTarget) -> Bool
    func focus(_ target: PasteTarget) -> Bool
    func draft(_ target: PasteTarget) -> String?
    func paste(_ text: String, into target: PasteTarget) -> PasteDispatch
    func readBack(_ target: PasteTarget) -> String?
}

@MainActor
public enum PastePipeline {
    public static func fill(_ text: String, backend: any PasteBackend, checks: Int = 10, delay: Duration = .milliseconds(80), acceptMatchingDraft: Bool = false) async -> PasteOutcome {
        var trace: [String] = []
        func result(_ status: PasteStatus, _ route: PasteRoute? = nil) -> PasteOutcome {
            PasteOutcome(status: status, route: route, trace: trace)
        }
        guard !text.isEmpty else { return result(.emptyText) }
        for route in [PasteRoute.snapshot, .accessibility, .ocr] {
            guard !Task.isCancelled else { return result(.cancelled) }
            guard backend.scopeMatches() else { return result(.contextChanged) }
            trace.append("locate:\(route.rawValue)")
            let lookup: PasteLookup
            switch route {
            case .snapshot: lookup = backend.snapshot().map(PasteLookup.target) ?? .absent
            case .accessibility: lookup = backend.locateAX()
            case .ocr: lookup = await backend.locateOCR()
            }
            // OCR can take time; a result from a previous context must never be used.
            guard !Task.isCancelled else { return result(.cancelled, route) }
            guard backend.scopeMatches() else { return result(.contextChanged, route) }
            switch lookup {
            case .absent: continue
            case .ambiguous: return result(.ambiguous, route)
            case .target(let target):
                guard backend.isValid(target) else { trace.append("invalid:\(route.rawValue)"); continue }
                guard backend.focus(target) else { trace.append("focus-failed:\(route.rawValue)"); continue }
                guard backend.scopeMatches(), backend.isValid(target) else { return result(.contextChanged, route) }
                guard let draft = backend.draft(target) else { return result(.unreadableDraft, route) }
                if acceptMatchingDraft, draft == text {
                    trace.append("existing-draft:verified")
                    return result(.filled, route)
                }
                guard draft.isEmpty else { return result(.draftPresent, route) }
                trace.append("focus:\(route.rawValue)")
                guard backend.scopeMatches(), backend.isValid(target), backend.draft(target) == "" else { return result(.contextChanged, route) }
                guard backend.paste(text, into: target) == .dispatched else { return result(.dispatchFailed, route) }
                trace.append("paste:dispatched")
                for attempt in 0..<max(1, checks) {
                    guard !Task.isCancelled else { return result(.cancelled, route) }
                    guard backend.scopeMatches(), backend.isValid(target) else { return result(.contextChanged, route) }
                    if backend.readBack(target) == text { trace.append("paste:verified"); return result(.filled, route) }
                    if attempt + 1 < checks { try? await Task.sleep(for: delay) }
                }
                // Never retry via another route after a potentially successful dispatch.
                return result(.verificationFailed, route)
            }
        }
        return result(.noTarget)
    }
}
