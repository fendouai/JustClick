# 方案评估与类似项目

> 本文是 2026-10-03 的早期记录。2026-10-04 新增的自动显示、一键填入并发送，以及原生 MCP/CDP 双路线评估，以 [README 总览](../README.md)为准。

调研日期：2026-10-03（Asia/Shanghai）。GitHub 搜索使用 agent-reach 的 gh 后端，结论依据实际读取的项目 README 与官方文档。没有下载安装或运行第三方项目；其功能描述属于作者声明，未验证其在本机 Codex 中的表现。

## 需求与选择

目标：自定义高频提示词、随时打开菜单、快速用于当前聊天，优先内置，无法内置时尽量接近原生体验。

当前推荐交付是 JustClick 的原生伴随菜单。它能通过菜单栏和快捷键长期访问，提示词可编辑并保存在本机，不依赖聊天回复中临时出现的按钮。选择提示词后优先填入当前输入框，复制作为可用的后备路径。

如果只想采用现成产品，优先评估 PromptPanel：其功能与需求最接近，支持更多项目管理、搜索、导入导出和快捷键配置。JustClick 的价值是更小的专用实现和可直接修改的源码，不宣称功能、成熟度或兼容性优于这些项目。

## 宿主证据

本机实际 App 路径为 `/Applications/ChatGPT.app`，Bundle ID 为 `com.openai.codex`，版本 `26.930.31730`。不能单凭安装目录名称断定它与文档中的 ChatGPT 插件界面完全相同。

官方文档提供以下证据：

1. [MCP server and UI quickstart](https://developers.openai.com/plugins/build/app-quickstart)：MCP 工具用于 ChatGPT 与 Codex，教程的可选 UI 在 ChatGPT iframe 中渲染。
2. [Add UI to your MCP server](https://developers.openai.com/plugins/build/chatgpt-ui)：介绍 MCP Apps UI、host bridge 和兼容宿主，并要求工具在没有 UI 时仍可工作。
3. [Plugin Extensions](https://developers.openai.com/plugins/build/extensions)：提供 ChatGPT 的 sidebar、composer、文件查看器扩展，composer mentions 描述为 ChatGPT desktop app 专属。
4. [Custom Prompts](https://learn.chatgpt.com/docs/custom-prompts)：自定义提示词已弃用，推荐 skills；旧功能明确描述为 CLI 和 IDE 的斜杠命令。

这些文档不足以确认本机 Codex 界面支持自定义、常驻的提示词菜单，也不足以证明它一定不支持。电脑操作工具明确拒绝检查 `com.openai.codex` 宿主，未绕过该限制。因此插件内置路线保持“待实机验证”，没有据此承诺或交付一个未经验证的 MCP 菜单。

聊天里的后续指令按钮适合依附某条回复的临时操作，无法单独满足常驻菜单与完整提示词管理需求。

## 类似项目

| 项目 | 已读取的项目功能 | 对当前需求的适合度 |
| --- | --- | --- |
| [qilaidev/PromptPanel](https://github.com/qilaidev/PromptPanel) | 原生 macOS；全局快捷键；搜索；项目隔离；置顶；SQLite；JSON/Markdown 导入导出；复制与辅助功能粘贴；MIT | 最接近。现成采用首选候选，但仍需在本机验证粘贴和权限 |
| [nabobery/Promptly](https://github.com/nabobery/Promptly) | macOS 菜单栏；提示词/片段；嵌套文件夹；收藏；搜索；快捷键；可选自动粘贴；MIT | 也很接近。README 的 v0.1.0 二进制支持 arm64、macOS 14+，ad-hoc 签名，未公证 |
| [espanso/espanso](https://github.com/espanso/espanso) | 跨平台文本展开；搜索栏；关键词展开；App 专属配置；GPL-3.0 | 适合愿意记短缩写的人，菜单体验需评估 |
| [Calrton/codex-prompt-manager](https://github.com/Calrton/codex-prompt-manager) | Windows GUI；管理 Codex 本地 Markdown 指令文件；备份恢复；重启 Codex | 不是当前聊天的提示词菜单，匹配度低 |

搜索词包括 `codex prompt manager`、`macos prompt snippets`、`codex desktop prompt`、`prompt menu macOS` 和 `codex snippets`。没有搜索到可以确认直接给本机 Codex 内置聊天菜单的成熟项目；这不是不存在此类项目的证明。

## 技术取舍

- SwiftUI 呈现搜索、分组、预览与编辑；AppKit 提供菜单栏和浮动 NSPanel。
- Carbon 注册全局快捷键，无需键盘监听权限；自动填入单独需要辅助功能权限。
- 首先捕获用户已经聚焦的输入控件，避免通过固定屏幕坐标点击输入框。
- 填入前确认 App、窗口、焦点和可编辑状态，AX 写选区优先，Command + V 为后备。
- 不自动发送：宿主没有可用、已验证的当前聊天发送协议，盲按 Return 不能证明投递正确。
- 不修改宿主文件，不读取会话数据库，不使用隐藏接口。数据采用可检查的 JSON，原子写入，破损库保护，导入与删除备份。

## 下一阶段的判定条件

解锁本机后可完成 JustClick 的真实界面检查；自动填入还需要用户对 JustClick 开启辅助功能权限，并在宿主输入框中实测。若后续获得可验证的宿主插件入口，只有通过“菜单可打开、点击能填入/发消息、明确属于当前聊天”三项检查后才切换到内置路线。
