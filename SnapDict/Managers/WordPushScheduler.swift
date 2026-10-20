import Foundation

@MainActor
@Observable
final class WordPushScheduler {
    static let shared = WordPushScheduler()

    var isRunning = false
    var lastPushTime: Date?
    var lastError: String?

    private var timer: Timer?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let minutes = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushInterval) as? Int
            ?? Constants.Defaults.pushIntervalMinutes
        let interval = TimeInterval(minutes * 60)

        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pushNext()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func restart() {
        stop()
        start()
    }

    func pushNext() async {
        lastError = nil

        guard let entry = WordBookManager.shared.nextWordForPush() else {
            let pushOnlyLearning = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushOnlyLearning) as? Bool
                ?? Constants.Defaults.pushOnlyLearning
            lastError = pushOnlyLearning ? "学习中为空" : "生词本为空"
            return
        }

        do {
            let deviceId = try await resolveDeviceId()
            let modeRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.pushMode) ?? ""
            let pushMode = Constants.PushMode(rawValue: modeRaw) ?? Constants.Defaults.pushMode
            let taskKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedTaskKey)

            switch pushMode {
            case .image:
                guard let pngData = WordCardRenderer.render(
                    word: entry.word,
                    phonetic: entry.phonetic,
                    translation: entry.translation
                ) else {
                    lastError = "图片渲染失败"
                    return
                }
                let base64 = pngData.base64EncodedString()
                try await DotScreenService.shared.pushImage(base64, to: deviceId, taskKey: taskKey)
            case .text:
                let payload = DotScreenService.PushPayload(
                    word: entry.word,
                    phonetic: entry.phonetic,
                    translation: entry.translation,
                    firstExample: entry.examples.first
                )
                try await DotScreenService.shared.pushWord(payload, to: deviceId, taskKey: taskKey)
            }
            try WordBookManager.shared.markPushed(entry)
            lastPushTime = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resolveDeviceId() async throws -> String {
        // 每次从 UserDefaults 读取：设置页切换/刷新设备只写 UserDefaults，不能缓存在内存
        if let cached = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedDeviceId),
           !cached.isEmpty {
            return cached
        }

        let devices = try await DotScreenService.shared.fetchDevices()
        guard let first = devices.first else {
            throw DotError.requestFailed
        }

        UserDefaults.standard.set(first.id, forKey: Constants.UserDefaultsKey.cachedDeviceId)
        return first.id
    }
}
