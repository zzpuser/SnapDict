import AVFoundation

private enum TTSPlaybackError: LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        "音频播放启动失败"
    }
}

@MainActor
final class TTSManager: NSObject, AVAudioPlayerDelegate {
    static let shared = TTSManager()

    private(set) var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var systemProcess: Process?
    private var playTask: Task<Void, Never>?
    private var finishWatchdogTask: Task<Void, Never>?
    private var playbackToken = UUID()

    private override init() {
        super.init()
    }

    /// Toggle：播放中则停止，否则开始朗读
    func speak(_ word: String) {
        if isPlaying {
            stop()
            return
        }

        let engineRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ttsEngine) ?? ""
        let engine = Constants.TTSEngine(rawValue: engineRaw) ?? .system

        let token = UUID()
        playbackToken = token
        setPlaying(true)

        switch engine {
        case .system:
            speakWithSystem(word, token: token)
        case .byteDance:
            speakWithByteDance(word, token: token)
        }
    }

    /// 停止所有播放，重置状态
    func stop() {
        playbackToken = UUID()
        playTask?.cancel()
        playTask = nil
        finishWatchdogTask?.cancel()
        finishWatchdogTask = nil
        audioPlayer?.delegate = nil
        audioPlayer?.stop()
        audioPlayer = nil
        systemProcess?.terminationHandler = nil
        systemProcess?.terminate()
        systemProcess = nil
        setPlaying(false)
    }

    /// 播放测试音频（供设置页保存/测试时调用）
    func playTestAudio(_ data: Data) async throws {
        stop()
        let token = UUID()
        playbackToken = token
        setPlaying(true)
        do {
            let player = try await Self.makePreparedPlayer(data: data)
            guard playbackToken == token else { return }
            guard attachAndPlay(player, token: token) else {
                throw TTSPlaybackError.playbackFailed
            }
        } catch {
            if playbackToken == token {
                setPlaying(false)
            }
            throw error
        }
    }

    // MARK: - System TTS (子进程，不阻塞主线程)

    private func speakWithSystem(_ word: String, token: UUID) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [word]
        // 静默标准输出和错误输出
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak process] _ in
            Task { @MainActor in
                // 仅当此进程仍为当前进程时重置状态（避免 stop() 后的残留回调）
                guard let process,
                      self.playbackToken == token,
                      self.systemProcess === process else { return }
                self.systemProcess = nil
                self.setPlaying(false)
            }
        }
        do {
            try process.run()
            self.systemProcess = process
        } catch {
            guard playbackToken == token else { return }
            setPlaying(false)
        }
    }

    // MARK: - ByteDance TTS

    private func speakWithByteDance(_ word: String, token: UUID) {
        // 下载/准备阶段兜底：SSE 流挂起时自动终止，避免 isPlaying 永久卡在 true
        scheduleFetchWatchdog(fallbackWord: word, token: token)
        playTask = Task.detached(priority: .userInitiated) { [word, token] in
            do {
                let audioData = try await ByteDanceTTSService.shared.fetchAudio(text: word)
                // 解码与音频硬件预热在后台执行器完成，不阻塞 main actor 上的流式翻译渲染
                let player = try await TTSManager.makePreparedPlayer(data: audioData)
                try Task.checkCancellation()
                await TTSManager.shared.startPreparedPlayback(player, fallbackWord: word, token: token)
            } catch is CancellationError {
                return
            } catch {
                await TTSManager.shared.handleByteDanceFailure(word, token: token)
            }
        }
    }

    private func startPreparedPlayback(_ player: sending AVAudioPlayer, fallbackWord word: String, token: UUID) {
        guard playbackToken == token else { return }
        playTask = nil
        if !attachAndPlay(player, token: token) {
            handleByteDanceFailure(word, token: token)
        }
    }

    private func handleByteDanceFailure(_ word: String, token: UUID) {
        guard playbackToken == token else { return }
        playTask = nil
        finishWatchdogTask?.cancel()
        finishWatchdogTask = nil

        // 换新 token：作废仍可能在途的旧回调（如 watchdog 取消下载后已排队的播放回调）
        let newToken = UUID()
        playbackToken = newToken

        let fallback = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsFallbackToSystem) as? Bool
            ?? Constants.Defaults.ttsFallbackToSystem

        if fallback {
            speakWithSystem(word, token: newToken)
        } else {
            setPlaying(false)
        }
    }

    /// 在后台执行器上创建并预热播放器。
    /// AVAudioPlayer 线程安全；MP3 解码、缓冲预载、音频硬件启动（prepareToPlay 内的
    /// coreaudiod 同步 IPC，蓝牙设备可达秒级）均不占用 main actor。
    private nonisolated static func makePreparedPlayer(data: Data) async throws -> sending AVAudioPlayer {
        let volume = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsVolume) as? Int
            ?? Constants.Defaults.ttsVolume
        let clamped = min(max(volume, 0), Constants.Defaults.ttsVolumeMax)

        let player: AVAudioPlayer
        if clamped > 100 {
            // AVAudioPlayer.volume 上限为 1.0，超过 100% 只能预处理样本实现增益
            let amplified = try amplifiedAudioData(from: data, gain: Float(clamped) / 100)
            player = try AVAudioPlayer(data: amplified, fileTypeHint: AVFileType.caf.rawValue)
            player.volume = 1
        } else {
            player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
            player.volume = Float(clamped) / 100
        }
        guard player.prepareToPlay() else {
            throw TTSPlaybackError.playbackFailed
        }
        return player
    }

    /// 音量放大：解码 MP3 → PCM 样本乘增益（clamp 到 ±1 防爆音削波失真过重）→ 重编码为 CAF。
    /// AVAudioFile 只接受文件 URL，需经临时文件中转。
    private nonisolated static func amplifiedAudioData(from data: Data, gain: Float) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("snapdict-tts-\(UUID().uuidString).mp3")
        let outputURL = tempDir.appendingPathComponent("snapdict-tts-\(UUID().uuidString).caf")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try data.write(to: inputURL)

        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TTSPlaybackError.playbackFailed
        }
        try inputFile.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw TTSPlaybackError.playbackFailed
        }
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for i in 0..<Int(buffer.frameLength) {
                samples[i] = max(-1, min(1, samples[i] * gain))
            }
        }

        // AVAudioFile 在释放时才完成写入，独立作用域确保读取前已落盘
        do {
            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: buffer)
        }
        return try Data(contentsOf: outputURL)
    }

    /// 绑定 delegate 并启动播放（player 已 prepare，play() 开销极小）
    private func attachAndPlay(_ player: AVAudioPlayer, token: UUID) -> Bool {
        finishWatchdogTask?.cancel()
        finishWatchdogTask = nil
        audioPlayer?.delegate = nil
        audioPlayer?.stop()

        player.delegate = self
        audioPlayer = player

        guard player.play() else {
            player.delegate = nil
            audioPlayer = nil
            return false
        }

        scheduleFinishWatchdog(for: player, token: token)
        return true
    }

    /// 下载/准备阶段超时兜底；播放开始后由 scheduleFinishWatchdog 接管
    private func scheduleFetchWatchdog(fallbackWord word: String, token: UUID) {
        finishWatchdogTask?.cancel()
        finishWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.API.ttsFetchTimeout))
            guard !Task.isCancelled,
                  self.playbackToken == token,
                  self.playTask != nil else { return }
            self.playTask?.cancel()
            self.handleByteDanceFailure(word, token: token)
        }
    }

    private func scheduleFinishWatchdog(for player: AVAudioPlayer, token: UUID) {
        let duration = player.duration
        let timeout = duration.isFinite && duration > 0 ? duration + 1 : 30
        finishWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(timeout * 1000)))
            guard !Task.isCancelled,
                  self.playbackToken == token,
                  self.audioPlayer === player else { return }
            self.finishAudioPlayback(player)
        }
    }

    private func finishAudioPlayback(_ player: AVAudioPlayer) {
        guard audioPlayer === player else { return }
        finishWatchdogTask?.cancel()
        finishWatchdogTask = nil
        player.delegate = nil
        audioPlayer = nil
        setPlaying(false)
    }

    private func finishAudioPlayback(playerID: ObjectIdentifier) {
        guard let player = audioPlayer, ObjectIdentifier(player) == playerID else { return }
        finishAudioPlayback(player)
    }

    private func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        NotificationCenter.default.post(
            name: Constants.Notification.ttsPlaybackStateChanged,
            object: self,
            userInfo: ["isPlaying": playing]
        )
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor in
            self.finishAudioPlayback(playerID: playerID)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor in
            self.finishAudioPlayback(playerID: playerID)
        }
    }
}
