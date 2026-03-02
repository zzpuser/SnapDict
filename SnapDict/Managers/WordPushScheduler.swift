import Foundation

@MainActor
@Observable
final class WordPushScheduler {
    static let shared = WordPushScheduler()

    var isRunning = false
    var lastPushTime: Date?
    var lastError: String?

    private var timer: Timer?
    private var cachedDeviceId: String?

    private init() {
        cachedDeviceId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedDeviceId)
    }

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
            let payload = DotScreenService.PushPayload(
                word: entry.word,
                phonetic: entry.phonetic,
                translation: entry.translation,
                firstExample: entry.examples.first
            )
            let taskKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.cachedTaskKey)
            try await DotScreenService.shared.pushWord(payload, to: deviceId, taskKey: taskKey)
            try WordBookManager.shared.markPushed(entry)
            lastPushTime = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resolveDeviceId() async throws -> String {
        if let cached = cachedDeviceId, !cached.isEmpty {
            return cached
        }

        let devices = try await DotScreenService.shared.fetchDevices()
        guard let first = devices.first else {
            throw DotError.requestFailed
        }

        cachedDeviceId = first.id
        UserDefaults.standard.set(first.id, forKey: Constants.UserDefaultsKey.cachedDeviceId)
        return first.id
    }
}
