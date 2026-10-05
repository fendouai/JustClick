import Foundation

public enum UIStrings {
    public static func text(_ value: String, language: PromptLanguage) -> String {
        guard language == .en else { return value }
        if let result = pairs[value] { return result }
        var result = value
        for (pattern,replacement) in patterns { result = result.replacingOccurrences(of:pattern,with:replacement,options:.regularExpression) }
        for key in pairs.keys.sorted(by: { $0.count > $1.count }) where key.count >= 4 {
            result = result.replacingOccurrences(of:key,with:pairs[key]!)
        }
        return result
    }
    private static let patterns: [(String,String)] = [
        (#"图标识别：＋(\d+) 个，麦克风 (\d+) 个，有效配对 (\d+) 组"#,"Icons: + $1, microphone $2, valid pairs $3"),
        (#"已复制“(.+)”，可按 ⌘V 粘贴。"#,"Copied “$1”. Press ⌘V to paste."),
        (#"已保存“(.+)”。"#,"Saved “$1”."),
        (#"输入区域检测到 (\d+) 段文字、(\d+) 个字符，未认定为空输入框，未粘贴。"#,"Detected $1 text regions ($2 characters). The field is not confirmed empty; nothing pasted.")
    ]
    private static let pairs: [String:String] = [
        "个人提示词库":"Personal prompt library", "恢复自适应大小":"Reset adaptive window size",
        "先预览候选，再勾选需要的提示词加入。已有内容不会自动改变。":"Preview suggestions, then select the prompts you want to add. Your library will not change automatically.",
        "读取历史":"Read history", "全选可加入":"Select available", "已加入":"Added", "加入所选":"Add selected",
        "暂无此语言的候选，点击读取历史开始发现。":"No suggestions for this language yet. Read history to discover prompts.",
        "发现常用":"Discover prompts", "关闭":"Close", "开始发现":"Start discovery",
        "读取我的历史对话，发现我的常用提示词":"Read my chat history to discover my frequent prompts",
        "读取本机 Codex 历史，整理重复使用的提示词，并放到常用列表前面。已有内容与手工修改会保留。":"Read local Codex history, find reusable prompts, and bring them to the top. Existing prompts and manual edits are preserved.",
        "从对话发现常用":"Discover from chats",
        "读取本地 Codex 对话，整理常用提示词并放到前面":"Read local Codex chats and bring your frequent prompts to the top",
        "从 Codex 历史更新常用提示词…":"Refresh frequent prompts from Codex history…",
        "正在整理历史…":"Analyzing local history…",
        "正在本地读取 Codex 历史并整理常用提示词…":"Reading local Codex history and finding reusable prompts…",
        "提示词":"Prompt", "自动填入":"Auto-fill", "自动发送":"Auto-send",
        "点文字填入 · 点纸飞机发送":"Click text to fill · Plane to send",
        "新增提示词":"New prompt", "随 Codex 自动显示":"Follow Codex automatically",
        "关闭登录时启动":"Disable launch at login", "开启登录时启动":"Launch at login",
        "开启辅助功能权限…":"Accessibility permissions…", "导入 JSON…":"Import JSON…", "导出 JSON…":"Export JSON…",
        "添加/恢复内置提示词":"Restore built-in prompts", "打开数据目录":"Open data folder", "收起侧栏":"Hide sidebar",
        "搜索提示词":"Search prompts", "分组":"Category", "全部":"All", "常用":"Everyday", "常用优先":"Frequent",
        "所有提示词":"All prompts", "语言":"Language", "仅填入":"Fill only", "仅填入，不发送":"Fill without sending",
        "填入并发送":"Fill & send", "填入":"Fill", "发送":"Send", "复制":"Copy", "编辑":"Edit", "删除":"Delete",
        "复制为新提示词":"Duplicate prompt", "取消置顶":"Unpin", "置顶":"Pin", "上移":"Move up", "下移":"Move down",
        "删除并备份":"Delete (with backup)", "没有匹配的提示词":"No matching prompts", "预览":"Preview",
        "视觉定位需授权：打开指引…":"Screen recording access: setup…", "发送需授权：开启辅助功能…":"Accessibility access: setup…",
        "上次结果未确认。可继续选择、编辑；再次点击操作按钮会重新尝试。":"Last action is unconfirmed. Keep browsing or editing; another action click will retry.",
        "辅助功能":"Accessibility", "录屏":"Screen recording", "已授权":"Granted", "待授权":"Needed",
        "编辑提示词":"Edit prompt", "名称":"Title", "内容":"Prompt", "取消":"Cancel", "保存":"Save",
        "来源":"Source", "我的提示词":"My prompt", "收藏":"Favorite", "删除前会备份当前提示词库，可从数据目录重新导入。":"A backup will be saved before deletion. You can restore it by importing from the data folder.",
        "切回 Codex 后自动显示。点击文字填入，点击纸飞机填入并发送。":"Appears when you return to Codex. Click text to fill; click the plane to fill and send.",
        "未绑定 Codex":"No Codex target", "复制失败。":"Copy failed.", "内置提示词已添加，原有内容与修改已保留。":"Built-ins added. Existing prompts and edits were preserved.",
        "已删除，原库已备份。":"Deleted. A library backup was saved.", "已导入；原库已备份。":"Imported. Previous library backed up.",
        "已导出提示词库。":"Prompt library exported.", "请先恢复提示词库，再添加内置提示词。":"Restore a valid library before adding built-ins.",
        "请先导入有效备份，避免覆盖无法读取的原文件。":"Import a valid backup first; the unreadable original has been preserved.",
        "完成弹窗中的辅助功能授权后，回到 Codex 点击纸飞机即可发送。":"Grant Accessibility access in the setup dialog, return to Codex, and click the paper plane.",
        "位置缓存命中：跳过完整定位。":"Position cache hit: full detection skipped.",
        "已核对并填入，尚未发送。":"Filled and verified. Not sent.",
        "已通过＋和麦克风定位并填入，内容核对通过，尚未发送。":"Located with + and microphone. Filled and verified; not sent.",
        "已通过图标定位、填入并发送，聊天回执核对通过。":"Located, filled and sent. Chat receipt verified.",
        "已操作发送，但未确认聊天回执；请检查，不会重复发送。":"Send requested, but the chat receipt is unconfirmed. Check the chat; no automatic repeat.",
        "输入框已有草稿，已保留，未发送。":"An existing draft was preserved. Nothing sent.",
        "无法核对输入框内容，未输入。":"Could not verify the input field. Nothing inserted.",
        "没有绑定 Codex 窗口。请切回当前聊天。":"No Codex window is bound. Return to the intended chat.",
        "已尝试粘贴，但视觉及复制回读均未确认完整内容；请检查输入框，不会重复粘贴或发送。":"Paste attempted, but neither visual nor copy verification confirmed the full text. Check the field; nothing will repeat automatically.",
        "点击后窗口或聊天已变化，未粘贴。":"The window or chat changed after focus. Nothing pasted.",
        "点击后无法重新截取同一窗口，未粘贴。":"Could not recheck the same window after focus. Nothing pasted.",
        "图标定位后输入框或窗口已变化，未输入。":"The field or window changed after detection. Nothing inserted.",
        "发送前未能核对完整文字，未发送。":"Full text could not be verified before sending. Nothing sent.",
        "发送前窗口已变化，未发送。":"The window changed before sending. Nothing sent.",
        "焦点快照与 AX 都无法定位；本地视觉兜底尚未获得屏幕录制权限":"Focus and accessibility detection failed; local vision needs screen recording access",
        "视觉未能确认唯一的＋和麦克风组合":"Could not confirm a unique + and microphone pair",
        "没有识别到可编辑的主聊天输入框":"No editable main chat composer found",
        "；未能确认唯一输入区域":"; no unique input region confirmed", "，未输入。":"; nothing inserted.",
        "无法确认原窗口，未输入。":"Could not confirm the original window. Nothing inserted.",
        "请到系统设置的登录项中允许 JustClick。":"Allow JustClick in System Settings → Login Items.",
        "已开启登录时启动。":"Launch at login enabled.", "已关闭登录时启动。":"Launch at login disabled.",
        "无法读取提示词库：":"Unable to read prompt library: ", "。原文件已保留，请导入有效备份恢复。":". The original was preserved; import a valid backup to recover.",
        "保存失败：":"Save failed: ", "备份失败，未删除：":"Backup failed; nothing deleted: ", "导入失败：":"Import failed: ", "导出失败：":"Export failed: ",
        "添加内置库失败：":"Unable to add built-ins: ", "提示词已添加，但升级标记未保存：":"Prompts added, but the migration marker could not be saved: "
    ]
}
