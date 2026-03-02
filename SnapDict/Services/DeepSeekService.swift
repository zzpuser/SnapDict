import Foundation

@Observable
final class DeepSeekService: Sendable {
    static let shared = DeepSeekService()

    private init() {}

    // MARK: - 独立查询方法

    /// 只请求单词释义（不含助记和例句）
    func translateWord(_ text: String, skipCache: Bool = false, forceNoAutoCorrect: Bool = false) async throws -> TranslationResult {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let autoCorrect = forceNoAutoCorrect ? false :
            (UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.autoCorrect) as? Bool
                ?? Constants.Defaults.autoCorrect)

        if !skipCache, let cached = CacheService.shared.getCachedTranslation(for: normalizedText) {
            if !cached.word.isEmpty && !cached.phonetic.isEmpty && !cached.translation.isEmpty {
                return TranslationResult(
                    word: cached.word,
                    phonetic: cached.phonetic,
                    translation: cached.translation,
                    examples: [],
                    originalInput: cached.originalInput,
                    suggestedCorrection: cached.suggestedCorrection
                )
            }
        }

        let prompt: String
        if autoCorrect {
            prompt = """
            你是一个专业的英语词典。请翻译以下英文单词或短语，只返回 JSON 格式：
            {"word": "原词", "phonetic": "音标", "translation": "中文释义（简洁，包含词性）", "original_input": null}

            如果输入的英文单词或短语拼写有误，请自动纠正为正确拼写。word 填写纠正后的正确单词，original_input 填写用户的原始输入。如果拼写正确，original_input 为 null。
            如果输入的是中文，则翻译为英文，word 为英文翻译结果，original_input 为 null。
            phonetic 必须是字符串，如果无法提供音标则返回空字符串 ""。
            只返回 JSON，不要返回其他内容。

            输入：\(text)
            """
        } else {
            prompt = """
            你是一个专业的英语词典。请翻译以下英文单词或短语，只返回 JSON 格式：
            {"word": "原词", "phonetic": "音标", "translation": "中文释义（简洁，包含词性）", "suggested_correction": null}

            不要自动纠正拼写。word 字段始终填写用户的原始输入。如果你发现拼写可能有误，suggested_correction 字段填写你建议的正确拼写；如果拼写正确，suggested_correction 为 null。按用户原始输入进行翻译。
            如果输入的是中文，则翻译为英文，word 为英文翻译结果，suggested_correction 为 null。
            phonetic 必须是字符串，如果无法提供音标则返回空字符串 ""。
            只返回 JSON，不要返回其他内容。

            输入：\(text)
            """
        }

        let cleaned = try await callAPI(prompt: prompt)

        guard let resultData = cleaned.data(using: .utf8) else {
            throw TranslationError.parseError
        }

        struct WordResult: Codable {
            let word: String
            let phonetic: String?
            let translation: String
            let originalInput: String?
            let suggestedCorrection: String?
            enum CodingKeys: String, CodingKey {
                case word, phonetic, translation
                case originalInput = "original_input"
                case suggestedCorrection = "suggested_correction"
            }
        }

        let wordResult = try JSONDecoder().decode(WordResult.self, from: resultData)
        let translationResult = TranslationResult(
            word: wordResult.word,
            phonetic: wordResult.phonetic ?? "",
            translation: wordResult.translation,
            examples: [],
            originalInput: wordResult.originalInput,
            suggestedCorrection: wordResult.suggestedCorrection
        )

        CacheService.shared.cacheTranslation(translationResult)
        return translationResult
    }

    /// 获取助记信息（词根词缀 + 联想记忆）
    func fetchMnemonic(_ word: String, skipCache: Bool = false) async throws -> (etymology: String?, association: String?) {
        // 短语不提供词根分析
        if word.contains(" ") {
            return (nil, nil)
        }

        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 缓存检查：etymology 非 nil 即命中
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

        // 缓存检查：examples 非空即命中
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

    // MARK: - Private

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

        return content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
