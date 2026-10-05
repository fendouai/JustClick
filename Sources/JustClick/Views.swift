import SwiftUI
import JustClickCore

struct PickerView: View {
    @ObservedObject var model: Model
    private let actionColumnWidth: CGFloat = 52
    private var actionHeader: some View {
    HStack(spacing: 5) {
        Text(model.t("提示词")).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
        Color.clear.frame(width: 18, height: 1).accessibilityHidden(true)
        Text(model.t("自动填入")).font(.system(size: 9, weight: .regular)).frame(width: actionColumnWidth)
        Text(model.t("自动发送")).font(.system(size: 9, weight: .regular)).frame(width: actionColumnWidth)
    }
    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
    .lineLimit(1).minimumScaleFactor(0.85)
    .padding(.vertical, 6).background(.regularMaterial)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("JustClick").font(.headline)
                    Text(model.t("个人提示词库")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.edit() } label: { Image(systemName: "plus") }.help(model.t("新增提示词")).accessibilityLabel(model.t("新增提示词"))
                Menu {
                    Toggle(model.t("随 Codex 自动显示"), isOn: $model.autoShow)
                    Button(model.loginEnabled ? model.t("关闭登录时启动") : model.t("开启登录时启动")) { model.toggleLogin() }
                    Divider()
                    Button(model.t("开启辅助功能权限…")) { model.delivery.requestAccess() }
                    Button(model.t("导入 JSON…"), action: model.importLibrary)
                    Button(model.t("导出 JSON…"), action: model.exportLibrary)
                    Button(model.t("添加/恢复内置提示词")) { model.installBuiltins() }
                    Button(model.t("从 Codex 历史更新常用提示词…")) { model.openDiscovery() }
                    Button(model.t("恢复自适应大小")) { model.resetWindowSize?() }
                    Button(model.t("打开数据目录")) { NSWorkspace.shared.open(model.file.url.deletingLastPathComponent()) }
                    Divider()
                    Button(model.t("收起侧栏")) { model.hide?() }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
            }.padding(14)
            Picker("",selection:$model.page) {
                Text(model.t("提示词")).tag(Model.Page.library)
                Text(model.t("发现常用")).tag(Model.Page.discovery)
            }.labelsHidden().pickerStyle(.segmented).padding(.horizontal,14).padding(.bottom,10)
            HStack {
                Picker(model.t("语言"), selection: $model.language) {
                    Text("中文").tag(PromptLanguage.zh)
                    Text("English").tag(PromptLanguage.en)
                }.labelsHidden().pickerStyle(.segmented).frame(width:130)
                Spacer()
                if model.page == .library {
                Picker("", selection:$model.frequentOnly) {
                    Text(model.t("常用优先")).tag(true)
                    Text(model.t("全部")).tag(false)
                }.labelsHidden().pickerStyle(.segmented)
                }
            }.padding(.horizontal,14).padding(.bottom,8)
            if model.page == .discovery {
                HistoryDiscoveryView(model:model)
            } else {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.t("搜索提示词"), text: $model.query).textFieldStyle(.plain)
                    .onSubmit { if let prompt = model.current { model.use(prompt) } }
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14)
            HStack {
                Picker(model.t("分组"), selection: $model.category) {
                    Text(model.t("全部")).tag(String?.none)
                    ForEach(model.categories, id: \.self) { Text($0).tag(Optional($0)) }
                }.labelsHidden().frame(width: 130)
                Spacer()
                Text(model.language == .zh ? "\(model.results.count) / \(model.languageCount) 条" : "\(model.results.count) / \(model.languageCount) prompts").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                    Section {
                    ForEach(model.results) { prompt in
                        HStack(spacing: 5) {
                            Button {
                                model.selected = prompt.id
                                model.use(prompt, send: false)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: prompt.pinned ? "pin.fill" : "text.alignleft").foregroundStyle(.secondary).frame(width: 16)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(prompt.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                        Text(prompt.body).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(model.t("仅填入") + ": \(prompt.title)")
                            Menu {
                                Button(model.t("编辑")) { model.edit(prompt) }
                                Button(model.t(prompt.pinned ? "取消置顶" : "置顶")) { model.pin(prompt) }
                                Button(model.t("复制为新提示词")) { model.duplicate(prompt) }
                                Divider()
                                Button(model.t("删除"),role:.destructive) { model.remove(prompt) }
                            } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:18).help(model.t("编辑"))
                            Button { model.selected = prompt.id; model.use(prompt, send: false) } label: {
                                Image(systemName: "character.cursor.ibeam").frame(width: actionColumnWidth, height: 34).contentShape(Rectangle())
                            }
                                .buttonStyle(.borderless).help(model.t("仅填入，不发送") + ": \(prompt.title)")
                                .accessibilityLabel(model.t("自动填入") + ": \(prompt.title)")
                                
                            Button { model.selected = prompt.id; model.use(prompt, send: true) } label: {
                                Image(systemName: "paperplane.fill").frame(width: actionColumnWidth, height: 34).contentShape(Rectangle())
                            }
                                .buttonStyle(.borderless).help(model.t("填入并发送") + ": \(prompt.title)")
                                .accessibilityLabel(model.t("自动发送") + ": \(prompt.title)")
                                
                        }.background(model.current?.id == prompt.id ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                            .contextMenu {
                                Button(model.t("填入并发送")) { model.use(prompt, send: true) }
                                Button(model.t("仅填入")) { model.use(prompt, send: false) }
                                Button(model.t("复制")) { model.use(prompt, copyOnly: true) }
                                Button(model.t("编辑")) { model.edit(prompt) }
                                Button(prompt.pinned ? model.t("取消置顶") : model.t("置顶")) { model.pin(prompt) }
                                Button(model.t("上移")) { model.reorder(prompt, -1) }
                                Button(model.t("下移")) { model.reorder(prompt, 1) }
                                Button(model.t("删除并备份")) { model.remove(prompt) }
                            }
                    }
                    if model.results.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray").font(.title)
                            Text(model.t("没有匹配的提示词"))
                            Button(model.t("新增提示词")) { model.edit() }
                        }.foregroundStyle(.secondary).padding(25)
                    }
                    } header: { actionHeader }
                }.padding(10)
            }
            Divider()
            if let prompt = model.current {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.t("预览") + " · \(prompt.title)").font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Button(model.t("编辑")) { model.edit(prompt) }.controlSize(.small)
                        Button { model.remove(prompt) } label: { Image(systemName:"trash") }.controlSize(.small).help(model.t("删除")).accessibilityLabel(model.t("删除"))
                        Button(model.t("复制")) { model.use(prompt, copyOnly: true) }.controlSize(.small)
                    }
                    if let source = prompt.source {
                        HStack {
                            Text(model.t("来源") + ": " + source).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
                            if let urlString = prompt.sourceURL, let url = URL(string:urlString), url.scheme == "https" { Link(destination:url) { Image(systemName:"arrow.up.right.square") }.font(.caption) }
                        }
                    }
                    if let count = prompt.historyCount, let threads = prompt.historyThreadCount {
                        Text(model.language == .zh ? "历史使用 \(count) 次 · 涉及 \(threads) 个会话" : "Used \(count) times across \(threads) chats")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    ScrollView { Text(prompt.body).font(.caption).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
                    HStack {
                        Button { model.use(prompt, send: false) } label: { Label(model.t("自动填入"), systemImage: "character.cursor.ibeam") }.controlSize(.small).help(model.t("仅填入，不发送"))
                        Spacer()
                        Button { model.use(prompt, send: true) } label: { Label(model.t("自动发送"), systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).controlSize(.small).help(model.t("填入并发送"))
                    }
                }.padding(12)
                Divider()
            }
            }
            VStack(alignment: .leading, spacing: 6) {
                if model.busy { ProgressView().controlSize(.small) }
                if model.historyBusy { ProgressView(model.t("正在整理历史…")).controlSize(.small) }
                Text(model.t(model.message)).font(.caption).lineLimit(5).foregroundStyle(.secondary).textSelection(.enabled)
                if !model.screenPermissionGranted {
                    Button(model.t("视觉定位需授权：打开指引…")) { PermissionGuide.showScreenCapture() }.controlSize(.small)
                }
                if model.retryLocked { Text(model.t("上次结果未确认。可继续选择、编辑；再次点击操作按钮会重新尝试。")).font(.caption2).foregroundStyle(.secondary) }
                if !model.permissionGranted { Button(model.t("发送需授权：开启辅助功能…")) { model.delivery.requestAccess() }.controlSize(.small) }
                HStack {
                    Text(model.t(model.targetName))
                    Spacer()
                    Text(model.t("辅助功能") + ": " + model.t(model.permissionGranted ? "已授权" : "待授权") + " · " + model.t("录屏") + ": " + model.t(model.screenPermissionGranted ? "已授权" : "待授权"))
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, minHeight: 480)
        .background(.regularMaterial)
        .onChange(of: model.query) { _, _ in model.selected = model.results.first?.id }
        .onChange(of: model.category) { _, _ in model.selected = model.results.first?.id }
        .onChange(of:model.page) { _, page in if page == .discovery { model.openDiscovery() } }
        .sheet(isPresented: $model.showEditor) { if let draft = model.editing { EditorView(model: model, draft: draft) } }
    }
}

