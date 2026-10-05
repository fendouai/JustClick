# JustClick MCP 实机验证插件

这是最小兼容性探针，不是已验证可用的正式提示词菜单。

## 本次完成的检查（2026-10-04）

- 桌面工具确实提供 `Codex MCP Apps` backend；当前聊天的侧栏 MCP tab 列表为空。
- 本地市场 `justclick-local` 已通过 Codex CLI 注册。
- 插件 `justclick-mcp-probe@justclick-local` 已安装，CLI 列表显示 `installed: true`、`enabled: true`。
- `npm test` 的 7 项检查通过：工具元数据、调用、HTML 资源、报告字段过滤、无效报告拒绝、未声明消息能力时禁用按钮、向活动聊天发送唯一标记的消息格式。
- 上述最后两项使用模拟宿主。没有将这些结果当成真实桌面宿主能力。
- 真正的 `ui/initialize` 返回值和 `ui/message` 响应仍待实机获取。

## 实机继续步骤

1. 重启 `/Applications/ChatGPT.app`，即当前包含 Codex 的桌面 App；回到原来的 JustClick 聊天。
2. 发消息：“打开 JustClick MCP 验证面板”。应调用 `open_justclick_probe`。
3. 如果先以内嵌卡片显示，将它展开到当前聊天侧栏。也可在聊天面板入口中查找“JustClick MCP 验证面板”。
4. 查看报告中的真实 `hostInfo` 与 `hostCapabilities`。文本消息能力没声明时按钮保持禁用。
5. 点击“发送验证消息”。它经 `ui/message` 发送 `JC_MCP_<UUID>` 测试文本；OpenAI message 扩展存在时明确设置 `target: active`、`send: true`。
6. 只有原聊天确实出现测试消息，并收到对应 `ACK JC_MCP_<UUID>`，才将消息路径记为通过。返回 JSON-RPC 响应本身不够。
7. 再点“汇报当前任务进度”，确认它继续原任务而非另开聊天。

报告保存到 `~/Library/Application Support/JustClick/mcp-probe-report.json`。仅保留宿主元信息、能力、验证阶段、测试标记和协议结果，不读取聊天历史、账号或提示词库。报告保存工具可能遵循宿主的工具审批流程；保存失败会显示提示，不应被当成发送成功证据。

## 本地开发

```sh
cd plugins/justclick-mcp-probe
npm ci --ignore-scripts
npm test
```

使用官方 MCP SDK 1.30.0。没有 OpenAI API 调用，不需要 API key，不联网发送用户内容。面板只通过宿主 bridge 通信，资源 CSP 不允许外部连接与资源。

`.mcp.json` 为此次本机验证固定了 Node 与源码绝对路径，因此不是跨机器可移植配置。CLI 将插件安装到 `~/.codex/plugins/cache/justclick-local/justclick-mcp-probe/0.1.0/`；服务器仍运行当前工作区源码。发布前需要改成可移植配置。

## 结论边界

目前是“探针构建、协议测试、安装启用已通过；真实面板与消息投递未验证”。不要据此声称 Codex 支持当前聊天按钮，也不要据此声称不支持。

官方依据：[插件 UI](https://developers.openai.com/plugins/build/chatgpt-ui)、[插件扩展](https://developers.openai.com/plugins/build/extensions)、[本地插件安装与重启](https://developers.openai.com/plugins/build/plugins)。
