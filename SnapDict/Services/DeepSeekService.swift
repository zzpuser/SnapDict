import Foundation
import PartialJSON

@Observable
final class DeepSeekService: Sendable {
    static let shared = DeepSeekService()

    private init() {}

    // MARK: - Streaming Translation

    /// 流式翻译单词，逐字返回部分结果
    func translateWordStreaming(
        _ text: String,
        skipCache: Bool = false,
        forceNoAutoCorrect: Bool = false
    ) -> AsyncThrowingStream<PartialWordResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
                        ?? Constants.Defaults.enableMnemonic
                    let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
                        ?? Constants.Defaults.showExamples
                    let isPhrase = text.trimmingCharacters(in: .whitespacesAndNewlines).contains(" ")

                    // 缓存检查：只有所有需要的字段都有时才命中
                    if !skipCache, let cached = CacheService.shared.getCachedTranslation(for: normalizedText) {
                        let mnemonicReady = !enableMnemonic || isPhrase || cached.etymology != nil
                        let examplesReady = !showExamples || !cached.examples.isEmpty
                        if !cached.word.isEmpty && !cached.phonetic.isEmpty && !cached.translation.isEmpty
                            && mnemonicReady && examplesReady {
                            continuation.yield(PartialWordResult(
                                word: cached.word,
                                phonetic: cached.phonetic,
                                translation: cached.translation,
                                originalInput: nil,
                                etymology: cached.etymology,
                                association: cached.association,
                                examples: cached.examples,
                                isComplete: true
                            ))
                            continuation.finish()
                            return
                        }
                    }

                    let prompt = buildWordPrompt(
                        text: text,
                        forceNoAutoCorrect: forceNoAutoCorrect,
                        enableMnemonic: enableMnemonic && !isPhrase,
                        showExamples: showExamples
                    )

                    var lastPartial = PartialWordResult()

                    for try await accumulated in callAPIStreaming(prompt: prompt) {
                        try Task.checkCancellation()
                        let cleaned = cleanContent(accumulated)
                        guard let dict = try? PartialJSON.parse(cleaned, options: .all) as? [String: Any] else {
                            continue
                        }

                        var partial = PartialWordResult()

                        // word 从输入文本推导，不从 API
                        let inputWord = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        partial.word = inputWord

                        if !forceNoAutoCorrect {
                            if let correctedWord = dict["corrected_word"] as? String {
                                partial.word = correctedWord
                                partial.originalInput = inputWord
                            }
                        }

                        // 检测 not_found（仅 forceNoAutoCorrect 模式）
                        if forceNoAutoCorrect {
                            if let nf = dict["not_found"] as? Bool, nf {
                                partial.notFound = true
                                partial.suggestion = dict["suggestion"] as? String
                                if !partialEqual(lastPartial, partial) {
                                    continuation.yield(partial)
                                    lastPartial = partial
                                }
                                continue
                            }
                        }

                        partial.phonetic = dict["phonetic"] as? String
                        partial.translation = dict["translation"] as? String
                        partial.etymology = dict["etymology"] as? String
                        partial.association = dict["association"] as? String
                        if let examples = dict["examples"] as? [Any] {
                            partial.examples = examples.compactMap { $0 as? String }
                        }

                        // 只在有变化时 yield
                        if !partialEqual(lastPartial, partial) {
                            continuation.yield(partial)
                            lastPartial = partial
                        }
                    }

                    // 流结束，解码完整结果并缓存
                    try Task.checkCancellation()
                    var completePartial = lastPartial
                    completePartial.isComplete = true
                    continuation.yield(completePartial)

