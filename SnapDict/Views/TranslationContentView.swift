import SwiftUI
import SwiftData
import AVFoundation

struct TranslationContentView: View {
    /// 每次变化时重置所有状态（由 UnifiedPanelView 在 shouldReset 时更新）
    let resetID: UUID
    /// 当前 Tab 是否激活（控制输入框焦点）
    let isActive: Bool
    /// 内容区显示状态变化回调（供 UnifiedPanelView 控制面板高度）
    var onContentChange: ((Bool) -> Void)?

    @State private var query = ""
    @State private var result: TranslationResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSaved = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var translationTask: Task<Void, Never>?
    @State private var isSpeaking = false
    @State private var isMnemonicLoading = false
    @State private var isExamplesLoading = false
    @State private var mnemonicError: String?
    @State private var examplesError: String?
    @State private var mnemonicTask: Task<Void, Never>?
    @State private var examplesTask: Task<Void, Never>?

    private let synthesizer = AVSpeechSynthesizer()

    @FocusState private var isInputFocused: Bool

    // 判断是否有内容显示（需要展开窗口）
    private var hasContent: Bool {
        isLoading || errorMessage != nil || result != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar - Spotlight style
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 22, weight: .light))

                TextField("输入单词或短语...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
                    .focused($isInputFocused)
                    .onSubmit {
                        debounceTask?.cancel()
                        performTranslation()
                    }
                    .onChange(of: query) { _, newValue in
                        if newValue.isEmpty {
                            resetState()
                        } else {
                            debounceAutoTranslate(newValue)
                        }
                    }

                if !query.isEmpty {
                    Button {
                        resetState()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if hasContent {
                Divider()
                    .padding(.horizontal, 8)

                // Content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if isLoading {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                    Text("翻译中...")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.top, 40)
                        } else if let error = errorMessage {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                Spacer()
                            }
                            .padding(.top, 40)
                        } else if let result {
                            resultView(result)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 420)
        .background(.clear)
        .onChange(of: hasContent) { _, newValue in
            DispatchQueue.main.async {
                self.onContentChange?(newValue)
            }
        }
        .onChange(of: resetID) { _, _ in
            resetState()
            if isActive { isInputFocused = true }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                isInputFocused = true
                DispatchQueue.main.async {
                    self.onContentChange?(self.hasContent)
                }
            }
        }
        .onKeyPress(.escape) {
            if query.isEmpty {
                return .ignored
            }
            resetState()
            return .handled
        }
        .onAppear {
            if isActive {
                isInputFocused = true
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: TranslationResult) -> some View {
        // 拼写纠正提醒
        if let correctedFrom = result.correctedFrom {
            HStack(spacing: 4) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 12))
                Text("已自动纠正: \"\(correctedFrom)\" → \"\(result.word)\"")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
        }

        // Word + phonetic + save button
        HStack(alignment: .center) {
            Text(result.word)
                .font(.system(size: 22, weight: .semibold))

            if !result.phonetic.isEmpty {
                Text(result.phonetic)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button {
                speakWord(result.word)
            } label: {
                Image(systemName: isSpeaking ? "waveform" : "speaker.wave.2")
                    .font(.system(size: 16))
                    .foregroundStyle(isSpeaking ? Color.accentColor : .secondary)
                    .symbolEffect(.variableColor, isActive: isSpeaking)
            }
            .buttonStyle(.plain)
            .help("朗读 (⌘S)")
            .keyboardShortcut("s", modifiers: .command)

            Spacer()

            Button {
                toggleSaveWord(result)
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundStyle(isSaved ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isSaved ? "取消收藏 (⌘D)" : "保存到生词本 (⌘D)")
            .keyboardShortcut("d", modifiers: .command)
        }

        // Translation
        Text(result.translation)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .textSelection(.enabled)

        // Mnemonic (助记：词根 + 联想)
        mnemonicSection(result)

        // Examples (例句)
        examplesSection(result)
    }

    private func performTranslation() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        result = nil
        isSaved = false
        isMnemonicLoading = false
        isExamplesLoading = false
        mnemonicError = nil
        examplesError = nil
        mnemonicTask?.cancel()
        examplesTask?.cancel()

        translationTask = Task {
            // 阶段 1：查词
            do {
                let translationResult = try await DeepSeekService.shared.translateWord(text)
                guard !Task.isCancelled else { return }
                self.result = translationResult
                self.isLoading = false
                self.isSaved = WordBookManager.shared.isWordSaved(translationResult.word)

                // 阶段 2：并行获取助记和例句
                let correctedWord = translationResult.word
                let translation = translationResult.translation

                let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
                    ?? Constants.Defaults.enableMnemonic
                let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
                    ?? Constants.Defaults.showExamples

                if enableMnemonic {
                    mnemonicTask = Task {
                        isMnemonicLoading = true
                        mnemonicError = nil
                        do {
                            let mnemonic = try await DeepSeekService.shared.fetchMnemonic(correctedWord)
                            guard !Task.isCancelled else { return }
                            self.result?.etymology = mnemonic.etymology
                            self.result?.association = mnemonic.association
                        } catch {
                            guard !Task.isCancelled else { return }
                            self.mnemonicError = error.localizedDescription
                        }
                        self.isMnemonicLoading = false
                    }
                }

                if showExamples {
                    examplesTask = Task {
                        isExamplesLoading = true
                        examplesError = nil
                        do {
                            let examples = try await DeepSeekService.shared.fetchExamples(correctedWord, translation: translation)
                            guard !Task.isCancelled else { return }
                            self.result?.examples = examples
                        } catch {
                            guard !Task.isCancelled else { return }
                            self.examplesError = error.localizedDescription
                        }
                        self.isExamplesLoading = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func debounceAutoTranslate(_ text: String) {
        // 取消防抖任务
        debounceTask?.cancel()
        // 若有正在进行的查询，立即中断并清除结果，等待用户输入完成后重新查询
        if isLoading || isMnemonicLoading || isExamplesLoading {
            translationTask?.cancel()
            mnemonicTask?.cancel()
            examplesTask?.cancel()
            isLoading = false
            isMnemonicLoading = false
            isExamplesLoading = false
            result = nil
            errorMessage = nil
            mnemonicError = nil
            examplesError = nil
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            performTranslation()
        }
    }

    private func resetState() {
        debounceTask?.cancel()
        translationTask?.cancel()
        mnemonicTask?.cancel()
        examplesTask?.cancel()
        isLoading = false
        isMnemonicLoading = false
        isExamplesLoading = false
        query = ""
        result = nil
        errorMessage = nil
        mnemonicError = nil
        examplesError = nil
        isSaved = false
    }

    private func speakWord(_ word: String) {
        // 若正在播放则停止
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            Task { await ByteDanceTTSService.shared.stop() }
            isSpeaking = false
            return
        }

        let engineRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ttsEngine) ?? ""
        let engine = Constants.TTSEngine(rawValue: engineRaw) ?? .system

        isSpeaking = true
        Task {
            defer { isSpeaking = false }
            switch engine {
            case .system:
                let utterance = AVSpeechUtterance(string: word)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.45
                synthesizer.speak(utterance)
                while synthesizer.isSpeaking {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            case .byteDance:
                do {
                    try await ByteDanceTTSService.shared.speak(word)
                } catch {
                    let fallback = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsFallbackToSystem) as? Bool
                        ?? Constants.Defaults.ttsFallbackToSystem
                    if fallback {
                        let utterance = AVSpeechUtterance(string: word)
                        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                        utterance.rate = 0.45
                        synthesizer.speak(utterance)
                        while synthesizer.isSpeaking {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mnemonicSection(_ result: TranslationResult) -> some View {
        let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        let hasMnemonicData = result.etymology != nil || result.association != nil

        if enableMnemonic {
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12))
                    Text("助记")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if isMnemonicLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else if hasMnemonicData {
                        Button { refreshMnemonic() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if mnemonicError != nil {
                        Button { refreshMnemonic() } label: {
                            Text("重试")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { refreshMnemonic() } label: {
                            Text("生成")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = mnemonicError, !hasMnemonicData {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Group {
                    if let etymology = result.etymology {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("词根")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Text(etymology)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    if let association = result.association {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("联想")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Text(association)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: hasMnemonicData)
            }
        }
    }

    @ViewBuilder
    private func examplesSection(_ result: TranslationResult) -> some View {
        let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples
        let hasExamples = !result.examples.isEmpty

        if showExamples {
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("例句")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if isExamplesLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else if hasExamples {
                        Button { refreshExamples() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if examplesError != nil {
                        Button { refreshExamples() } label: {
                            Text("重试")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { refreshExamples() } label: {
                            Text("生成")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = examplesError, !hasExamples {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Group {
                    ForEach(result.examples, id: \.self) { example in
                        Text(example)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: hasExamples)
            }
        }
    }

    private func refreshMnemonic() {
        guard let result = result, !isMnemonicLoading else { return }

        mnemonicTask?.cancel()
        mnemonicTask = Task {
            isMnemonicLoading = true
            mnemonicError = nil
            do {
                let mnemonic = try await DeepSeekService.shared.fetchMnemonic(result.word, skipCache: true)
                guard !Task.isCancelled else { return }
                self.result?.etymology = mnemonic.etymology
                self.result?.association = mnemonic.association
            } catch {
                guard !Task.isCancelled else { return }
                self.mnemonicError = error.localizedDescription
            }
            self.isMnemonicLoading = false
        }
    }

    private func refreshExamples() {
        guard let result = result, !isExamplesLoading else { return }

        examplesTask?.cancel()
        examplesTask = Task {
            isExamplesLoading = true
            examplesError = nil
            do {
                let examples = try await DeepSeekService.shared.fetchExamples(result.word, translation: result.translation, skipCache: true)
                guard !Task.isCancelled else { return }
                self.result?.examples = examples
            } catch {
                guard !Task.isCancelled else { return }
                self.examplesError = error.localizedDescription
            }
            self.isExamplesLoading = false
        }
    }

    private func toggleSaveWord(_ result: TranslationResult) {
        do {
            if isSaved {
                try WordBookManager.shared.deleteWord(byName: result.word)
                isSaved = false
            } else {
                try WordBookManager.shared.saveWord(from: result)
                isSaved = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
