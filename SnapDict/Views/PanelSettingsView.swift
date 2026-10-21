import SwiftUI
import Carbon
import HotKey

private struct SecureKeyField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isSecured = true

    var body: some View {
        HStack(spacing: 4) {
            if isSecured {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
            Button { isSecured.toggle() } label: {
                Image(systemName: isSecured ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .textFieldStyle(.roundedBorder)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    /// 设置卡片内单行的统一内边距
    func settingsRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

struct PanelSettingsView: View {
    let isActive: Bool
    var onHeightChange: ((CGFloat) -> Void)?

    private static let defaultShortcutText = "⌥Space"

    // API Keys
    @State private var deepSeekKey: String = ""
    @State private var dotKey: String = ""

    // Saved keys (for tracking unsaved changes)
    @State private var savedDeepSeekKey: String = ""
    @State private var savedDotKey: String = ""

    // Push settings
    @State private var pushEnabled: Bool = false
    @State private var pushInterval: Int = Constants.Defaults.pushIntervalMinutes
    @State private var pushOnlyLearning: Bool = Constants.Defaults.pushOnlyLearning
    @State private var pushMode: Constants.PushMode = Constants.Defaults.pushMode
    @State private var pushRandomMode: Constants.PushRandomMode = Constants.Defaults.pushRandomMode
    @State private var ditherType: Constants.DitherType = Constants.Defaults.ditherType
    @State private var ditherKernel: Constants.DitherKernel = Constants.Defaults.ditherKernel
    @State private var availableTasks: [DotTask] = []
    @State private var selectedTaskKey: String = ""
    @State private var isLoadingTasks: Bool = false
    @State private var isPushingNow: Bool = false

    // Dot connection
    enum DotConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(deviceCount: Int)
        case error(String)
    }
    @State private var connectionState: DotConnectionState = .disconnected
    @State private var connectedDevices: [DotDevice] = []
    @State private var selectedDeviceId: String = ""

    // Shortcut display
    @State private var shortcutText: String = Self.defaultShortcutText
    @State private var isRecordingShortcut = false
    @State private var enableMnemonic: Bool = Constants.Defaults.enableMnemonic
    @State private var showExamples: Bool = Constants.Defaults.showExamples
    @State private var showAnalysis: Bool = Constants.Defaults.showAnalysis
    @State private var hideOnFocusLost: Bool = Constants.Defaults.hideOnFocusLost
    @State private var autoFetchSelectedText: Bool = Constants.Defaults.autoFetchSelectedText
    @State private var accessibilityGranted: Bool = false
    @State private var accessibilityPollTimer: Timer?
    @State private var launchAtLogin: Bool = false
    @State private var launchAtLoginNeedsApproval: Bool = false
    @State private var launchAtLoginError: String?
    @State private var showMenuBarIcon: Bool = Constants.Defaults.showMenuBarIcon
    @State private var eventMonitor: Any?

    // TTS settings
    @State private var ttsEngine: Constants.TTSEngine = .system
    @State private var byteDanceTTSAppId: String = ""
    @State private var byteDanceTTSKey: String = ""
    @State private var savedByteDanceTTSAppId: String = ""
    @State private var savedByteDanceTTSKey: String = ""
    @State private var ttsFallbackToSystem: Bool = Constants.Defaults.ttsFallbackToSystem
    @State private var ttsVoice: String = Constants.API.byteDanceTTSDefaultVoice
    @State private var ttsVolume: Int = Constants.Defaults.ttsVolume

    // API test states
    enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }
    @State private var deepSeekTestState: TestState = .idle
    @State private var ttsTestState: TestState = .idle

    // Cache
    @State private var cacheSizeText: String = ""

    // Save states
    enum SaveState: Equatable {
        case idle, saved
    }
    @State private var deepSeekSaveState: SaveState = .idle
    @State private var dotSaveState: SaveState = .idle
    @State private var ttsSaveState: SaveState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                generalSection
                translationSection
                ttsSection
                pushSection
                cacheSection
                aboutSection

                Spacer(minLength: 14)
            }
            .padding(.vertical, 4)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(ContentHeightKey.self) { height in
                MainActor.assumeIsolated {
                    onHeightChange?(height)
                }
            }
        }
        .onAppear {
            loadSettings()
            startAccessibilityPolling()
        }
        .onDisappear {
            stopRecording()
            stopAccessibilityPolling()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                stopRecording()
            } else {
                checkAccessibility()
                // 用户可能在系统设置中修改了登录项
                refreshLaunchAtLogin()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var generalSection: some View {
        sectionHeader("通用", systemImage: "gearshape")

        settingsCard {
            HStack {
                rowLabel("唤醒快捷键", hint: "默认 \(Self.defaultShortcutText)，修改后立即生效，录制时按 Esc 取消")
                Spacer()
                Button(isRecordingShortcut ? "按下快捷键..." : shortcutText) {
                    toggleRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .settingsRow()

            rowDivider

            VStack(alignment: .leading, spacing: 6) {
                toggleRow("开机自动启动", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if launchAtLoginNeedsApproval {
                    statusLine(granted: false, text: "需要在系统设置的登录项中允许") {
                        LaunchAtLogin.openSystemSettings()
                    }
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .settingsRow()

            rowDivider

            toggleRow(
                "在菜单栏显示图标",
                hint: showMenuBarIcon ? nil : "已隐藏，可通过 \(shortcutText) 或再次打开 SnapDict 唤出面板",
                isOn: $showMenuBarIcon
            )
            .onChange(of: showMenuBarIcon) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.showMenuBarIcon)
                NotificationCenter.default.post(name: Constants.Notification.menuBarIconVisibilityChanged, object: nil)
            }
            .settingsRow()

            rowDivider

            toggleRow("失去焦点自动关闭", isOn: $hideOnFocusLost)
                .onChange(of: hideOnFocusLost) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.hideOnFocusLost)
                }
                .settingsRow()

            rowDivider

            VStack(alignment: .leading, spacing: 6) {
                toggleRow("自动获取选中文字", hint: "唤出面板时直接查询当前选中的文字", isOn: $autoFetchSelectedText)
                    .onChange(of: autoFetchSelectedText) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.autoFetchSelectedText)
                        if newValue {
                            SelectedTextReader.requestAccessibility()
                            checkAccessibility()
                            startAccessibilityPolling()
                        } else {
                            stopAccessibilityPolling()
                        }
                    }
                if autoFetchSelectedText {
                    if accessibilityGranted {
                        statusLine(granted: true, text: "辅助功能权限已授予")
                    } else {
                        statusLine(granted: false, text: "需要辅助功能权限") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            .settingsRow()
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        sectionHeader("查词", systemImage: "character.book.closed")

        settingsCard {
            apiKeyRow(
                title: "DeepSeek",
                hint: "用于翻译功能，从 platform.deepseek.com 获取",
                key: $deepSeekKey,
                savedKey: $savedDeepSeekKey,
                saveState: $deepSeekSaveState,
                testState: deepSeekTestState,
                onSave: {
                    saveKeyWithTest(
                        value: deepSeekKey,
                        defaultsKey: Constants.UserDefaultsKey.deepSeekAPIKey,
                        savedKey: $savedDeepSeekKey,
                        saveState: $deepSeekSaveState,
                        setState: { deepSeekTestState = $0 },
                        action: { _ = try await DeepSeekService.shared.testAPI() }
                    )
                },
                onTest: { testDeepSeek() }
            )
            .settingsRow()

            rowDivider

            toggleRow("显示助记", isOn: $enableMnemonic)
                .onChange(of: enableMnemonic) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.enableMnemonic)
                }
                .settingsRow()

            rowDivider

            toggleRow("显示例句", isOn: $showExamples)
                .onChange(of: showExamples) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.showExamples)
                }
                .settingsRow()

            rowDivider

            toggleRow("显示语法解析", isOn: $showAnalysis)
                .onChange(of: showAnalysis) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.showAnalysis)
                }
                .settingsRow()
        }
    }

    @ViewBuilder
    private var ttsSection: some View {
        sectionHeader("发音", systemImage: "speaker.wave.2")

        settingsCard {
            HStack {
                rowLabel("发音引擎")
                Spacer()
                Picker("发音引擎", selection: $ttsEngine) {
                    ForEach(Constants.TTSEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: ttsEngine) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.ttsEngine)
                }
            }
            .settingsRow()

            if ttsEngine == .byteDance {
                rowDivider

                ttsApiKeyRow()
                    .settingsRow()

                rowDivider

                HStack {
                    rowLabel("音色")
                    Spacer()
                    Picker("", selection: $ttsVoice) {
                        ForEach(Constants.API.byteDanceTTSVoices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: ttsVoice) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.byteDanceTTSVoice)
                    }
                }
                .settingsRow()

                rowDivider

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        rowLabel("音量")
                        Spacer()
                        Text("\(ttsVolume)%")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(ttsVolume) },
                            set: { ttsVolume = Int($0) }
                        ),
                        in: 10...Double(Constants.Defaults.ttsVolumeMax),
                        step: 10
                    )
                    .controlSize(.small)
                    .onChange(of: ttsVolume) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.ttsVolume)
                    }
                }
                .settingsRow()

                rowDivider

                toggleRow("合成失败时降级为系统发音", isOn: $ttsFallbackToSystem)
                    .onChange(of: ttsFallbackToSystem) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.ttsFallbackToSystem)
                    }
                    .settingsRow()
            }
        }
    }

    @ViewBuilder
    private var pushSection: some View {
        sectionHeader("推送", systemImage: "rectangle.on.rectangle")

        settingsCard {
            toggleRow("墨水屏推送", hint: pushEnabled ? nil : "定时将单词本中的单词推送到 Dot. 墨水屏", isOn: $pushEnabled)
                .onChange(of: pushEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.pushEnabled)
                    if newValue {
                        WordPushScheduler.shared.start()
                    } else {
                        WordPushScheduler.shared.stop()
                    }
                }
                .settingsRow()

            if pushEnabled {
                pushSettingsRows
            }
        }
    }

    @ViewBuilder
    private var pushSettingsRows: some View {
        rowDivider

        VStack(alignment: .leading, spacing: 8) {
            dotApiKeyRow()
            dotConnectionIndicator()
        }
        .settingsRow()

        // 设备选择（仅已连接时显示）
        if case .connected = connectionState {
            rowDivider

            HStack {
                rowLabel("设备")
                Spacer()
                if connectedDevices.count > 1 {
                    Picker("", selection: $selectedDeviceId) {
                        ForEach(connectedDevices) { device in
                            Text(device.displayName).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: selectedDeviceId) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.cachedDeviceId)
                        loadTasks()
                    }
                } else if let device = connectedDevices.first {
                    Text(device.displayName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button {
                    refreshDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(connectionState == .connecting)
            }
            .settingsRow()

            rowDivider

            // 任务标识
            let matchingTasks = availableTasks.filter { pushMode == .image ? $0.isImageAPI : $0.isTextAPI }
            HStack {
                rowLabel("任务标识", hint: "设备有多个\(pushMode == .image ? "图像" : "文本") API 内容时，用于指定推送目标")
                Spacer()
                if isLoadingTasks {
                    ProgressView().controlSize(.small)
                } else if matchingTasks.isEmpty {
                    Text(selectedTaskKey.isEmpty ? "默认" : selectedTaskKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $selectedTaskKey) {
                        Text("默认").tag("")
                        ForEach(matchingTasks) { task in
                            Text(task.key ?? "unknown").tag(task.key ?? "")
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: selectedTaskKey) { _, newValue in
                        if newValue.isEmpty {
                            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.cachedTaskKey)
                        } else {
                            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.cachedTaskKey)
                        }
                    }
                }
            }
            .settingsRow()
        }

        rowDivider

        HStack {
            rowLabel("推送间隔")
            Spacer()
            Text("\(pushInterval) 分钟")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
            Stepper("推送间隔", value: $pushInterval, in: 5...120, step: 5)
                .labelsHidden()
                .onChange(of: pushInterval) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.pushInterval)
                    if WordPushScheduler.shared.isRunning {
                        WordPushScheduler.shared.restart()
                    }
                }
        }
        .settingsRow()

        rowDivider

        toggleRow("只推送学习中", isOn: $pushOnlyLearning)
            .onChange(of: pushOnlyLearning) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.pushOnlyLearning)
            }
            .settingsRow()

        rowDivider

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                rowLabel("推送顺序")
                Spacer()
                Picker("推送顺序", selection: $pushRandomMode) {
                    ForEach(Constants.PushRandomMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: pushRandomMode) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.pushRandomMode)
                }
            }
            hintText(pushRandomMode.description)
        }
        .settingsRow()

        rowDivider

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                rowLabel("推送模式")
                Spacer()
                Picker("推送模式", selection: $pushMode) {
                    ForEach(Constants.PushMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: pushMode) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.pushMode)
                    loadTasks()
                }
            }
            hintText(pushMode == .image ? "将单词渲染为图片推送，排版更美观" : "推送纯文本内容到设备")
        }
        .settingsRow()

        if pushMode == .image {
            rowDivider

            HStack {
                rowLabel("抖动类型")
                Spacer()
                Picker("抖动类型", selection: $ditherType) {
                    ForEach(Constants.DitherType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: ditherType) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.ditherType)
                }
            }
            .settingsRow()

            if ditherType == .diffusion {
                rowDivider

                HStack {
                    rowLabel("抖动算法")
                    Spacer()
                    Picker("抖动算法", selection: $ditherKernel) {
                        ForEach(Constants.DitherKernel.allCases, id: \.self) { kernel in
                            Text(kernel.displayName).tag(kernel)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: ditherKernel) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.ditherKernel)
                    }
                }
                .settingsRow()
            }
        }

        rowDivider

        VStack(alignment: .leading, spacing: 10) {
            pushContentPreview()

            HStack(spacing: 8) {
                Button {
                    isPushingNow = true
                    Task {
                        await WordPushScheduler.shared.pushNext()
                        isPushingNow = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isPushingNow {
                            ProgressView().controlSize(.small)
                        }
                        Text("立即推送下一条")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPushingNow)

                if let error = WordPushScheduler.shared.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
        .settingsRow()
    }

    @ViewBuilder
    private var cacheSection: some View {
        sectionHeader("缓存", systemImage: "internaldrive")

        settingsCard {
            HStack {
                rowLabel(cacheSizeText, hint: "清除翻译结果缓存，不影响生词本数据")
                Spacer()
                Button("清除缓存") {
                    CacheService.shared.clearAllCache()
                    updateCacheSize()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
            .settingsRow()
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        sectionHeader("关于", systemImage: "info.circle")

        settingsCard {
            HStack {
                rowLabel("当前版本")
                Spacer()
                Text(Self.appVersionText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .settingsRow()

            rowDivider

            HStack {
                rowLabel("退出 SnapDict", hint: showMenuBarIcon ? nil : "菜单栏图标已隐藏，可在此退出应用")
                Spacer()
                Button("退出") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .settingsRow()
        }
    }

    // MARK: - Row Components

    private static let appVersionText: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return "v\(version)"
    }()

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 14)
    }

    private func rowLabel(_ title: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
            if let hint {
                hintText(hint)
            }
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRow(_ title: String, hint: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            rowLabel(title, hint: hint)
            Spacer()
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    /// 权限 / 授权状态行：未授予时附带「前往设置」按钮
    private func statusLine(granted: Bool, text: String, openSettings: (() -> Void)? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(text)
            Spacer()
            if let openSettings {
                Button("前往设置", action: openSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    // MARK: - Dot Push UI Components

    @ViewBuilder
    private func dotApiKeyRow() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("墨水屏 (Dot. App)")
                .font(.system(size: 13))
            HStack(spacing: 6) {
                SecureKeyField(placeholder:"API Key", text: $dotKey)
                Button(dotSaveState == .saved ? "已保存" : "保存") {
                    saveDotKeyAndRefresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(dotKey == savedDotKey || connectionState == .connecting)
                .tint(dotSaveState == .saved ? .green : nil)
            }
            Text("用于推送单词到墨水屏，从 Dot. App 获取")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if case .error(let msg) = connectionState {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func dotConnectionIndicator() -> some View {
        switch connectionState {
        case .disconnected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                Text("未连接")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .connecting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("连接中...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .connected(let deviceCount):
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("已连接 · \(deviceCount) 台设备")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .error:
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text("连接失败")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func pushContentPreview() -> some View {
        let lastWord = WordBookManager.shared.lastPushedWord()

        VStack(alignment: .leading, spacing: 8) {
            Text("推送预览")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if let entry = lastWord {
                if pushMode == .image {
                    ditherPreview(entry: entry)
                } else {
                    let message = [
                        entry.phonetic.isEmpty ? nil : entry.phonetic,
                        entry.translation,
                        entry.examples.first
                    ]
                        .compactMap { $0 }
                        .joined(separator: "\n")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.word)
                            .font(.system(size: 16, weight: .bold))
                        Divider()
                        Text(message)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                        HStack {
                            Spacer()
                            Text("SnapDict")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.97))
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
            } else {
                Text("暂无推送记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func ditherPreview(entry: WordEntry) -> some View {
        let cardView = WordCardImageView(
            word: entry.word,
            phonetic: entry.phonetic,
            translation: entry.translation
        )

        let dithered: NSImage? = {
            let renderer = ImageRenderer(content: cardView)
            renderer.scale = 1.0
            guard let cgImage = renderer.cgImage else { return nil }
            guard let result = DitherSimulator.apply(to: cgImage, type: ditherType, kernel: ditherKernel) else { return nil }
            return NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
        }()

        if let nsImage = dithered {
            Image(nsImage: nsImage)
                .interpolation(.none)
                .resizable()
                .frame(width: 296, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        } else {
            cardView
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func apiTestButton(state: TestState, action: @escaping () -> Void) -> some View {
        switch state {
        case .idle:
            Button("测试") { action() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .testing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("测试中")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("连接成功", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .failure:
            Button("重试") { action() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
        }
    }


    @ViewBuilder
    private func apiKeyRow(
        title: String,
        placeholder: String = "API Key",
        hint: String,
        key: Binding<String>,
        savedKey: Binding<String>,
        saveState: Binding<SaveState>,
        testState: TestState,
        onSave: @escaping () -> Void,
        onTest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13))
            HStack(spacing: 6) {
                SecureKeyField(placeholder:placeholder, text: key)
                apiTestButton(state: testState, action: onTest)
                Button(saveState.wrappedValue == .saved ? "已保存" : "保存") {
                    onSave()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(key.wrappedValue == savedKey.wrappedValue || testState == .testing)
                .tint(saveState.wrappedValue == .saved ? .green : nil)
            }
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if case .failure(let msg) = testState {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func saveKeyWithTest(
        value: String,
        defaultsKey: String,
        savedKey: Binding<String>,
        saveState: Binding<SaveState>,
        setState: @escaping (TestState) -> Void,
        action: @escaping () async throws -> Void
    ) {
        guard !value.isEmpty else {
            setState(.failure("请先填写 API Key"))
            return
        }
        setState(.testing)
        Task {
            let previousKey = UserDefaults.standard.string(forKey: defaultsKey)
            UserDefaults.standard.set(value, forKey: defaultsKey)
            do {
                try await action()
                savedKey.wrappedValue = value
                saveState.wrappedValue = .saved
                setState(.success)
                try? await Task.sleep(for: .seconds(3))
                saveState.wrappedValue = .idle
                setState(.idle)
            } catch {
                if let previousKey {
                    UserDefaults.standard.set(previousKey, forKey: defaultsKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: defaultsKey)
                }
                setState(.failure(error.localizedDescription))
            }
        }
    }

    // MARK: - API Tests

    private func testAPIKey(
        currentKey: String,
        savedKey: String,
        defaultsKey: String,
        setState: @escaping (TestState) -> Void,
        action: @escaping () async throws -> Void
    ) {
        let keyToTest = currentKey.isEmpty
            ? (UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            : currentKey
        guard !keyToTest.isEmpty else {
            setState(.failure("请先填写 API Key"))
            return
        }
        setState(.testing)
        Task {
            let previousKey = UserDefaults.standard.string(forKey: defaultsKey)
            UserDefaults.standard.set(keyToTest, forKey: defaultsKey)
            defer {
                if currentKey != savedKey {
                    UserDefaults.standard.set(previousKey, forKey: defaultsKey)
                }
            }
            var succeeded = false
            do {
                try await action()
                setState(.success)
                succeeded = true
            } catch {
                setState(.failure(error.localizedDescription))
            }
            if succeeded {
                try? await Task.sleep(for: .seconds(3))
                setState(.idle)
            }
        }
    }

    @ViewBuilder
    private func ttsApiKeyRow() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("豆包语音合成")
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("App ID", text: $byteDanceTTSAppId)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 6) {
                    SecureKeyField(placeholder: "Access Key", text: $byteDanceTTSKey)
                    apiTestButton(state: ttsTestState, action: { testTTS() })
                    Button(ttsSaveState == .saved ? "已保存" : "保存") {
                        saveTTSKeysWithTest()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        (byteDanceTTSAppId == savedByteDanceTTSAppId && byteDanceTTSKey == savedByteDanceTTSKey)
                        || ttsTestState == .testing
                    )
                    .tint(ttsSaveState == .saved ? .green : nil)
                }
            }
            Text("从火山引擎控制台获取")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if case .failure(let msg) = ttsTestState {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func saveTTSKeysWithTest() {
        guard !byteDanceTTSAppId.isEmpty, !byteDanceTTSKey.isEmpty else {
            ttsTestState = .failure("请填写 App ID 和 Access Key")
            return
        }
        ttsTestState = .testing
        Task {
            let previousAppId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            let previousKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            UserDefaults.standard.set(byteDanceTTSAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            UserDefaults.standard.set(byteDanceTTSKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            do {
                let audioData = try await ByteDanceTTSService.shared.fetchAudio(text: "hello", skipCache: true)
                // 播放测试音频
                try await TTSManager.shared.playTestAudio(audioData)
                savedByteDanceTTSAppId = byteDanceTTSAppId
                savedByteDanceTTSKey = byteDanceTTSKey
                ttsSaveState = .saved
                ttsTestState = .success
                try? await Task.sleep(for: .seconds(3))
                ttsSaveState = .idle
                ttsTestState = .idle
            } catch {
                // 回滚
                if let previousAppId {
                    UserDefaults.standard.set(previousAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
                } else {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
                }
                if let previousKey {
                    UserDefaults.standard.set(previousKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
                }
                ttsTestState = .failure(error.localizedDescription)
            }
        }
    }

    private func testTTS() {
        let appId = byteDanceTTSAppId.isEmpty
            ? (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) ?? "")
            : byteDanceTTSAppId
        let key = byteDanceTTSKey.isEmpty
            ? (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) ?? "")
            : byteDanceTTSKey
        guard !appId.isEmpty, !key.isEmpty else {
            ttsTestState = .failure("请填写 App ID 和 Access Key")
            return
        }
        ttsTestState = .testing
        Task {
            let previousAppId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            let previousKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            UserDefaults.standard.set(appId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            UserDefaults.standard.set(key, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            defer {
                if byteDanceTTSAppId != savedByteDanceTTSAppId || byteDanceTTSKey != savedByteDanceTTSKey {
                    if let previousAppId { UserDefaults.standard.set(previousAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) }
                    else { UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) }
                    if let previousKey { UserDefaults.standard.set(previousKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) }
                    else { UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) }
                }
            }
            do {
                let audioData = try await ByteDanceTTSService.shared.fetchAudio(text: "hello", skipCache: true)
                try await TTSManager.shared.playTestAudio(audioData)
                ttsTestState = .success
                try? await Task.sleep(for: .seconds(3))
                ttsTestState = .idle
            } catch {
                ttsTestState = .failure(error.localizedDescription)
            }
        }
    }

    private func testDeepSeek() {
        testAPIKey(
            currentKey: deepSeekKey,
            savedKey: savedDeepSeekKey,
            defaultsKey: Constants.UserDefaultsKey.deepSeekAPIKey,
            setState: { deepSeekTestState = $0 },
            action: { _ = try await DeepSeekService.shared.testAPI() }
        )
    }

    private func saveDotKeyAndRefresh() {
        guard !dotKey.isEmpty else {
            connectionState = .error("请先填写 API Key")
            return
        }
        let previousKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.dotAPIKey)
        UserDefaults.standard.set(dotKey, forKey: Constants.UserDefaultsKey.dotAPIKey)
        connectionState = .connecting
        Task {
            do {
                let devices = try await DotScreenService.shared.fetchDevices()
                guard !devices.isEmpty else {
                    throw DotError.requestFailed
                }
                connectedDevices = devices
                // 保存成功
                savedDotKey = dotKey
                dotSaveState = .saved
                // 选中设备
                let cachedId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedDeviceId) ?? ""
                if devices.contains(where: { $0.id == cachedId }) {
                    selectedDeviceId = cachedId
                } else {
                    selectedDeviceId = devices.first!.id
                    UserDefaults.standard.set(selectedDeviceId, forKey: Constants.UserDefaultsKey.cachedDeviceId)
                }
                connectionState = .connected(deviceCount: devices.count)
                loadTasks()
                try? await Task.sleep(for: .seconds(2))
                dotSaveState = .idle
            } catch {
                // 还原 Key
                if let previousKey {
                    UserDefaults.standard.set(previousKey, forKey: Constants.UserDefaultsKey.dotAPIKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.dotAPIKey)
                }
                connectedDevices = []
                connectionState = .error(error.localizedDescription)
            }
        }
    }

    private func refreshDevices() {
        connectionState = .connecting
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.cachedDeviceId)
        Task {
            do {
                let devices = try await DotScreenService.shared.fetchDevices()
                guard !devices.isEmpty else {
                    throw DotError.requestFailed
                }
                connectedDevices = devices
                // 优先选之前选中的设备
                let previousId = selectedDeviceId
                if devices.contains(where: { $0.id == previousId }) {
                    selectedDeviceId = previousId
                } else {
                    selectedDeviceId = devices.first!.id
                }
                UserDefaults.standard.set(selectedDeviceId, forKey: Constants.UserDefaultsKey.cachedDeviceId)
                connectionState = .connected(deviceCount: devices.count)
                loadTasks()
            } catch {
                connectedDevices = []
                connectionState = .error(error.localizedDescription)
            }
        }
    }

    private func loadTasks() {
        guard !selectedDeviceId.isEmpty else { return }
        isLoadingTasks = true
        Task {
            do {
                let tasks = try await DotScreenService.shared.fetchTasks(deviceId: selectedDeviceId)
                availableTasks = tasks
                let matchingTasks = tasks.filter { pushMode == .image ? $0.isImageAPI : $0.isTextAPI }
                if !matchingTasks.contains(where: { $0.key == selectedTaskKey }) {
                    selectedTaskKey = ""
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.cachedTaskKey)
                }
            } catch {
                availableTasks = []
            }
            isLoadingTasks = false
        }
    }

    // MARK: - Shortcut Recording

    private func toggleRecording() {
        if isRecordingShortcut {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecordingShortcut = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard self.isRecordingShortcut else { return event }
            // 过滤掉纯修饰键按下（没有实际按键）
            let keyCode = event.keyCode
            let carbonMods = carbonModifiers(from: event.modifierFlags)

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // 单独按 Esc 取消录制
            if keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
                self.stopRecording()
                return nil
            }

            // 全局热键会吞掉系统内所有该组合的按键：无修饰键（如空格）或仅 Shift（如大写字母）
            // 会让正常打字失效，因此至少需要 ⌘ / ⌥ / ⌃ 之一
            let hasModifier = !modifiers.intersection([.command, .option, .control]).isEmpty
            if hasModifier {
                self.applyShortcut(keyCode: UInt32(keyCode), carbonModifiers: carbonMods, displayFlags: event.modifierFlags)
            }
            return nil // 消耗事件，防止触发其他操作
        }
    }

    private func stopRecording() {
        isRecordingShortcut = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func applyShortcut(keyCode: UInt32, carbonModifiers: UInt32, displayFlags: NSEvent.ModifierFlags) {
        stopRecording()
        HotKeyManager.shared.updateHotKey(keyCode: keyCode, modifiers: carbonModifiers)
        shortcutText = shortcutDisplayText(keyCode: keyCode, modifiers: displayFlags)
    }

    /// 将 NSEvent.ModifierFlags 转换为 Carbon modifier flags
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }

    /// 生成快捷键的可读显示文本
    private func shortcutDisplayText(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option)  { text += "⌥" }
        if modifiers.contains(.shift)   { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }

        if let key = Key(carbonKeyCode: keyCode) {
            switch key {
            case .space:     text += "Space"
            case .return:    text += "↩"
            case .delete:    text += "⌫"
            case .tab:       text += "⇥"
            case .escape:    text += "⎋"
            case .upArrow:   text += "↑"
            case .downArrow: text += "↓"
            case .leftArrow: text += "←"
            case .rightArrow:text += "→"
            default:
                text += key.description.uppercased()
            }
        }
        return text
    }

    // MARK: - Helpers

    private func checkAccessibility() {
        accessibilityGranted = SelectedTextReader.isAccessibilityGranted()
        if accessibilityGranted {
            stopAccessibilityPolling()
        }
    }

    private func startAccessibilityPolling() {
        stopAccessibilityPolling()
        guard autoFetchSelectedText, !accessibilityGranted else { return }
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                checkAccessibility()
            }
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            launchAtLoginError = "设置失败：\(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        let status = LaunchAtLogin.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private func loadSettings() {
        deepSeekKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.deepSeekAPIKey) ?? ""
        savedDeepSeekKey = deepSeekKey
        dotKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.dotAPIKey) ?? ""
        savedDotKey = dotKey
        pushEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.pushEnabled)
        pushInterval = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushInterval) as? Int
            ?? Constants.Defaults.pushIntervalMinutes
        pushOnlyLearning = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushOnlyLearning) as? Bool
            ?? Constants.Defaults.pushOnlyLearning
        pushRandomMode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.pushRandomMode)
            .flatMap { Constants.PushRandomMode(rawValue: $0) } ?? Constants.Defaults.pushRandomMode
        enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples
        showAnalysis = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showAnalysis) as? Bool
            ?? Constants.Defaults.showAnalysis
        hideOnFocusLost = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hideOnFocusLost) as? Bool
            ?? Constants.Defaults.hideOnFocusLost
        autoFetchSelectedText = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.autoFetchSelectedText) as? Bool
            ?? Constants.Defaults.autoFetchSelectedText
        checkAccessibility()
        refreshLaunchAtLogin()
        showMenuBarIcon = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showMenuBarIcon) as? Bool
            ?? Constants.Defaults.showMenuBarIcon
        let pushModeRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.pushMode) ?? ""
        pushMode = Constants.PushMode(rawValue: pushModeRaw) ?? Constants.Defaults.pushMode
        let ditherTypeRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ditherType) ?? ""
        ditherType = Constants.DitherType(rawValue: ditherTypeRaw) ?? Constants.Defaults.ditherType
        let ditherKernelRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ditherKernel) ?? ""
        ditherKernel = Constants.DitherKernel(rawValue: ditherKernelRaw) ?? Constants.Defaults.ditherKernel
        selectedTaskKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedTaskKey) ?? ""
        selectedDeviceId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedDeviceId) ?? ""
        // 有 Key 时自动连接获取设备
        if !dotKey.isEmpty {
            // 有缓存设备 ID 时先乐观显示已连接，再后台刷新
            if !selectedDeviceId.isEmpty {
                connectionState = .connected(deviceCount: 1)
            } else {
                connectionState = .connecting
            }
            Task {
                do {
                    let devices = try await DotScreenService.shared.fetchDevices()
                    guard !devices.isEmpty else {
                        if selectedDeviceId.isEmpty { connectionState = .error("未找到设备") }
                        return
                    }
                    connectedDevices = devices
                    if !devices.contains(where: { $0.id == selectedDeviceId }) {
                        selectedDeviceId = devices.first!.id
                        UserDefaults.standard.set(selectedDeviceId, forKey: Constants.UserDefaultsKey.cachedDeviceId)
                    }
                    connectionState = .connected(deviceCount: devices.count)
                    loadTasks()
                } catch {
                    // 有缓存时静默失败保持状态，无缓存时显示错误
                    if selectedDeviceId.isEmpty {
                        connectionState = .error(error.localizedDescription)
                    }
                }
            }
        }
        ttsEngine = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ttsEngine)
            .flatMap { Constants.TTSEngine(rawValue: $0) } ?? .system
        byteDanceTTSAppId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) ?? ""
        savedByteDanceTTSAppId = byteDanceTTSAppId
        byteDanceTTSKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) ?? ""
        savedByteDanceTTSKey = byteDanceTTSKey
        ttsFallbackToSystem = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsFallbackToSystem) as? Bool
            ?? Constants.Defaults.ttsFallbackToSystem
        ttsVoice = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSVoice)
            ?? Constants.API.byteDanceTTSDefaultVoice
        ttsVolume = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsVolume) as? Int
            ?? Constants.Defaults.ttsVolume
        shortcutText = loadShortcutText()
        updateCacheSize()
    }

    private func updateCacheSize() {
        let counts = CacheService.shared.cacheCounts()
        cacheSizeText = "翻译 \(counts.translation) 条 / 句子 \(counts.sentence) 条 / 音频 \(counts.tts) 条"
    }

    private func loadShortcutText() -> String {
        guard
            let keyCode = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hotKeyKeyCode) as? UInt32,
            let carbonMods = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hotKeyModifiers) as? UInt32
        else {
            return Self.defaultShortcutText
        }
        let flags = NSEvent.ModifierFlags(carbonFlags: carbonMods)
        return shortcutDisplayText(keyCode: keyCode, modifiers: flags)
    }

}
