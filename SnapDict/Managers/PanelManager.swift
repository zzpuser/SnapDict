import AppKit
import SwiftUI
import SwiftData

@MainActor
final class PanelManager: NSObject, NSWindowDelegate {
    static let shared = PanelManager()

    private var panel: TranslationPanel?
    private var panelWidth: CGFloat = 420
    private let wordPanelWidth: CGFloat = 420
    private let sentencePanelWidth: CGFloat = 840

    // 查词 Tab 高度
    private let compactHeight: CGFloat = 98      // 紧凑：仅搜索框 (tabBar + searchArea)
    private let searchAreaHeight: CGFloat = 60   // 搜索栏区域高度（含 padding）

    // 其他 Tab 默认高度
    private let defaultWordBookHeight: CGFloat = 520
    private let defaultSettingsHeight: CGFloat = 498  // tabBarHeight + 460

    /// Tab 栏高度（指示器 + Divider）
    private let tabBarHeight: CGFloat = 38
    /// 设置页面内容高度（由 View 动态上报，初始值保证首次渲染有足够空间）
    private var settingsContentHeight: CGFloat = 460
    private var settingsHeight: CGFloat { tabBarHeight + settingsContentHeight }

    // 新增状态
    private var currentTab: PanelTab = .translation
    private var translationContentHeight: CGFloat = 0
    private var isResizingProgrammatically = false

    // 用户手动调整的高度（从 UserDefaults 恢复）
    private var userWordBookHeight: CGFloat?
    private var userSettingsHeight: CGFloat?

    private var modelContainer: ModelContainer?
    private weak var hostingView: NSView?

    /// 每次显示面板时调用，用于通知 View 重置状态
    var onShow: ((_ shouldReset: Bool, _ selectedText: String?) -> Void)?

    /// 切换 Tab 的回调
    var onSwitchTab: ((PanelTab) -> Void)?

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    private var lastHideDate: Date?
    private var localEventMonitor: Any?

    private var shouldReset: Bool {
        guard let lastHide = lastHideDate else { return true }
        return Date().timeIntervalSince(lastHide) >= 60
    }

