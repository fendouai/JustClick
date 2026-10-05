# 从 Codex 本地历史生成个人常用提示词

调研日期：2026-10-05。

0.8.0 行为更新：候选改在独立标签页中预览，读取与加入分离；勾选并点击“加入所选”才修改库。下文 0.7.0 自动加入描述属于历史实现，当前以此行为为准。结论：可行。推荐「官方 App Server 读取存量 + 可选 UserPromptSubmit Hook 接收增量 + JustClick 自有本地索引」，JSONL 作为受限兼容方案。

更新：0.7.0 已按用户明确授权实现并测试一次性本地历史读取与常用提示词导入。更多菜单可手动刷新；未安装持续采集 Hook。下文保留原方案设计，当前实现以本节为准。

当前实现使用受限 JSON-RPC 客户端，只允许 initialize、thread/list、thread/read、thread/turns/list、thread/items/list。通过官方 App Server 列出已索引的本地非子代理会话，分页读取后仅提取 userMessage 文本；不启动、恢复或推进模型任务。首次读取106个会话、2316条用户消息，过滤425条明显不适合内容（含自动上下文、过长内容、链接/路径与敏感模式等），再按跨会话重复筛选和小范围明确同义短句整理，最终选择5类通用项。特定项目的较长段落不自动导入。过滤是规则式的，不保证能识别所有自动生成消息或所有敏感内容。

个人报告存于用户 Application Support/JustClick/history-candidates.json，文件权限0600；保存候选和去重后的会话哈希，不复制完整会话。去重以根session、turn、item和内容哈希组合实现。归并时使用真实会话集合求并集，不能简单相加会话数。最近使用的排序辅助值来自会话更新时间，不是假定精确提示词提交时间。库内新增 historyKey/count/threadCount/rank，保留 JustClick 点击次数为独立统计。首屏置顶组中优先显示历史条目，原有条目与置顶标志保留。

覆盖边界：本次为 API 可列出的106个会话，并不声称涵盖所有未索引文件、其他设备或 ChatGPT Work 会话。每次最多500个会话，处理时间和页数有上限；报告记录读取失败与截断，界面提示部分覆盖。当前采用小型JSON报告而非完整SQLite索引，重复刷新仍会重新读取该范围，尚未实现增量Hook/游标缓存。

本地验证包括分页、子代理排除、fork重复、自动上下文过滤、敏感模式过滤、禁止写方法、分支/否定语义不混合，以及Swift导入的重复更新、首屏排序、原库与编辑/置顶保留。

## 证据与边界

