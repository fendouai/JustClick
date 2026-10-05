import AppKit

/// Only restores if nobody else changed the clipboard while this paste was running.
@MainActor
public final class ClipboardTransaction {
    private let board: NSPasteboard
    private var previous: [[NSPasteboard.PasteboardType: Data]] = []
    private var ownedChangeCount: Int?
    public init(board: NSPasteboard = .general) { self.board = board }
    @discardableResult public func begin(text: String) -> Bool {
        guard ownedChangeCount == nil else { return false }
        previous = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        board.clearContents()
        ownedChangeCount = board.changeCount
        guard board.setString(text, forType: .string) else { _ = restore(); return false }
        ownedChangeCount = board.changeCount
        return true
    }
    public var unchanged: Bool { ownedChangeCount == board.changeCount }
    /// Replace our own temporary clipboard value without losing the original snapshot.
    public func replaceOwnedText(_ text: String) -> Bool {
        guard unchanged else { return false }
        board.clearContents(); ownedChangeCount = board.changeCount
        let success = board.setString(text,forType:.string)
        ownedChangeCount = board.changeCount
        return success
    }
    public func adoptVerifiedCopy(_ expected: String) -> Bool {
        guard ownedChangeCount != nil, board.string(forType:.string) == expected else { return false }
        ownedChangeCount = board.changeCount
        return true
    }
    @discardableResult public func restore() -> Bool {
        guard let ownedChangeCount else { return false }
        defer { self.ownedChangeCount = nil; previous = [] }
        guard board.changeCount == ownedChangeCount else { return false }
        let items = previous.map { values in
            let item = NSPasteboardItem()
            values.forEach { item.setData($0.value, forType: $0.key) }
            return item
        }
        board.clearContents()
        return items.isEmpty || board.writeObjects(items)
    }
}
