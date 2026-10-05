import ApplicationServices

public enum KeyboardTransport {
    public static func key(_ code: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t) -> Bool {
        guard let down = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true),
              let up = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else { return false }
        down.flags = flags; up.flags = flags
        down.postToPid(pid); up.postToPid(pid)
        return true
    }
    /// Dispatch only. The caller must verify the intended window, draft and receipt.
    public static func pressReturn(to pid: pid_t) -> Bool {
        guard let down = CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:true),
              let up = CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:false) else { return false }
        down.postToPid(pid); up.postToPid(pid)
        return true
    }
}
