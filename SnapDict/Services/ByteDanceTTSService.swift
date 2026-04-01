import Foundation
@preconcurrency import AVFoundation

/// 豆包 TTS 服务，调用字节跳动语音合成 V3 SSE API
actor ByteDanceTTSService {
    static let shared = ByteDanceTTSService()

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

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
            "user": [
                "uid": "snapdict_user"
            ],
            "req_params": [
                "text": text,
                "speaker": speaker,
                "additions": "{\"disable_markdown_filter\":true,\"enable_language_detector\":true}",
                "audio_params": [
                    "format": "mp3",
                    "sample_rate": 24000,
                    "loudness_rate": 100
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 使用 bytes(for:) 流式读取 SSE 响应
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TTSError.apiError("HTTP \(httpResponse.statusCode)")
        }

        var audioData = Data()

        // 逐行解析 SSE 事件，每个 data: 行立即处理
        for try await line in bytes.lines {
            // SSE 格式: "data: {json}" 或 "data:{json}"
            let dataPrefix = "data:"
            guard line.hasPrefix(dataPrefix) else { continue }

            let jsonStr = String(line.dropFirst(dataPrefix.count)).trimmingCharacters(in: .whitespaces)
            guard !jsonStr.isEmpty,
                  let lineData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let code = json["code"] as? Int ?? 0
            if code != 0 && code != 20000000 {
                let message = json["message"] as? String ?? "错误码 \(code)"
                throw TTSError.apiError(message)
            }
            if let part = json["data"] as? String, !part.isEmpty,
               let partData = Data(base64Encoded: part) {
                audioData.append(partData)
            }
            if code == 20000000 {
                break
            }
        }

        guard !audioData.isEmpty else {
            throw TTSError.parseError("未收到音频数据")
        }
        return audioData
    }

    private func playAudio(_ data: Data) async throws {
        stopEngine()

        // AVAudioFile 需要文件路径，写临时文件
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("snapdict_tts.mp3")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let audioFile = try AVAudioFile(forReading: tempURL)
        let format = audioFile.processingFormat

        // 读取用户设置的线性音量比例（0.5~3.0），转换为 dB 增益
        let volumeScale = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsVolume) as? Float
            ?? Constants.Defaults.ttsVolume
        let gainDB = 20.0 * log10(volumeScale)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eqNode = AVAudioUnitEQ()
        // 全频段整体增益
        eqNode.globalGain = gainDB

        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine
        self.playerNode = playerNode

        // 计算音频时长
        let duration = Double(audioFile.length) / format.sampleRate

        await playerNode.scheduleFile(audioFile, at: nil)
        playerNode.play()

        // 用 Task.sleep 等待音频播放完毕，支持 Task 取消
        try await Task.sleep(for: .milliseconds(Int(duration * 1000) + 50))

        stopEngine()
    }

    private func stopEngine() {
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
    }

    /// 停止当前播放
    func stop() {
        stopEngine()
    }

    enum TTSError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse
        case parseError(String)
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "请先在设置中填写豆包 TTS App ID 和 Access Key"
            case .invalidURL: return "无效的 API 地址"
            case .invalidResponse: return "无效的服务器响应"
            case .parseError(let detail): return "解析音频数据失败: \(detail)"
            case .apiError(let msg): return "API 错误: \(msg)"
            }
        }
    }
}