struct EditorView: View {
    @ObservedObject var model: Model
    @State var draft: Prompt
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t("编辑提示词")).font(.title2.weight(.semibold))
            TextField(model.t("名称"), text: $draft.title)
            TextField(model.t("分组"), text: $draft.category)
            Picker(model.t("语言"),selection:Binding(get:{ draft.language ?? draft.effectiveLanguage },set:{ draft.language = $0 })) {
                Text("中文").tag(PromptLanguage.zh)
                Text("English").tag(PromptLanguage.en)
            }.pickerStyle(.segmented)
            Text(model.t("内容")).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft.body).font(.system(size: 14)).frame(height: 220)
                .padding(5).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Toggle(model.t("置顶"), isOn: $draft.pinned)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(model.t("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.t("保存")) {
                    draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    if draft.category.isEmpty { draft.category = model.t("常用") }
                    if model.save(draft) { dismiss() } else { error = model.message }
                }.keyboardShortcut(.defaultAction).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 500)
    }
}


struct HistoryDiscoveryView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(model.t("读取我的历史对话，发现我的常用提示词")).font(.headline).fixedSize(horizontal:false,vertical:true)
            Text(model.t("先预览候选，再勾选需要的提示词加入。已有内容不会自动改变。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { model.discoverHistory() } label: {
                    Label(model.t(model.historyBusy ? "正在整理历史…" : "读取历史"),systemImage:"arrow.clockwise")
                }.disabled(model.historyBusy)
                Spacer()
                Button(model.t("全选可加入")) { model.selectedHistoryKeys = Set(model.historyCandidates.filter { !model.historyIsAdded($0) }.map(\.key)) }
                    .controlSize(.small)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    ForEach(model.historyCandidates,id:\.key) { candidate in
                        HStack(alignment:.top,spacing:10) {
                            if model.historyIsAdded(candidate) {
                                Image(systemName:"checkmark.circle.fill").foregroundStyle(.secondary).frame(width:20)
                            } else {
                                Toggle("",isOn:Binding(get:{model.selectedHistoryKeys.contains(candidate.key)},set:{ selected in
                                    if selected { model.selectedHistoryKeys.insert(candidate.key) } else { model.selectedHistoryKeys.remove(candidate.key) }
                                })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel(candidate.title)
                            }
                            VStack(alignment:.leading,spacing:6) {
                                HStack {
                                    Text(candidate.title).font(.headline)
                                    Spacer()
                                    if model.historyIsAdded(candidate) { Text(model.t("已加入")).font(.caption).foregroundStyle(.secondary) }
                                }
                                Text(candidate.body).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                                Text(model.language == .zh ? "历史使用 \(candidate.count) 次 · \(candidate.threadCount) 个会话" : "\(candidate.count) uses · \(candidate.threadCount) chats")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                            .background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:8))
                    }
                    if model.historyCandidates.isEmpty {
                        Text(model.t("暂无此语言的候选，点击读取历史开始发现。"))
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical,24)
                    }
                }
            }
            HStack {
                Text(model.language == .zh ? "已选 \(model.selectedHistoryKeys.count) 条" : "\(model.selectedHistoryKeys.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.t("加入所选")) { model.addSelectedHistory() }
                    .buttonStyle(.borderedProminent).disabled(model.selectedHistoryKeys.isEmpty)
            }
        }.padding(14).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