- 官方排障文档列出 `$CODEX_HOME/sessions` 与 `archived_sessions`。本机确认 `~/.codex/sessions`、`archived_sessions`、`session_index.jsonl` 存在，`history.jsonl` 不存在；只检查了路径元数据。[官方排障文档](https://learn.chatgpt.com/docs/reference/troubleshooting)
- App Server 提供 `thread/list`、`thread/read`；`thread/turns/list` / `thread/items/list` 可分页读取，但属于实验接口。读取存量无需调用 resume/start。[官方 App Server](https://learn.chatgpt.com/docs/app-server)
- `UserPromptSubmit` 提供 prompt、session_id、turn_id 等字段；后台 command hook 可异步执行。Hook 的 transcript_path 格式不稳定，不能当长期接口；Stop Hook 还可能生成新的用户提示词。[官方 Hooks](https://learn.chatgpt.com/docs/hooks)
- 配置中的 `history.persistence` 可关闭 history.jsonl，`history.max_bytes` 可裁剪旧内容。因此不能把该单一文件当作完整桌面聊天历史。[官方配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)

本机 CLI 为 0.154.0，已通过它生成 JSON Schema，确认以下字段和输入结构存在。没有因此宣布桌面宿主对接已经实测成功，也没有启动模型 turn。

## 方案比较

| 方案 | 优势 | 局限 | 建议 |
|---|---|---|---|
| App Server 历史读取 | 官方协议、结构化消息、过滤与分页 | 需要匹配版本的 CLI；分页接口实验性；索引覆盖度须核对 | 主要适配器 |
| UserPromptSubmit Hook | 增量事件，不必反复扫描历史 | 不能补旧历史；需用户启用；可能包含自动生成/子代理来源 | 可选增强 |
| sessions JSONL 解析 | 无后台服务，能处理已有本地导出或目录快照 | 格式可能变化、尾行未写完、fork 重复、压缩等 | 版本受限的 fallback |
| history.jsonl | 简单 | 本机没有，且可关闭/截断；不保证覆盖桌面记录 | 不作主方案 |
| 直接读 state SQLite | 元数据查询快 | 内部表结构、WAL、版本与写入耦合 | 不直接依赖 |
| Computer History/记忆 | 适合跨应用活动或总结记忆 | 不是原始提示词提交统计，范围过大 | 不用于此需求 |
| 抓聊天界面/截图 | 可以看当前可见内容 | 不完整、效率低、与现有输入控制耦合 | 不用于挖掘历史 |

App Server 是业务只读接口方案，并不承诺其进程在文件系统层面绝对零写入。若严格要求零改动，可让用户选择导出的目录快照，仅解析快照。

## 推荐实现

JustClick 增加「从 Codex 历史发现常用提示词」入口。首次选择范围（例如最近 90 天、指定项目），本地生成候选并预览。用户启用后增量更新推荐，已固定和手工编辑的条目始终优先，不自动覆盖。

模块：`HistoryProvider` → `UserPromptExtractor` → `Normalizer` → `LocalPromptIndex` → `SuggestionRanker` → 「为你推荐」。先实现完全相同/格式差异的重复统计，无需云模型、向量服务或下载大模型；语义合并以后作为可选建议，避免把带否定词的指令合成同一条。

### 存量读取

Swift `Process` 启动兼容的 `codex app-server --stdio`，通过 stdin/stdout JSON-RPC 通信，不开放 TCP 端口。使用明确选定的 CODEX_HOME，优先与桌面版本匹配的运行时。应用只实现历史读取方法白名单，不调用 turn/start、turn/steer、thread/resume 或写入方法。

初始化后先读元数据，按更新时间分页；再按预算分页加载指定线程的用户消息。下面的结构已对照本机生成的 Schema 核对，但未向真实私人历史发出请求：

```json
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"justclick_history","version":"0.6.0"},"capabilities":{"experimentalApi":true}}}
{"method":"initialized","params":{}}
{"id":2,"method":"thread/list","params":{"limit":50,"sortKey":"updated_at","sortDirection":"desc","sourceKinds":["cli","vscode","appServer"],"archived":false,"useStateDbOnly":true}}
{"id":3,"method":"thread/turns/list","params":{"threadId":"<selected-thread-id>","limit":50,"itemsView":"full","sortDirection":"desc"}}
```

注意实现中的几个细节：

- 显式选择来源并检查实际 source/originator；默认来源过滤可能漏掉 appServer 来源。unknown 来源进入待确认范围，不把所有 exec/subagent 记录混入个人偏好。
- `useStateDbOnly:true` 避免列表方法扫描 JSONL 修复元数据，但可能漏掉尚未入索引的历史。必须展示覆盖范围，不能把“索引为空”说成“没有聊天”。
- 归档与未归档分别分页。新消息用游标和更新时间增量同步；删除、回滚、归档要使索引相应失效。
- 本机 Schema 对 includeTurns 的说明已经建议分页线程使用 turns/items 分页；旧版兼容时才按能力选择 thread/read(includeTurns:true)，不盲目读取整个超长线程。
- API/存储不支持当前版本时明确降级或显示不支持，不把仅取到的第一页当完整历史。

### 增量事件

推荐可选安装一个短小、异步的 UserPromptSubmit command hook，将事件追加到 JustClick 自有队列文件或本地 IPC。处理器只接收输入、快速落队列、退出 0；不输出 additionalContext、decision、systemMessage，不改变对话，不调用模型。耗时统计由 JustClick 后台队列执行。

这需要单独验证本机桌面版本、Hook 信任流程及字段。初期可仅用 App Server 定时/打开面板时增量刷新，避免把 Hook 安装作为基本功能的前置条件。未启用时不修改用户 hooks.json 或 config.toml。

### 只统计真正有用的用户输入

本机 ThreadItem Schema 区分 `userMessage` 与 `hookPrompt`、agentMessage、reasoning、工具输出等。只提取 userMessage.content 中的 text；不跟随图片、附件路径或外链读取文件。

仍需额外过滤，因为 userMessage 不等于“人手工输入”：

1. 排除子代理、Hook、目标自动续跑及系统上下文包装；来源无法确定的条目不自动晋升为默认。
2. 排除一次性大段粘贴、报错日志、授权回复，以及“好/可以”等缺乏独立用途的回应。短指令如“继续完成”可保留。
3. 排除或标记明显密钥、令牌和其他敏感内容；不能承诺正则规则能发现所有秘密，因此首次候选仍需预览。
4. Unicode、空白、换行规范化只用于去重，原文保留；不删除否定、数值、文件路径等可能改变语义的内容。
5. 按消息/turn 身份去重，处理重读、Hook+API 双重采集及 fork 继承，避免同一提交计数多次。
6. 优先“多个会话、多个日期反复出现”，而不是一个任务中连续重试十次。按语言分别排序。

建议初始评分：跨会话频次、出现天数、最近使用和独立可复用性；人为置顶最高。JustClick 自身操作次数与 Codex 历史提交次数分别保存，避免一次点击又被历史采集重复相加。

### 本地存储与产品体验

建议在 `~/Library/Application Support/JustClick/` 下建立专用 SQLite 索引，仅存候选用户文本、规范化哈希、来源ID、时间、项目标识和统计量；不复制助手输出与整个 transcript。保留删除索引、排除项目、暂停更新及“不要再推荐”能力。

首屏优先级：用户置顶 → 已确认的个人高频 → 当前语言内置常用。新建议显示使用次数、涉及会话数、最近使用日期和原文来源，可一键加入、编辑成模板或忽略。选中中文只显示中文候选，英文同理；原文不自动翻译覆盖。

## 外部项目参考

- [recall-cli](https://github.com/ramsrib/recall-cli)：JSONL 到本地 SQLite、增量索引、关键词/语义检索。可参考文件变更处理，但语义索引需要 Ollama，summary 会调用 Codex，远程 OLLAMA_HOST 也会改变数据边界，不应照搬成“全部离线”。
- [session-recall](https://github.com/AbsoluteMode/session-recall)：本地 SQLite/ONNX、多来源、项目/时间范围和 MCP 查询。适合参考适配器与来源追踪，范围远大于常用提示词统计，JustClick 初版不需要整套记忆/向量检索系统。

以上仅检查了项目 README/元数据，没有安装或运行这些第三方程序，也没有把私人聊天交给它们。

## 验证标准与交付边界

要上线此功能，需在隔离 fixture 验证分页、断点续读、归档、重复消息、fork、自动消息过滤、双语排名、敏感候选过滤和原库不被覆盖，再在用户选择的少量真实会话上核对覆盖率。日志只记录数量、状态和不可逆ID，不回显提示词原文。首次推荐需要可解释的来源和计数。

原调研阶段只验证了文档、协议Schema和目录存在。0.7.0新增实际API读取和手动导入验证，覆盖范围及限制见文首；Hook实际投递与所有磁盘历史的完整覆盖仍未验证。推荐顺序为 App Server 存量与增量读取 → 本地候选预览 → 可选 Hook；不再用截图来分析历史。
