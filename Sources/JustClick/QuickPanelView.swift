import SwiftUI
import JustClickCore

/// The working surface intentionally omits settings and the permanent editor preview.
struct QuickPanelView: View {
    @ObservedObject var model: Model
    private func label(_ zh: String, _ en: String) -> String { model.language == .zh ? zh : en }
    private var canSend: Bool { model.targetName != "未绑定 Codex" && model.permissionGranted }

    var body: some View {
        Group {
            if model.collapsed {
                AnchorButton(title: label("展开快捷菜单（可拖动）", "Open quick menu (drag to move)"),
                             open: { model.collapsed = false }, moved: { model.anchorMoved?() })
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "bolt.circle.fill").foregroundStyle(.tint)
                        Text("JustClick").font(.headline)
                        Spacer()
                        Button { model.keepExpanded.toggle() } label: {
                            Image(systemName: model.keepExpanded ? "pin.fill" : "pin")
                        }.help(label("保持展开", "Keep expanded"))
                            .accessibilityLabel(label("保持展开", "Keep expanded"))
                            .accessibilityValue(model.keepExpanded ? "On" : "Off")
                        Button { model.closeQuick?() } label: { Image(systemName: "chevron.right") }
                            .help(label("收起菜单", "Close menu"))
                            .accessibilityLabel(label("收起菜单", "Close menu"))
                        Menu {
                            Toggle(label("仅菜单栏模式", "Menu bar only"), isOn: $model.menuBarOnly)
                            Button(label("刷新常用排序", "Refresh frequent prompts")) { model.refreshQuickOrder() }
                            Button(label("管理提示词与设置…", "Library and settings…")) { model.openManager?(.library) }
                            Button(model.t("收起侧栏")) { model.hide?() }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18)
                    }.buttonStyle(.borderless).padding(10)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(model.t("搜索提示词"), text: $model.quickQuery)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                if let prompt = model.quickResults.first(where: { $0.id == model.quickSelected }) ?? model.quickResults.first {
                                    model.use(prompt)
                                }
                            }
                        if !model.quickQuery.isEmpty {
                            Button { model.quickQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        }
                    }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
                    HStack {
                        Text(label("常用指令", "Your shortcuts"))
                        Spacer()
                        Text(label("点击填入", "Click to fill"))
                        Text(model.t("自动发送")).lineLimit(1).minimumScaleFactor(0.8).frame(width: 44)
                    }.font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 5)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.visibleQuickResults) { prompt in
                                HStack(spacing: 4) {
                                    Button { model.quickSelected = prompt.id; model.use(prompt) } label: {
                                        HStack(spacing: 7) {
                                            if prompt.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                                            Text(prompt.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                            Spacer(minLength: 0)
                                        }.padding(.leading, 10).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).help(prompt.body)
                                    Button { model.quickSelected = prompt.id; model.use(prompt, send: true) } label: {
                                        Image(systemName: "paperplane.fill").frame(width: 32, height: 32)
                                    }.accessibilityLabel(model.t("自动发送") + ": " + prompt.title)
                                        .help(canSend ? model.t("填入并发送") : label("请先切回目标 Codex 窗口并授权", "Select your Codex window and grant access first"))
                                        .disabled(!canSend)
                                }.buttonStyle(.borderless)
                                    .background(model.quickSelected == prompt.id ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                                    .contextMenu {
                                        Button(model.t("复制")) { model.use(prompt, copyOnly: true) }
                                        Button(model.t("编辑")) { model.openManager?(.library); model.edit(prompt) }
                                        Button(model.t(prompt.pinned ? "取消置顶" : "置顶")) { model.pin(prompt); model.refreshQuickOrder() }
                                    }
                            }
                            if model.quickResults.isEmpty {
                                Text(model.t("没有匹配的提示词")).foregroundStyle(.secondary).padding(24)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    Divider()
                    HStack {
                        Button(label("我的提示词", "My prompts")) { model.openManager?(.library) }
                        Spacer()
                        Button(model.t("发现常用")) { model.openManager?(.discovery) }
                    }.buttonStyle(.borderless).font(.caption).padding(12)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Circle().fill(canSend ? Color.green : Color.secondary).frame(width: 5, height: 5)
                            Text(model.t(model.targetName)).lineLimit(1)
                            Spacer()
                            if model.busy { ProgressView().controlSize(.mini) }
                        }
                        if model.deliveryFeedback { Text(model.t(model.message)).lineLimit(2).help(model.t(model.message)) }
                        if !model.permissionGranted {
                            Button(label("开启辅助功能权限…", "Enable Accessibility…")) { model.delivery.requestAccess() }.buttonStyle(.borderless)
                        }
                    }.font(.caption2).foregroundStyle(.secondary).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3))
                }
            }
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: model.collapsed ? 14 : 12))
            .onChange(of: model.quickQuery) { _, _ in model.quickSelected = model.quickResults.first?.id }
    }
}

private struct AnchorButton: NSViewRepresentable {
    let title: String
    let open: () -> Void
    let moved: () -> Void
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        view.open = open; view.moved = moved
        view.setAccessibilityLabel(title); view.toolTip = title
    }
}
private final class AnchorView: NSView {
    var open: (() -> Void)?
    var moved: (() -> Void)?
    private var start: NSPoint = .zero
    private var origin: NSPoint = .zero
    private var dragged = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool { open?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.draw(in: NSRect(x: 8, y: 6, width: 12, height: 16))
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        start = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation; origin = window?.frame.origin ?? .zero; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        dragged = true
        window?.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
    }
    override func mouseUp(with event: NSEvent) { if dragged { moved?() } else { open?() } }
}
