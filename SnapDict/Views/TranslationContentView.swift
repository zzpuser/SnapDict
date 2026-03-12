import SwiftUI
import SwiftData
import AVFoundation

struct TranslationContentView: View {
    /// 每次变化时重置所有状态（由 UnifiedPanelView 在 shouldReset 时更新）
    let resetID: UUID
    /// 当前 Tab 是否激活（控制输入框焦点）
    let isActive: Bool
    /// 外部传入的初始查询（选中文字），使用后自动清空
    @Binding var initialQuery: String?
    /// 内容区显示状态变化回调（供 UnifiedPanelView 控制面板高度）
    var onContentChange: ((Bool) -> Void)?
    /// 上报实际内容高度（供 PanelManager 自适应窗口高度）
    var onContentHeightChange: ((CGFloat) -> Void)?

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
    @State private var sentenceResult: SentenceTranslationResult?
    @State private var currentInputType: InputType = .word
    @State private var shimmerPhase: CGFloat = 0

    // 流式中间状态
    @State private var partialWord: PartialWordResult?
    @State private var partialSentence: PartialSentenceResult?

    private let synthesizer = AVSpeechSynthesizer()

    @State private var contentHeight: CGFloat = 0

    @FocusState private var isInputFocused: Bool

    // 判断是否有内容显示（需要展开窗口）
    private var hasContent: Bool {
        isLoading || errorMessage != nil || result != nil || sentenceResult != nil
            || partialWord != nil || partialSentence != nil
    }

    /// 是否有任何骨架屏可见（主骨架屏或助记/例句骨架屏），用于控制闪烁动画
    private var isAnySkeletonVisible: Bool {
        if isLoading { return true }
        guard result != nil else { return false }
        let hasMnemonicData = result?.etymology != nil || result?.association != nil
        let hasExamples = !(result?.examples.isEmpty ?? true)
        return (isMnemonicLoading && !hasMnemonicData) || (isExamplesLoading && !hasExamples)
    }

