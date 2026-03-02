import SwiftUI
import Carbon
import HotKey

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PanelSettingsView: View {
    let isActive: Bool
    var onHeightChange: ((CGFloat) -> Void)?

    private static let defaultShortcutText = "⌥Space"

    // API Keys
    @State private var deepSeekKey: String = ""
    @State private var dotKey: String = ""
    @State private var byteDanceTTSAppId: String = ""
    @State private var byteDanceTTSKey: String = ""

    // Saved keys (for tracking unsaved changes)
    @State private var savedDeepSeekKey: String = ""
    @State private var savedDotKey: String = ""
    @State private var savedByteDanceTTSAppId: String = ""
    @State private var savedByteDanceTTSKey: String = ""

    // TTS
    @State private var ttsEngine: Constants.TTSEngine = .system
    @State private var ttsFallbackToSystem: Bool = Constants.Defaults.ttsFallbackToSystem
    @State private var ttsVoice: String = Constants.API.byteDanceTTSDefaultVoice

    // Push settings
    @State private var pushInterval: Int = Constants.Defaults.pushIntervalMinutes
    @State private var pushOnlyLearning: Bool = Constants.Defaults.pushOnlyLearning
    @State private var availableTasks: [DotTask] = []
    @State private var selectedTaskKey: String = ""
    @State private var isLoadingTasks: Bool = false

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
    @State private var eventMonitor: Any?

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
                // MARK: 通用
                sectionHeader("通用")

                VStack(spacing: 0) {
                    HStack {
                        Text("唤醒快捷键")
                            .font(.system(size: 14))
                        Button(isRecordingShortcut ? "按下快捷键..." : shortcutText) {
                            toggleRecording()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Text("默认 \(Self.defaultShortcutText)，修改后立即生效")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)

                // MARK: 查词
                sectionHeader("查词")

                VStack(spacing: 0) {
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
                                action: { _ = try await DeepSeekService.shared.translate("hello") }
                            )
                        },
                        onTest: { testDeepSeek() }
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    Toggle("显示助记", isOn: $enableMnemonic)
                        .toggleStyle(.switch)
                        .onChange(of: enableMnemonic) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.enableMnemonic)
                        }
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

