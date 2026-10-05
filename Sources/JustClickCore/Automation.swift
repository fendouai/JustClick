import Foundation
import CoreGraphics

public enum ComposerPolicy {
    public static func isComposer(role: String, label: String, enabled: Bool, editable: Bool, secure: Bool, excludedAncestor: Bool, structuralMatch: Bool = false) -> Bool {
        guard enabled, editable, !secure, !excludedAncestor,
              ["AXTextArea", "AXTextField"].contains(role) else { return false }
        let value = label.lowercased()
        let rejected = ["search", "搜索", "terminal", "终端", "password", "密码", "side chat", "侧聊", "address", "地址"]
        guard !rejected.contains(where: value.contains) else { return false }
        return ["composer", "prompt", "message", "ask ", "do anything", "消息", "提问", "问题", "描述任务", "输入指令", "询问", "发送给"].contains(where: value.contains)
            || (role == "AXTextArea" && structuralMatch)
    }

    public static func sendKind(_ label: String) -> String? {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !["stop", "停止", "interrupt", "中断", "cancel", "取消", "dictat", "语音", "voice", "feedback", "反馈", "new chat", "新聊天", "new task", "新任务"].contains(where: value.contains) else { return nil }
        if ["queue", "排队", "加入队列"].contains(where: value.contains) { return "queue" }
        if ["send", "submit", "发送", "提交", "steer", "引导"].contains(where: value.contains) { return "send" }
        return nil
    }
}

/// A successful key/mouse dispatch is never a delivery receipt.
public enum DeliveryReceipt: String {
    case confirmed, draftOnly, unknown, contextChanged
    public static func evaluate(contextMatches: Bool, draft: String?, inserted: String, visibleMatchesBefore: Int, visibleMatchesAfter: Int) -> DeliveryReceipt {
        guard contextMatches else { return .contextChanged }
        if let draft, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .draftOnly }
        guard draft != nil, !inserted.isEmpty, visibleMatchesAfter > visibleMatchesBefore else { return .unknown }
        return .confirmed
    }
}

/// Suppresses concurrent/rapid clicks and automatic retries after uncertain delivery.
/// A new explicit user action can acknowledge uncertainty without locking the interface.
public struct DeliveryGate {
    public private(set) var inFlight = false
    public private(set) var needsAcknowledgement = false
    private var lastAction: Date?
    public init() {}
    public mutating func begin(now: Date = Date(), explicitRetry: Bool = false) -> Bool {
        guard !inFlight, (!needsAcknowledgement || explicitRetry), lastAction.map({ now.timeIntervalSince($0) >= 1.5 }) ?? true else { return false }
        needsAcknowledgement = false
        inFlight = true; lastAction = now; return true
    }
    public mutating func finish(uncertain: Bool) { inFlight = false; needsAcknowledgement = uncertain }
    public mutating func acknowledge() { needsAcknowledgement = false }
}

public enum SidebarPlacement {
    /// AppKit coordinates, clamped even on a small screen. Prefer outside the host.
    public static func frame(host: CGRect, visible: CGRect, preferredWidth: CGFloat? = nil, preferredHeight: CGFloat? = nil) -> CGRect {
        var automaticWidth = min(520, max(380, visible.width * 0.28))
        let sideSpace = max(visible.maxX-host.maxX-8,host.minX-visible.minX-8)
        if sideSpace >= 380 { automaticWidth = min(automaticWidth,sideSpace) }
        let automaticHeight = min(900, max(640, visible.height * 0.88))
        let width = min(max(320,preferredWidth ?? automaticWidth), visible.width)
        let height = min(max(480,preferredHeight ?? automaticHeight), visible.height)
        let right = host.maxX + 8
        let left = host.minX - width - 8
        let x = right + width <= visible.maxX ? right : left >= visible.minX ? left : visible.maxX - width
        let y = min(max(host.maxY - height - 16, visible.minY), visible.maxY - height)
        return CGRect(x: min(max(x, visible.minX), visible.maxX - width), y: y, width: width, height: height)
    }
}