    /// 骨架屏预估内容高度，用于在 onGeometryChange 触发前立即展开面板
    private var estimatedSkeletonContentHeight: CGFloat {
        var h: CGFloat = 106
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic { h += 99 }
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples { h += 98 }
        return h
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar - Spotlight style
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 22, weight: .light))

                TextField("输入单词、短句或中文...", text: $query)
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
                            skeletonView()
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
                        } else if currentInputType == .word, let result {
                            resultView(result)
                        } else if currentInputType == .word, let partial = partialWord {
                            partialResultView(partial)
                        } else if let sentenceResult {
                            SentenceTranslationView(
                                originalText: query,
                                result: sentenceResult,
                                inputType: currentInputType
                            )
                        } else if let partial = partialSentence {
                            partialSentenceView(partial)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        contentHeight = newHeight
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(.clear)
        .onChange(of: contentHeight) { _, newHeight in
            if hasContent {
                onContentHeightChange?(newHeight)
            }
        }
        .onChange(of: hasContent) { _, newValue in
            if newValue {
                if contentHeight <= 0 {
                    onContentHeightChange?(estimatedSkeletonContentHeight)
                }
            } else {
                contentHeight = 0
            }
            DispatchQueue.main.async {
                self.onContentChange?(newValue)
            }
        }
        .onChange(of: resetID) { _, _ in
            resetState()
            if isActive { isInputFocused = true }
            // 不在此触发 performTranslation，由 onChange(of: initialQuery) 统一处理
        }
        .onChange(of: initialQuery) { _, newValue in
            if let text = newValue, !text.isEmpty {
                query = text
                initialQuery = nil
                performTranslation()
            }
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
        .onChange(of: isAnySkeletonVisible) { _, visible in
            if visible {
                shimmerPhase = 0
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1
                }
            } else {
                shimmerPhase = 0
            }
        }
        .onAppear {
            if isActive {
                isInputFocused = true
            }
        }
    }

    // MARK: - Skeleton

    private func skeletonLine(width: CGFloat, height: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.tertiary)
            .frame(width: width, height: height)
    }

    private func withShimmer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        content()
            .overlay(
                GeometryReader { geo in
                    let shimmerWidth: CGFloat = 120
                    let totalTravel = geo.size.width + shimmerWidth
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.4), .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: shimmerWidth)
                    .offset(x: -shimmerWidth + totalTravel * shimmerPhase)
                }
            )
            .mask { content() }
    }

    @ViewBuilder
    private func skeletonView() -> some View {
        let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples

        withShimmer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    skeletonLine(width: 120, height: 22)
                    skeletonLine(width: 60, height: 15)
                    Spacer()
                    skeletonLine(width: 20, height: 20)
                }

                skeletonLine(width: 280)
                skeletonLine(width: 180)

                if enableMnemonic {
                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 4) {
                        skeletonLine(width: 14, height: 14)
                        skeletonLine(width: 30, height: 13)
                    }
                    skeletonLine(width: 240)
                    skeletonLine(width: 300)
                }

                if showExamples {
                    Divider()
                        .padding(.vertical, 4)

                    skeletonLine(width: 30, height: 13)
                    skeletonLine(width: 340)
                    skeletonLine(width: 260)
                }
            }
        }
    }

    /// 助记区域骨架屏（词根 + 联想占位）
    @ViewBuilder
    private func mnemonicSkeletonContent() -> some View {
        withShimmer {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    skeletonLine(width: 28, height: 12)
                    skeletonLine(width: 240)
                }
                VStack(alignment: .leading, spacing: 4) {
                    skeletonLine(width: 28, height: 12)
                    skeletonLine(width: 300)
                }
            }
        }
    }

    /// 例句区域骨架屏
    @ViewBuilder
    private func examplesSkeletonContent() -> some View {
        withShimmer {
            VStack(alignment: .leading, spacing: 8) {
                skeletonLine(width: 340)
                skeletonLine(width: 260)
            }
        }
    }

    // MARK: - Partial Result Views (流式)

    @ViewBuilder
    private func partialResultView(_ partial: PartialWordResult) -> some View {
        if partial.notFound {
            notFoundView(partial)
        } else {
        // 拼写纠正提示（流式阶段也显示）
        partialCorrectionBanner(partial)

        // Word + phonetic + speak/save buttons
        if let word = partial.word {
            HStack(alignment: .center) {
                Text(word)
                    .font(.system(size: 22, weight: .semibold))

                if let phonetic = partial.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    speakWord(word)
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
                    toggleSavePartialWord(partial)
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundStyle(isSaved ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(isSaved ? "取消收藏 (⌘D)" : "保存到生词本 (⌘D)")
                .keyboardShortcut("d", modifiers: .command)
            }
        } else {
            HStack {
                skeletonLine(width: 120, height: 22)
                skeletonLine(width: 60, height: 15)
                Spacer()
            }
        }

        // Translation（逐字流入）
        if let translation = partial.translation {
            Text(translation)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            withShimmer {
                VStack(alignment: .leading, spacing: 8) {
                    skeletonLine(width: 280)
                    skeletonLine(width: 180)
                }
            }
        }

        // Etymology（逐字流入）
        let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        let isPhrase = query.trimmingCharacters(in: .whitespacesAndNewlines).contains(" ")

        if enableMnemonic && !isPhrase {
            if partial.etymology != nil || partial.association != nil {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 12))
                        Text("助记")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    if let etymology = partial.etymology {
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

                    if let association = partial.association {
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
            } else if partial.translation != nil {
                // translation 已出现但 etymology 还没来，显示骨架
                Divider()
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 12))
                        Text("助记")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    mnemonicSkeletonContent()
                }
            }
        }

        // Examples
        let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples

        if showExamples {
            if !partial.examples.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12))
                        Text("例句")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(partial.examples, id: \.self) { example in
                        Text(example)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else if partial.translation != nil {
                // translation 已出现但 examples 还没来，显示骨架
                Divider()
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12))
                        Text("例句")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    examplesSkeletonContent()
                }
            }
        }
        } // else notFound
    }

    @ViewBuilder
    private func notFoundView(_ partial: PartialWordResult) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("未找到该词")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                if let suggestion = partial.suggestion, !suggestion.isEmpty {
                    Button {
                        query = suggestion
                        debounceTask?.cancel()
                        performTranslation()
                    } label: {
                        Text("查询 \(suggestion)")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func partialSentenceView(_ partial: PartialSentenceResult) -> some View {
        // 原文
        Text(query)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(3)

        // 译文（逐字流入）
        if let translation = partial.translation {
            Text(translation)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            withShimmer {
                VStack(alignment: .leading, spacing: 8) {
                    skeletonLine(width: 300)
                    skeletonLine(width: 220)
                }
            }
        }

        // 解析（逐字流入）
        let showAnalysis = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showAnalysis) as? Bool
            ?? Constants.Defaults.showAnalysis

        if showAnalysis {
            if let analysis = partial.analysis, !analysis.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 12))
                        Text(currentInputType == .chinese ? "用法说明" : "语法解析")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)

                    Text(analysis)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            } else if partial.translation != nil {
                Divider()
                    .padding(.vertical, 2)
                withShimmer {
                    VStack(alignment: .leading, spacing: 6) {
                        skeletonLine(width: 60, height: 13)
                        skeletonLine(width: 300)
                        skeletonLine(width: 240)
                    }
                }
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func resultView(_ result: TranslationResult) -> some View {
        // 拼写纠正提示
        correctionBanner(result)

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

    @ViewBuilder
    private func correctionBanner(_ result: TranslationResult) -> some View {
        if let originalInput = result.originalInput {
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 12))
                Text("已自动纠正: \"\(originalInput)\" → \"\(result.word)\"")
                    .font(.system(size: 13))
                Spacer()
                Button {
                    queryWithOriginalInput(originalInput)
                } label: {
                    Text("仍查询 \(originalInput)")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func partialCorrectionBanner(_ partial: PartialWordResult) -> some View {
        if let originalInput = partial.originalInput {
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 12))
                Text("已自动纠正: \"\(originalInput)\" → \"\(partial.word ?? "")\"")
                    .font(.system(size: 13))
                Spacer()
                Button {
                    queryWithOriginalInput(originalInput)
                } label: {
                    Text("仍查询 \(originalInput)")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func performTranslation(forceNoAutoCorrect: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let inputType = InputClassifier.classify(text)
        currentInputType = inputType

        isLoading = true
        errorMessage = nil
        result = nil
        sentenceResult = nil
        partialWord = nil
        partialSentence = nil
        isSaved = false
        isMnemonicLoading = false
        isExamplesLoading = false
        mnemonicError = nil
        examplesError = nil
        mnemonicTask?.cancel()
        examplesTask?.cancel()

        PanelManager.shared.updatePanelWidth(for: inputType)

        translationTask?.cancel()
        translationTask = Task {
            switch inputType {
            case .word:
                do {
                    for try await partial in DeepSeekService.shared.translateWordStreaming(text, forceNoAutoCorrect: forceNoAutoCorrect) {
                        guard !Task.isCancelled else { return }

                        if (partial.phonetic != nil || partial.notFound) && isLoading {
                            isLoading = false
                        }

                        if partial.isComplete {
                            if partial.notFound {
                                // notFound 保持在 partialWord 显示空状态，不转为 result
                                partialWord = partial
                            } else {
                                // 流式完成，转为正式 result
                                result = TranslationResult(
                                    word: partial.word ?? "",
                                    phonetic: partial.phonetic ?? "",
                                    translation: partial.translation ?? "",
                                    examples: partial.examples,
                                    originalInput: partial.originalInput,
                                    etymology: partial.etymology,
                                    association: partial.association
                                )
                                partialWord = nil
                                isSaved = WordBookManager.shared.isWordSaved(result!.word)
                                // 如果在流式过程中已收藏，用完整数据更新数据库
                                if isSaved {
                                    try? WordBookManager.shared.saveWord(from: result!)
                                }
                            }
                        } else {
                            partialWord = partial
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.partialWord = nil
                }

            case .sentence, .chinese:
                do {
                    for try await partial in DeepSeekService.shared.translateSentenceStreaming(text, inputType: inputType) {
                        guard !Task.isCancelled else { return }

                        if partial.translation != nil && isLoading {
                            isLoading = false
                        }

                        if partial.isComplete {
                            sentenceResult = SentenceTranslationResult(
                                translation: partial.translation ?? "",
                                analysis: partial.analysis
                            )
                            partialSentence = nil
                        } else {
                            partialSentence = partial
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.partialSentence = nil
                }
            }
        }
    }

    private func debounceAutoTranslate(_ text: String) {
        debounceTask?.cancel()
        if isLoading || isMnemonicLoading || isExamplesLoading || partialWord != nil || partialSentence != nil {
            translationTask?.cancel()
            mnemonicTask?.cancel()
            examplesTask?.cancel()
            isLoading = true
            isMnemonicLoading = false
            isExamplesLoading = false
            result = nil
            sentenceResult = nil
            partialWord = nil
            partialSentence = nil
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
        sentenceResult = nil
        partialWord = nil
        partialSentence = nil
        currentInputType = .word
        PanelManager.shared.updatePanelWidth(for: .word)
        errorMessage = nil
        mnemonicError = nil
        examplesError = nil
        isSaved = false
    }

    private func speakWord(_ word: String) {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            Task { await ByteDanceTTSService.shared.stop() }
            isSpeaking = false
            return
        }

        let engineRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ttsEngine) ?? ""
        let engine = Constants.TTSEngine(rawValue: engineRaw) ?? .system

        isSpeaking = true
        Task { @MainActor in
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

                if isMnemonicLoading && !hasMnemonicData {
                    mnemonicSkeletonContent()
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
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
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

                if isExamplesLoading && !hasExamples {
                    examplesSkeletonContent()
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

    private func queryWithOriginalInput(_ text: String) {
        // 1. 立即停止当前所有任务
        debounceTask?.cancel()
        translationTask?.cancel()
        mnemonicTask?.cancel()
        examplesTask?.cancel()

        // 2. 重置为骨架屏状态
        result = nil
        partialWord = nil
        partialSentence = nil
        sentenceResult = nil
        errorMessage = nil
        isMnemonicLoading = false
        isExamplesLoading = false
        mnemonicError = nil
        examplesError = nil
        isLoading = true
        isSaved = false

        // 3. 更新输入框文字（会触发 onChange → debounceAutoTranslate）
        query = text

        // 4. 在下一个 run loop 执行，确保在 onChange 的 debounce 之后
        //    取消 debounce 创建的任务，启动 forceNoAutoCorrect 翻译
        Task { @MainActor in
            debounceTask?.cancel()
            performTranslation(forceNoAutoCorrect: true)
        }
    }

    private func toggleSavePartialWord(_ partial: PartialWordResult) {
        let result = TranslationResult(
            word: partial.word ?? "",
            phonetic: partial.phonetic ?? "",
            translation: partial.translation ?? "",
            examples: partial.examples,
            originalInput: partial.originalInput,
            etymology: partial.etymology,
            association: partial.association
        )
        toggleSaveWord(result)
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
