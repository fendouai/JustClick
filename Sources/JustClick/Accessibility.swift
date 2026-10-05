import AppKit
import ApplicationServices

enum AX {
    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }
    static func label(_ element: AXUIElement) -> String {
        [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue"]
            .compactMap { value(element, $0) as String? }.joined(separator: " ")
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = value(element, kAXPositionAttribute),
              let size: AXValue = value(element, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    struct Node { let element: AXUIElement; let role: String; let excluded: Bool }
    static func nodes(_ root: AXUIElement) -> [Node] {
        var pending = [(root, false, 0, false)]; var result: [Node] = []; var cursor = 0
        let deadline = Date().addingTimeInterval(3)
        // Breadth-first: don't exhaust the scan in a long transcript before reaching the composer.
        while cursor < pending.count, result.count < 1600, Date() < deadline {
            let (element, inherited, depth, webAncestor) = pending[cursor]; cursor += 1
            let role: String = value(element, kAXRoleAttribute) ?? ""
            let label = ["AXGroup", "AXWebArea", "AXScrollArea", "AXSplitGroup"].contains(role)
                ? ((value(element, kAXIdentifierAttribute) as String? ?? "") + " " + (value(element, kAXDescriptionAttribute) as String? ?? "")).lowercased() : ""
            let containerExcluded = !["AXWindow", "AXApplication", "AXStaticText", "AXHeading"].contains(role)
                && ["terminal", "终端", "side chat", "side-chat", "sidechat", "sideconversation", "侧聊", "code editor", "source editor", "代码编辑", "in-app-browser", "browser-pane", "browser-content", "浏览器内容"].contains(where: label.contains)
            let pageURL: URL? = value(element, kAXURLAttribute)
            // Electron's top-level application view may itself have an HTTPS URL.
            let embeddedWebPage = webAncestor && role == "AXWebArea" && ["http", "https"].contains(pageURL?.scheme ?? "")
            let excluded = inherited || role == "AXDialog" || containerExcluded || embeddedWebPage
            result.append(Node(element: element, role: role, excluded: excluded))
            if depth < 24, let children: [AXUIElement] = value(element, kAXChildrenAttribute) {
                pending.append(contentsOf: children.map { ($0, excluded, depth + 1, webAncestor || role == "AXWebArea") })
            }
        }
        return result
    }
    static func editable(_ element: AXUIElement) -> Bool {
        if let explicit: Bool = value(element, "AXEditable") { return explicit }
        return settable(element, kAXSelectedTextAttribute) || settable(element, kAXValueAttribute)
    }
    static func text(_ element: AXUIElement) -> String? { value(element, kAXValueAttribute) }
    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
}