    private override init() {
        super.init()
        // 从 UserDefaults 恢复用户手动调整的高度
        userWordBookHeight = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.panelHeightWordBook) as? CGFloat
        userSettingsHeight = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.panelHeightSettings) as? CGFloat
        setupLocalEventMonitor()
    }

    private func setupLocalEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // 只在面板可见时处理
            guard let panel = self.panel, panel.isVisible else { return event }
            // 必须是 Cmd 修饰键 + 数字键 1/2/3
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control) else { return event }

            switch event.charactersIgnoringModifiers {
            case "1":
                Task { @MainActor in self.onSwitchTab?(.translation) }
                return nil  // 消费事件，不传递
            case "2":
                Task { @MainActor in self.onSwitchTab?(.wordBook) }
                return nil
            case "3":
                Task { @MainActor in self.onSwitchTab?(.settings) }
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - 显示/隐藏面板

    func showPanel(modelContainer: ModelContainer, selectedText: String? = nil) {
        self.modelContainer = modelContainer

        if let panel, panel.isVisible {
            if let selectedText, !selectedText.isEmpty {
                // 面板已可见且有新文本：直接传递新查询，不走 toggle 逻辑
                panel.makeKeyAndOrderFront(nil)
                onShow?(false, selectedText)
                return
            }
            // 面板已可见且无新文本：走 toggle 逻辑
            let hideOnFocus = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hideOnFocusLost) as? Bool
                ?? Constants.Defaults.hideOnFocusLost
            if !hideOnFocus && !panel.isKeyWindow {
                panel.makeKeyAndOrderFront(nil)
                return
            }
            panel.orderOut(nil)
            return
        }

        if panel == nil {
            createPanel(modelContainer: modelContainer)
        }

        let reset = shouldReset
        if reset { centerPanel() }
        animateShow()
        // 延迟一个 runloop，确保窗口成为 key window 后再通知 View 设置焦点
        DispatchQueue.main.async {
            self.onShow?(reset, selectedText)
        }
    }

    func hidePanel() {
        animateHide {
            self.lastHideDate = Date()
        }
    }

    // MARK: - Tab 切换

    /// 显示面板并切换到指定 Tab，不触发 toggle 关闭逻辑
    func showTab(_ tab: PanelTab, modelContainer container: ModelContainer) {
        self.modelContainer = container

        if panel == nil {
            createPanel(modelContainer: container)
        }

        if let panel, panel.isVisible {
            // 面板已可见，直接切换 Tab
            onSwitchTab?(tab)
        } else {
            // 面板不可见，先显示再切 Tab
            if shouldReset { centerPanel() }
            animateShow()
            DispatchQueue.main.async {
                self.onShow?(false, nil)  // 切换到特定 Tab，不重置内容
                self.onSwitchTab?(tab)
            }
        }
    }

    func openWordBook() {
        guard let container = modelContainer else { return }
        showTab(.wordBook, modelContainer: container)
    }

    func openSettings() {
        guard let container = modelContainer else { return }
        showTab(.settings, modelContainer: container)
    }

    // MARK: - 高度自适应

    private func targetHeight(for tab: PanelTab) -> CGFloat {
        switch tab {
        case .translation:
            if translationContentHeight <= 0 {
                return compactHeight  // 无内容：仅搜索框
            }
            // 有内容：tabBar + 搜索栏 + divider + 实际内容高度
            let naturalHeight = tabBarHeight + searchAreaHeight + 1 + translationContentHeight
            let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.6
            return min(naturalHeight, maxHeight)
        case .wordBook:
            return userWordBookHeight ?? defaultWordBookHeight
        case .settings:
            return userSettingsHeight ?? defaultSettingsHeight
        }
    }

    func adjustHeight(for tab: PanelTab) {
        currentTab = tab
        resizePanel(to: targetHeight(for: tab), animated: true)
    }

    /// 切换 Tab 前调用：若目标 Tab 需要更大窗口，先无动画扩大，避免内容被压缩闪动
    func preExpandIfNeeded(for tab: PanelTab) {
        let target = targetHeight(for: tab)
        guard let panel, panel.frame.height < target else { return }
        resizePanel(to: target, animated: false)
    }

    func updatePanelWidth(for inputType: InputType) {
        let targetWidth = (inputType == .word) ? wordPanelWidth : sentencePanelWidth
        guard panelWidth != targetWidth else { return }
        panelWidth = targetWidth

        guard let panel else { return }
        var frame = panel.frame
        let oldWidth = frame.size.width
        frame.size.width = targetWidth
        // 保持窗口中心 X 不变
        frame.origin.x -= (targetWidth - oldWidth) / 2

        // 更新 min/max size
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
        panel.minSize = NSSize(width: targetWidth, height: compactHeight)
        panel.maxSize = NSSize(width: targetWidth, height: screenHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func updateTranslationContentHeight(_ height: CGFloat) {
        translationContentHeight = height
        guard currentTab == .translation, panel != nil else { return }
        resizePanel(to: targetHeight(for: .translation), animated: true)
    }

    func updateSettingsHeight(_ contentHeight: CGFloat) {
        settingsContentHeight = contentHeight
        guard currentTab == .settings, panel != nil else { return }
        // 如果用户已手动调整过高度，不自动改变
        if userSettingsHeight != nil { return }
        let maxHeight = NSScreen.main?.visibleFrame.height ?? 1000
        let target = min(settingsHeight, maxHeight)
        resizePanel(to: target, animated: true)
    }

    // MARK: - 动画

    /// 构建以视图中心为原点的缩放 transform（不修改 anchorPoint）
    private func centerScaleTransform(_ scale: CGFloat, in view: NSView) -> CATransform3D {
        let cx = view.bounds.midX
        let cy = view.bounds.midY
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, cx, cy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        return t
    }

    private func animateShow() {
        guard let panel, let contentView = panel.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        layer.opacity = 1
        layer.removeAllAnimations()

        let fromTransform = centerScaleTransform(0.9, in: contentView)

        panel.alphaValue = 0
        layer.transform = fromTransform
        panel.makeKeyAndOrderFront(nil)

        // 透明度淡入
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
            panel.animator().alphaValue = 1
        }

        // 弹簧缩放（从中心展开）
        let scaleAnim = CASpringAnimation(keyPath: "transform")
        scaleAnim.fromValue = fromTransform
        scaleAnim.toValue = CATransform3DIdentity
        scaleAnim.damping = 22
        scaleAnim.stiffness = 300
        scaleAnim.mass = 1
        scaleAnim.initialVelocity = 0
        scaleAnim.duration = scaleAnim.settlingDuration
        scaleAnim.isRemovedOnCompletion = true
        layer.add(scaleAnim, forKey: "showSpring")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func animateHide(completion: @escaping @MainActor () -> Void) {
        guard let panel, let contentView = panel.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        layer.removeAllAnimations()

        let toTransform = centerScaleTransform(0.92, in: contentView)

        // 向中心收缩 + 快速淡出
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = CATransform3DIdentity
        shrink.toValue = toTransform
        shrink.duration = 0.16
        shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        layer.add(shrink, forKey: "hideScale")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "hideFade")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                if let layer = panel.contentView?.layer {
                    layer.removeAllAnimations()
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.transform = CATransform3DIdentity
                    layer.opacity = 1
                    CATransaction.commit()
                }
                completion()
            }
        }
    }

    // MARK: - 面板尺寸

    private func resizePanel(to height: CGFloat, animated: Bool) {
        guard let panel else { return }
        guard panel.frame.height != height else { return }

        isResizingProgrammatically = true

        // 清理 show/hide 残留动画，防止 transform 在 resize 时产生视觉干扰
        if let layer = panel.contentView?.layer {
            layer.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
            CATransaction.commit()
        }

        var frame = panel.frame
        let oldHeight = frame.height
        let oldWidth = frame.width
        frame.size.height = height
        frame.size.width = panelWidth
        // 保持窗口顶部位置不变，从底部调整
        frame.origin.y += (oldHeight - height)
        // 保持窗口中心 X 不变
        frame.origin.x -= (panelWidth - oldWidth) / 2

        // 始终通过 animator 设置 frame，确保新调用替换旧的帧动画，
        // 避免快速切换时 non-animated setFrame 与旧 animated setFrame 竞争
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.2 : 0
            context.timingFunction = animated
                ? CAMediaTimingFunction(name: .easeInEaseOut)
                : nil
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.isResizingProgrammatically = false
            }
        }
    }

    // MARK: - 面板创建

    private func createPanel(modelContainer: ModelContainer) {
        let rect = NSRect(x: 0, y: 0, width: panelWidth, height: compactHeight)
        let newPanel = TranslationPanel(contentRect: rect)
        newPanel.delegate = self

        // 使用统一面板视图
        let contentView = UnifiedPanelView()
            .modelContainer(modelContainer)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.safeAreaRegions = []
        // 禁止 NSHostingView 根据 SwiftUI ideal size 驱动窗口尺寸变化，
        // 让 NSPanel frame 完全由 PanelManager 控制
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.hostingView = hostingView

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true

        // 使用 maskImage 裁剪圆角（比 layer.cornerRadius 更可靠，能正确裁剪 NSHostingView）
        let cornerRadius: CGFloat = 14
        let edgeLength = 2 * cornerRadius + 1
        let maskImage = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        maskImage.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        maskImage.resizingMode = .stretch
        visualEffect.maskImage = maskImage

        visualEffect.frame = rect
        hostingView.frame = rect

        visualEffect.autoresizingMask = [.width, .height]
        hostingView.autoresizingMask = [.width, .height]

        visualEffect.addSubview(hostingView)
        newPanel.contentView = visualEffect

        self.panel = newPanel

        // 设置宽松的 min/max（用户手动 resize 由 windowWillResize 控制）
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
        newPanel.minSize = NSSize(width: panelWidth, height: compactHeight)
        newPanel.maxSize = NSSize(width: panelWidth, height: screenHeight)
    }

    private func centerPanel() {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let currentHeight = panel.frame.height
        let x = screenFrame.midX - panelWidth / 2
        // 窗口顶部对齐屏幕可用区域纵向 1/4 处
        let y = screenFrame.maxY - screenFrame.height / 4 - currentHeight
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            let hide = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hideOnFocusLost) as? Bool
                ?? Constants.Defaults.hideOnFocusLost
            if hide {
                self.hidePanel()
            }
        }
    }

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated {
            var size = NSSize(width: panelWidth, height: frameSize.height)
            // 查词页不允许用户手动 resize，仅程序控制
            if currentTab == .translation && !isResizingProgrammatically {
                size.height = sender.frame.height
            }
            return size
        }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            guard !isResizingProgrammatically else { return }
            guard let panel else { return }
            let height = panel.frame.height

            switch currentTab {
            case .translation:
                break  // 查词页纯自动，不记忆
            case .wordBook:
                userWordBookHeight = height
                UserDefaults.standard.set(height, forKey: Constants.UserDefaultsKey.panelHeightWordBook)
            case .settings:
                userSettingsHeight = height
                UserDefaults.standard.set(height, forKey: Constants.UserDefaultsKey.panelHeightSettings)
            }
        }
    }
}