//                    Text("开启后显示词根词缀拆解和联想记忆")
//                        .font(.system(size: 11))
//                        .foregroundStyle(.tertiary)
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                        .padding(.horizontal, 14)
//                        .padding(.bottom, 10)

                    Divider().padding(.leading, 14)

                    Toggle("显示例句", isOn: $showExamples)
                        .toggleStyle(.switch)
                        .onChange(of: showExamples) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.showExamples)
                        }
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)

                // MARK: 发音
                sectionHeader("发音")

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("发音引擎")
                            .font(.system(size: 14))
                        Picker("引擎", selection: $ttsEngine) {
                            ForEach(Constants.TTSEngine.allCases, id: \.self) { engine in
                                Text(engine.displayName).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .onChange(of: ttsEngine) { _, newValue in
                            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.ttsEngine)
                        }
                        Text(ttsEngine == .byteDance ? "使用豆包在线语音合成" : "使用系统内置语音，无需联网")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if ttsEngine == .byteDance {
                        Divider().padding(.leading, 14)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("App ID")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .leading)
                                TextField("App ID", text: $byteDanceTTSAppId)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack(spacing: 6) {
                                Text("Access Key")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .leading)
                                SecureField("Access Key", text: $byteDanceTTSKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack(spacing: 6) {
                                Text("从火山引擎控制台获取")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                apiTestButton(state: ttsTestState, action: { testTTS() })
                                Button(ttsSaveState == .saved ? "已保存" : "保存") {
                                    saveTTSKeysWithTest()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled((byteDanceTTSAppId == savedByteDanceTTSAppId && byteDanceTTSKey == savedByteDanceTTSKey) || ttsTestState == .testing)
                                .tint(ttsSaveState == .saved ? .green : nil)
                            }
                            if case .failure(let msg) = ttsTestState {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 14)

                        HStack {
                            Text("音色")
                                .font(.system(size: 14))
                            Picker("音色", selection: $ttsVoice) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Toggle("合成失败时降级为系统发音", isOn: $ttsFallbackToSystem)
                            .font(.system(size: 12))
                            .toggleStyle(.checkbox)
                            .onChange(of: ttsFallbackToSystem) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.ttsFallbackToSystem)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)

                // MARK: 推送
                sectionHeader("推送")

                VStack(spacing: 0) {
                    // API Key 行
                    dotApiKeyRow()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    // 连接状态指示器
                    dotConnectionIndicator()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                    // 设备选择（仅已连接时显示）
                    if case .connected = connectionState {
                        Divider().padding(.leading, 14)

                        HStack {
                            Text("设备")
                                .font(.system(size: 14))
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
                            Spacer()
                            Button {
                                refreshDevices()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(connectionState == .connecting)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 14)

                        // 任务标识
                        HStack {
                            Text("任务标识")
                                .font(.system(size: 14))
                            if isLoadingTasks {
                                ProgressView().controlSize(.small)
                            } else if availableTasks.filter(\.isTextAPI).isEmpty {
                                Text(selectedTaskKey.isEmpty ? "默认" : selectedTaskKey)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("", selection: $selectedTaskKey) {
                                    Text("默认").tag("")
                                    ForEach(availableTasks.filter(\.isTextAPI)) { task in
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Text("设备有多个文本 API 内容时，用于指定推送目标")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }

                    Divider().padding(.leading, 14)

                    Stepper(
                        "每 \(pushInterval) 分钟推送一次",
                        value: $pushInterval,
                        in: 5...120,
                        step: 5
                    )
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: pushInterval) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.pushInterval)
                        if WordPushScheduler.shared.isRunning {
                            WordPushScheduler.shared.restart()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    Toggle("只推送学习中", isOn: $pushOnlyLearning)
                        .toggleStyle(.switch)
                        .onChange(of: pushOnlyLearning) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.pushOnlyLearning)
                        }
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)

                // MARK: 缓存
                sectionHeader("缓存")

                VStack(spacing: 0) {
                    HStack {
                        Text("缓存大小")
                            .font(.system(size: 14))
                        Spacer()
                        Text(cacheSizeText)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    Button("清除所有缓存") {
                        CacheService.shared.clearAllCache()
                        updateCacheSize()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Text("清除翻译结果和语音缓存，不影响生词本数据")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)

                Spacer(minLength: 14)
            }
            .padding(.vertical, 4)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(ContentHeightKey.self) { height in
                onHeightChange?(height)
            }
        }
        .onAppear { loadSettings() }
        .onDisappear { stopRecording() }
        .onChange(of: isActive) { _, active in
            if !active { stopRecording() }
        }
    }

    // MARK: - Dot Push UI Components

    @ViewBuilder
    private func dotApiKeyRow() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("墨水屏 (Dot. App)")
                .font(.system(size: 14))
            HStack(spacing: 6) {
                SecureField("API Key", text: $dotKey)
                    .textFieldStyle(.roundedBorder)
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
                .font(.system(size: 14))
            HStack(spacing: 6) {
                SecureField(placeholder, text: key)
                    .textFieldStyle(.roundedBorder)
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

    private func saveKey(
        value: String,
        defaultsKey: String,
        savedKey: Binding<String>,
        saveState: Binding<SaveState>
    ) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        }
        savedKey.wrappedValue = value
        saveState.wrappedValue = .saved
        Task {
            try? await Task.sleep(for: .seconds(2))
            saveState.wrappedValue = .idle
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

    private func testDeepSeek() {
        testAPIKey(
            currentKey: deepSeekKey,
            savedKey: savedDeepSeekKey,
            defaultsKey: Constants.UserDefaultsKey.deepSeekAPIKey,
            setState: { deepSeekTestState = $0 },
            action: { _ = try await DeepSeekService.shared.translate("hello") }
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

    private func saveTTSKeys() {
        saveKey(value: byteDanceTTSAppId, defaultsKey: Constants.UserDefaultsKey.byteDanceTTSAppId,
                savedKey: $savedByteDanceTTSAppId, saveState: $ttsSaveState)
        saveKey(value: byteDanceTTSKey, defaultsKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey,
                savedKey: $savedByteDanceTTSKey, saveState: $ttsSaveState)
    }

    private func testTTS() {
        guard !byteDanceTTSAppId.isEmpty, !byteDanceTTSKey.isEmpty else {
            ttsTestState = .failure("请先填写 App ID 和 Access Key")
            return
        }
        ttsTestState = .testing
        Task {
            let prevAppId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            let prevKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            UserDefaults.standard.set(byteDanceTTSAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            UserDefaults.standard.set(byteDanceTTSKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            defer {
                if byteDanceTTSAppId != savedByteDanceTTSAppId || byteDanceTTSKey != savedByteDanceTTSKey {
                    UserDefaults.standard.set(prevAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
                    UserDefaults.standard.set(prevKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
                }
            }
            do {
                try await ByteDanceTTSService.shared.speak("hello")
                ttsTestState = .success
                try? await Task.sleep(for: .seconds(3))
                ttsTestState = .idle
            } catch {
                ttsTestState = .failure(error.localizedDescription)
            }
        }
    }

    private func saveTTSKeysWithTest() {
        guard !byteDanceTTSAppId.isEmpty, !byteDanceTTSKey.isEmpty else {
            ttsTestState = .failure("请先填写 App ID 和 Access Key")
            return
        }
        ttsTestState = .testing
        Task {
            let prevAppId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            let prevKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            UserDefaults.standard.set(byteDanceTTSAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
            UserDefaults.standard.set(byteDanceTTSKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
            do {
                try await ByteDanceTTSService.shared.speak("hello")
                savedByteDanceTTSAppId = byteDanceTTSAppId
                savedByteDanceTTSKey = byteDanceTTSKey
                ttsSaveState = .saved
                ttsTestState = .success
                try? await Task.sleep(for: .seconds(3))
                ttsSaveState = .idle
                ttsTestState = .idle
            } catch {
                if let prevAppId {
                    UserDefaults.standard.set(prevAppId, forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
                } else {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId)
                }
                if let prevKey {
                    UserDefaults.standard.set(prevKey, forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey)
                }
                ttsTestState = .failure(error.localizedDescription)
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
                let textTasks = tasks.filter(\.isTextAPI)
                if !textTasks.contains(where: { $0.key == selectedTaskKey }) {
                    selectedTaskKey = ""
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.cachedTaskKey)
                }
            } catch {
                availableTasks = []
            }
            isLoadingTasks = false
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
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

            // 至少需要一个修饰键（或者允许无修饰键的特殊键）
            let hasModifier = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if hasModifier || keyCode == UInt32(kVK_Space) {
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

    private func loadSettings() {
        deepSeekKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.deepSeekAPIKey) ?? ""
        savedDeepSeekKey = deepSeekKey
        dotKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.dotAPIKey) ?? ""
        savedDotKey = dotKey
        byteDanceTTSAppId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) ?? ""
        savedByteDanceTTSAppId = byteDanceTTSAppId
        byteDanceTTSKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) ?? ""
        savedByteDanceTTSKey = byteDanceTTSKey
        let engineRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ttsEngine) ?? ""
        ttsEngine = Constants.TTSEngine(rawValue: engineRaw) ?? .system
        ttsFallbackToSystem = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsFallbackToSystem) as? Bool
            ?? Constants.Defaults.ttsFallbackToSystem
        ttsVoice = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSVoice)
            ?? Constants.API.byteDanceTTSDefaultVoice
        pushInterval = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushInterval) as? Int
            ?? Constants.Defaults.pushIntervalMinutes
        pushOnlyLearning = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushOnlyLearning) as? Bool
            ?? Constants.Defaults.pushOnlyLearning
        enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples
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
        shortcutText = loadShortcutText()
        updateCacheSize()
    }

    private func updateCacheSize() {
        let counts = CacheService.shared.cacheCounts()
        cacheSizeText = "翻译 \(counts.translation) 条 / 音频 \(counts.tts) 条"
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
