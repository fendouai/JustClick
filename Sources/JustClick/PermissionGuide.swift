import AppKit
import ApplicationServices

@MainActor
enum PermissionGuide {
    private static var presenting = false
    static func showScreenCapture() {
        guard !presenting else { return }
        presenting = true
        defer { presenting = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "允许本地视觉定位输入框"
        alert.informativeText = "焦点快照和辅助功能未能定位输入框。视觉兜底需要 macOS 的屏幕录制权限。\n\n请打开「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」（部分系统称为「屏幕录制」），添加并开启下面这个 JustClick。若系统要求，请退出并重新打开 JustClick，再回到 Codex 点击「仅填入」。\n\n当前应用：\n\(Bundle.main.bundleURL.path)\n\n此权限允许应用读取屏幕内容。JustClick 的 OCR 仅在本机处理目标窗口截图，不上传截图；开启权限不保证定位成功。复制提示词不需要此权限。"
        alert.addButton(withTitle: "打开屏幕录制设置")
        alert.addButton(withTitle: "定位当前应用")
        alert.addButton(withTitle: "稍后")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else if result == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }
    static func show() {
        guard !presenting else { return }
        presenting = true
        defer { presenting = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "允许 JustClick 自动填入并发送"
        alert.informativeText = "请打开「系统设置 → 隐私与安全性 → 辅助功能」。\n\n1. 找到 JustClick 并打开右侧开关。\n2. 若列表没有它，点击 ＋，添加下面这个应用。\n3. 若有旧副本，请使用下面的固定路径。\n4. 回到 Codex，再点击纸飞机发送。\n\n当前应用：\n\(Bundle.main.bundleURL.path)\n\n复制提示词不需要这项权限。JustClick 不会替你打开权限开关。"
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "定位当前应用")
        alert.addButton(withTitle: "稍后")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            // Register this exact running copy in TCC, then take the user to its settings.
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if result == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }
}
