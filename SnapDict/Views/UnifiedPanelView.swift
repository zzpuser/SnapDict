import SwiftUI
import SwiftData

// MARK: - PanelTab

enum PanelTab: Int, CaseIterable {
    case translation = 1
    case wordBook = 2
    case settings = 3

    var label: String {
        switch self {
        case .translation: "查词"
        case .wordBook: "单词本"
        case .settings: "设置"
        }
    }

    var shortcut: String {
        switch self {
        case .translation: "⌘1"
        case .wordBook: "⌘2"
        case .settings: "⌘3"
        }
    }

    var icon: String {
        switch self {
        case .translation: "magnifyingglass"
        case .wordBook: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

// MARK: - UnifiedPanelView

struct UnifiedPanelView: View {
    @State private var selectedTab: PanelTab = .translation
    @State private var translationResetID = UUID()
    @State private var translationHasContent = false
    @State private var pendingSelectedText: String?
    @State private var hideOnFocusLost: Bool = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hideOnFocusLost) as? Bool ?? Constants.Defaults.hideOnFocusLost

    /// 切换 Tab：先预扩窗口（避免内容被压缩闪动），再切换内容
    private func switchTab(to tab: PanelTab) {
        PanelManager.shared.preExpandIfNeeded(for: tab)
        selectedTab = tab
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab 指示器栏
            TabIndicatorBar(selectedTab: $selectedTab, onSelect: switchTab, showCloseButton: !hideOnFocusLost)

            Divider()

            // Tab 内容区，填满 NSPanel 剩余高度
            // 非激活 Tab 设置 height: 0，不参与 ZStack 布局计算
            ZStack(alignment: .top) {
                TranslationContentView(
                    resetID: translationResetID,
                    isActive: selectedTab == .translation,
                    initialQuery: $pendingSelectedText,
                    onContentChange: { hasContent in
                        translationHasContent = hasContent
                        guard selectedTab == .translation else { return }
                        if !hasContent {
                            // 无内容时，内容高度重置为 0，触发紧凑模式
                            PanelManager.shared.updateTranslationContentHeight(0)
                        }
                    },
                    onContentHeightChange: { height in
                        guard selectedTab == .translation else { return }
                        PanelManager.shared.updateTranslationContentHeight(height)
                    }
                )
                .tabContent(isActive: selectedTab == .translation)

                PanelWordBookView()
                    .tabContent(isActive: selectedTab == .wordBook)

                PanelSettingsView(isActive: selectedTab == .settings) { height in
                    guard selectedTab == .settings else { return }
                    PanelManager.shared.updateSettingsHeight(height)
                }
                .tabContent(isActive: selectedTab == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        // Escape 关闭面板
        // 查词 Tab 时，TranslationContentView 会先处理（清空内容），
        // 搜索框已空时返回 .ignored，事件冒泡到这里再关闭面板
        .onKeyPress(.escape) {
            PanelManager.shared.hidePanel()
            return .handled
        }
        .onChange(of: selectedTab) { _, newTab in
            // 内容切换后，动画调整到目标高度（preExpand 已处理扩大，这里处理缩小）
            PanelManager.shared.adjustHeight(for: newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let newValue = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hideOnFocusLost) as? Bool ?? Constants.Defaults.hideOnFocusLost
            if hideOnFocusLost != newValue {
                hideOnFocusLost = newValue
            }
        }
        .onAppear {
            // 注册显示/重置回调
            PanelManager.shared.onShow = { shouldReset, selectedText in
                #if DEBUG
                print("[PanelManager.onShow] shouldReset=\(shouldReset), selectedText=\(selectedText ?? "nil")")
                #endif
                if shouldReset {
                    selectedTab = .translation
                    translationResetID = UUID()
                    translationHasContent = false
                }
                if let text = selectedText, !text.isEmpty {
                    if selectedTab != .translation {
                        switchTab(to: .translation)
                    }
                    pendingSelectedText = text
                }
            }
            // 注册 Tab 切换回调（供 MenuBarView 等外部调用）
            PanelManager.shared.onSwitchTab = { tab in
                switchTab(to: tab)
            }
        }
    }
}

// MARK: - TabIndicatorBar

private struct TabIndicatorBar: View {
    @Binding var selectedTab: PanelTab
    var onSelect: (PanelTab) -> Void
    var showCloseButton: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.label)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.shortcut)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        selectedTab == tab
                            ? AnyShapeStyle(.fill.tertiary)
                            : AnyShapeStyle(Color.clear),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if showCloseButton {
                Button {
                    PanelManager.shared.hidePanel()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                        Text("esc")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.fill.quaternary, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - Tab Content Modifier

private extension View {
    func tabContent(isActive: Bool) -> some View {
        self
            .frame(height: isActive ? nil : 0)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
    }
}