                    // 缓存完整结果（notFound 不缓存）
                    if let word = lastPartial.word, !word.isEmpty, !lastPartial.notFound {
                        let fullResult = TranslationResult(
                            word: word,
                            phonetic: lastPartial.phonetic ?? "",
                            translation: lastPartial.translation ?? "",
                            examples: lastPartial.examples,
                            originalInput: nil,
                            etymology: lastPartial.etymology,
                            association: lastPartial.association
                        )
                        CacheService.shared.cacheTranslation(fullResult)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 流式翻译短句/中文
    func translateSentenceStreaming(
        _ text: String,
        inputType: InputType,
        skipCache: Bool = false
    ) -> AsyncThrowingStream<PartialSentenceResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let cacheKey = "s:" + normalizedText

                    if !skipCache, let cached = CacheService.shared.getCachedSentenceTranslation(for: cacheKey) {
                        continuation.yield(PartialSentenceResult(
                            translation: cached.translation,
                            analysis: cached.analysis,
                            isComplete: true
                        ))
                        continuation.finish()
                        return
                    }

                    let prompt = buildSentencePrompt(text: text, inputType: inputType)

                    var lastPartial = PartialSentenceResult()

                    for try await accumulated in callAPIStreaming(prompt: prompt) {
                        try Task.checkCancellation()
                        let cleaned = cleanContent(accumulated)
                        guard let dict = try? PartialJSON.parse(cleaned, options: .all) as? [String: Any] else {
                            continue
                        }

                        var partial = PartialSentenceResult()
                        partial.translation = dict["translation"] as? String
                        partial.analysis = dict["analysis"] as? String

                        if partial.translation != lastPartial.translation || partial.analysis != lastPartial.analysis {
                            continuation.yield(partial)
                            lastPartial = partial
                        }
                    }

                    try Task.checkCancellation()
                    var completePartial = lastPartial
                    completePartial.isComplete = true
                    continuation.yield(completePartial)

                    // 缓存
                    if let translation = lastPartial.translation {
                        let fullResult = SentenceTranslationResult(
                            translation: translation,
                            analysis: lastPartial.analysis
                        )
                        CacheService.shared.cacheSentenceTranslation(fullResult, for: cacheKey)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - API 测试

    /// 简单 API 连通性测试（供设置页使用）
    func testAPI() async throws {
        let prompt = """
        你是一个专业的英语词典。请翻译以下英文单词，只返回 JSON 格式：
        {"word": "hello", "phonetic": "/həˈloʊ/", "translation": "int. 你好"}
        只返回 JSON，不要返回其他内容。
        输入：hello
        """
        _ = try await callAPI(prompt: prompt)
    }

    // MARK: - 独立查询方法（供刷新按钮使用）

    /// 获取助记信息（词根词缀 + 联想记忆）
    func fetchMnemonic(_ word: String, skipCache: Bool = false) async throws -> (etymology: String?, association: String?) {
        if word.contains(" ") {
            return (nil, nil)
        }

        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if !skipCache, let cached = CacheService.shared.getCachedTranslation(for: normalizedWord),
           cached.etymology != nil {
            return (cached.etymology, cached.association)
        }

        let prompt = """
        你是一个专业的英语词汇助记专家。请为以下英文单词提供词根词缀分析和联想记忆法，只返回 JSON 格式：
        {"etymology": "词根词缀拆解（如 un- 不 + break 打破 + -able 能…的）", "association": "一句简短的联想记忆法"}

        只返回 JSON，不要返回其他内容。

        单词：\(word)
        """

        let cleaned = try await callAPI(prompt: prompt)

        guard let resultData = cleaned.data(using: .utf8) else {
            throw TranslationError.parseError
        }

        struct MnemonicResult: Codable {
            let etymology: String?
            let association: String?
        }

        let mnemonicResult = try JSONDecoder().decode(MnemonicResult.self, from: resultData)
        CacheService.shared.updateCachedMnemonic(for: normalizedWord, etymology: mnemonicResult.etymology, association: mnemonicResult.association)
        return (mnemonicResult.etymology, mnemonicResult.association)
    }

    /// 获取例句
    func fetchExamples(_ word: String, translation: String, skipCache: Bool = false) async throws -> [String] {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if !skipCache, let cached = CacheService.shared.getCachedTranslation(for: normalizedWord),
           !cached.examples.isEmpty {
            return cached.examples
        }

        let prompt = """
        你是一个专业的英语词典。请为以下英文单词提供 2 个地道的英文例句，只返回 JSON 格式：
        {"examples": ["例句1（英文）", "例句2（英文）"]}

        单词：\(word)
        中文释义：\(translation)
        只返回 JSON，不要返回其他内容。
        """

        let cleaned = try await callAPI(prompt: prompt)

        guard let resultData = cleaned.data(using: .utf8) else {
            throw TranslationError.parseError
        }

        struct ExamplesResult: Codable {
            let examples: [String]
        }

        let examplesResult = try JSONDecoder().decode(ExamplesResult.self, from: resultData)
        CacheService.shared.updateCachedExamples(for: normalizedWord, examples: examplesResult.examples)
        return examplesResult.examples
    }

    // MARK: - Prompt Construction

    private func buildWordPrompt(text: String, forceNoAutoCorrect: Bool, enableMnemonic: Bool, showExamples: Bool) -> String {
        // 构建 JSON 模板字段（拼写纠正字段排第一，流式最先到达）
        var fields: [String] = []

        if !forceNoAutoCorrect {
            fields.append("\"corrected_word\": null")
        }

        fields.append("\"phonetic\": \"音标\"")
        fields.append("\"translation\": \"中文释义（简洁，包含词性）\"")

        if enableMnemonic {
            fields.append("\"etymology\": \"词根词缀拆解\"")
            fields.append("\"association\": \"联想记忆法\"")
        }

        if showExamples {
            fields.append("\"examples\": [\"例句1\", \"例句2\"]")
        }

        let jsonTemplate = "{\(fields.joined(separator: ", "))}"

        var instructions = "你是一个专业的英语词典。请翻译以下英文单词，严格按以下 JSON 格式返回：\n\(jsonTemplate)\n\n"

        if !forceNoAutoCorrect {
            instructions += """
            不要返回 word 字段。如果输入拼写有误，corrected_word 填写纠正后的正确拼写；如果拼写正确，corrected_word 为 null。按纠正后的词进行翻译。
            如果输入的是中文，则翻译为英文，corrected_word 填写英文翻译结果。
            """
        } else {
            instructions += """
            不要返回 word 字段。不要自动纠正拼写。
            如果输入不是有意义的英文单词或短语（如拼写错误、乱码、无意义组合），只返回 {"not_found": true, "suggestion": "你认为用户想输入的正确内容"}，不要编造释义。
            如果是有意义的英文单词或短语，按正常格式返回翻译结果。
            如果输入的是中文，则翻译为英文。
            """
        }

        instructions += "\nphonetic 必须是字符串，如果无法提供音标则返回空字符串 \"\"。"
        instructions += "\n只返回 JSON，不要返回其他内容。"
        instructions += "\n\n输入：\(text)"

        return instructions
    }

    private func buildSentencePrompt(text: String, inputType: InputType) -> String {
        let showAnalysis = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showAnalysis) as? Bool
            ?? Constants.Defaults.showAnalysis

        switch inputType {
        case .sentence:
            if showAnalysis {
                return """
                你是一个专业的英语翻译助手。请翻译以下英文短句/段落，只返回 JSON 格式：
                {"translation": "中文翻译（自然流畅）", "analysis": "简要语法/用法解析（2-3句话，点出关键语法点或地道用法）"}

                只返回 JSON，不要返回其他内容。

                输入：\(text)
                """
            } else {
                return """
                你是一个专业的英语翻译助手。请翻译以下英文短句/段落，只返回 JSON 格式：
                {"translation": "中文翻译（自然流畅）"}

                只返回 JSON，不要返回其他内容。

                输入：\(text)
                """
            }
        case .chinese:
            if showAnalysis {
                return """
                你是一个专业的英语翻译助手。请将以下中文翻译为英文，只返回 JSON 格式：
                {"translation": "英文翻译（自然地道）", "analysis": "简要用法说明（解释翻译选择或提供替代表达）"}

                只返回 JSON，不要返回其他内容。

                输入：\(text)
                """
            } else {
                return """
                你是一个专业的英语翻译助手。请将以下中文翻译为英文，只返回 JSON 格式：
                {"translation": "英文翻译（自然地道）"}

                只返回 JSON，不要返回其他内容。

                输入：\(text)
                """
            }
        case .word:
            return ""
        }
    }

    // MARK: - Private

    /// 流式 SSE 调用，每次 yield 累积的完整文本
    private func callAPIStreaming(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    guard let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.deepSeekAPIKey),
                          !apiKey.isEmpty else {
                        throw TranslationError.noAPIKey
                    }

                    let requestBody: [String: Any] = [
                        "model": Constants.API.deepSeekModel,
                        "temperature": 0.1,
                        "stream": true,
                        "messages": [
                            ["role": "user", "content": prompt]
                        ]
                    ]

                    guard let url = URL(string: Constants.API.deepSeekEndpoint) else {
                        throw TranslationError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    request.timeoutInterval = 30

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TranslationError.invalidResponse
                    }
                    guard httpResponse.statusCode == 200 else {
                        throw TranslationError.apiError(statusCode: httpResponse.statusCode)
                    }

                    var accumulated = ""

                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        accumulated += content
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 非流式 API 调用（供 fetchMnemonic/fetchExamples 使用）
    private func callAPI(prompt: String) async throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.deepSeekAPIKey),
              !apiKey.isEmpty else {
            throw TranslationError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": Constants.API.deepSeekModel,
            "temperature": 0.1,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let url = URL(string: Constants.API.deepSeekEndpoint) else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(statusCode: httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.parseError
        }

        return cleanContent(content)
    }

    /// 清理 markdown 代码块标记
    private func cleanContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 比较两个 PartialWordResult 是否相同（避免重复 yield）
    private func partialEqual(_ a: PartialWordResult, _ b: PartialWordResult) -> Bool {
        a.word == b.word &&
        a.phonetic == b.phonetic &&
        a.translation == b.translation &&
        a.originalInput == b.originalInput &&
        a.etymology == b.etymology &&
        a.association == b.association &&
        a.examples == b.examples &&
        a.notFound == b.notFound &&
        a.suggestion == b.suggestion
    }
}

enum TranslationError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "请先在设置中配置 DeepSeek API Key"
        case .invalidURL: "无效的 API 地址"
        case .invalidResponse: "服务器响应异常"
        case .apiError(let code): "API 错误 (\(code))"
        case .parseError: "解析翻译结果失败"
        }
    }
}
