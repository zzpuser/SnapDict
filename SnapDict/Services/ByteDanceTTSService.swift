import Foundation

enum TTSError: LocalizedError {
    case notConfigured
    case requestFailed(statusCode: Int)
    case apiError(String)
    case emptyAudio
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置豆包语音 App ID 或 Access Key，请在设置中填写"
        case .requestFailed(let code):
            return "请求失败 (HTTP \(code))"
        case .apiError(let message):
            return "语音合成错误: \(message)"
        case .emptyAudio:
            return "音频数据为空"
        case .invalidResponse:
            return "响应格式无效"
        }
    }
}

@Observable
final class ByteDanceTTSService: Sendable {
    static let shared = ByteDanceTTSService()
    private init() {}

    /// 获取音频数据（优先缓存），返回 MP3 Data
    func fetchAudio(text: String, skipCache: Bool = false) async throws -> Data {
        let appId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) ?? ""
        let accessKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) ?? ""
        guard !appId.isEmpty, !accessKey.isEmpty else {
            throw TTSError.notConfigured
        }

        let speaker = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSVoice)
            ?? Constants.API.byteDanceTTSDefaultVoice

        let cacheKey = "\(speaker):\(text)"

        // 检查缓存
        if !skipCache, let cached = CacheService.shared.getCachedAudio(for: cacheKey) {
            return cached
        }

        // SSE 流式获取音频
        let audioData = try await fetchFromAPI(
            text: text,
            appId: appId,
            accessKey: accessKey,
            speaker: speaker
        )

        // 缓存结果
        CacheService.shared.cacheAudio(audioData, for: cacheKey)

        return audioData
    }

    // MARK: - Private

    private func fetchFromAPI(
        text: String,
        appId: String,
        accessKey: String,
        speaker: String
    ) async throws -> Data {
        let url = URL(string: Constants.API.byteDanceTTSEndpoint)!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-Id")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(Constants.API.byteDanceTTSResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")

        let body: [String: Any] = [
            "user": ["uid": "snapdict_user"],
            "req_params": [
                "text": text,
                "speaker": speaker,
                "additions": "{\"disable_markdown_filter\":true,\"enable_language_detector\":true}",
                "audio_params": [
                    "format": "mp3",
                    "sample_rate": 24000,
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TTSError.requestFailed(statusCode: httpResponse.statusCode)
        }

        var audioBuffer = Data()

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5))

            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let code = json["code"] as? Int else {
                continue
            }

            // 非 0 且非 20000000 视为错误
            if code != 0 && code != 20_000_000 {
                let message = json["message"] as? String ?? "未知错误"
                throw TTSError.apiError(message)
            }

            // 解码 base64 音频片段
            if let base64String = json["data"] as? String,
               let chunk = Data(base64Encoded: base64String) {
                audioBuffer.append(chunk)
            }

            // 传输完成
            if code == 20_000_000 {
                break
            }
        }

        guard !audioBuffer.isEmpty else {
            throw TTSError.emptyAudio
        }

        return audioBuffer
    }
}
