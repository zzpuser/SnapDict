import Foundation
import AVFoundation

/// 豆包 TTS 服务，调用字节跳动语音合成 V3 HTTP API
actor ByteDanceTTSService {
    static let shared = ByteDanceTTSService()

    private var player: AVAudioPlayer?

    private init() {}

    /// 合成并播放语音，返回时已播放完毕或抛出错误
    func speak(_ text: String) async throws {
        let appId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAppId) ?? ""
        let accessKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSAPIKey) ?? ""
        guard !appId.isEmpty, !accessKey.isEmpty else {
            throw TTSError.missingAPIKey
        }

        let speaker = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.byteDanceTTSVoice)
            ?? Constants.API.byteDanceTTSDefaultVoice
        let cacheKey = "\(speaker):\(text)"

        // 查缓存
        if let cachedAudio = CacheService.shared.getCachedAudio(for: cacheKey) {
            try await playAudio(cachedAudio)
            return
        }

        let audioData = try await fetchAudio(text: text, appId: appId, accessKey: accessKey, speaker: speaker)
        // 写缓存
        CacheService.shared.cacheAudio(audioData, for: cacheKey)
        try await playAudio(audioData)
    }

    // MARK: - Private

    private func fetchAudio(text: String, appId: String, accessKey: String, speaker: String) async throws -> Data {
        guard let url = URL(string: Constants.API.byteDanceTTSEndpoint) else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-Id")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(Constants.API.byteDanceTTSResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "req_params": [
                "text": text,
                "speaker": speaker,
                "additions": "{\"disable_markdown_filter\":true,\"enable_language_detector\":true,\"enable_latex_tn\":true,\"disable_default_bit_rate\":true,\"max_length_to_filter_parenthesis\":0,\"cache_config\":{\"text_type\":1,\"use_cache\":true}}",
                "audio_params": [
                    "format": "mp3",
                    "sample_rate": 24000
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["message"] as? String } ?? "HTTP \(httpResponse.statusCode)"
            throw TTSError.apiError(message)
        }

        // V3 接口返回 NDJSON（多个 JSON 对象换行拼接），每个对象的 data 字段是 base64 音频分片
        guard let responseText = String(data: data, encoding: .utf8) else {
            throw TTSError.parseError
        }

        var audioData = Data()
        let lines = responseText.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if let code = json["code"] as? Int, code != 0, code != 20000000 {
                let message = json["message"] as? String ?? "错误码 \(code)"
                throw TTSError.apiError(message)
            }
            if let part = json["data"] as? String, !part.isEmpty,
               let partData = Data(base64Encoded: part) {
                audioData.append(partData)
            }
        }

        guard !audioData.isEmpty else {
            throw TTSError.parseError
        }
        return audioData
    }

    private func playAudio(_ data: Data) async throws {
        player?.stop()

        let audioPlayer = try AVAudioPlayer(data: data)
        self.player = audioPlayer
        audioPlayer.play()

        while audioPlayer.isPlaying {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// 停止当前播放
    func stop() {
        player?.stop()
        player = nil
    }

    enum TTSError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse
        case parseError
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "请先在设置中填写豆包 TTS App ID 和 Access Key"
            case .invalidURL: return "无效的 API 地址"
            case .invalidResponse: return "无效的服务器响应"
            case .parseError: return "解析音频数据失败"
            case .apiError(let msg): return "API 错误: \(msg)"
            }
        }
    }
}
