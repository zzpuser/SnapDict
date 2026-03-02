import Foundation

enum Constants {
    enum API {
        static let deepSeekEndpoint = "https://api.deepseek.com/chat/completions"
        static let deepSeekModel = "deepseek-chat"

        static let dotBaseURL = "https://dot.mindreset.tech"
        static let dotDevicesPath = "/api/authV2/open/devices"
        static func dotTextPath(deviceId: String) -> String {
            "/api/authV2/open/device/\(deviceId)/text"
        }
        static func dotTaskListPath(deviceId: String, taskType: String = "loop") -> String {
            "/api/authV2/open/device/\(deviceId)/\(taskType)/list"
        }

        static let byteDanceTTSEndpoint = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
        static let byteDanceTTSResourceId = "seed-tts-2.0"
        static let byteDanceTTSVoices: [(id: String, name: String)] = [
            ("en_female_stokie_uranus_bigtts", "Stokie(女)"),
            ("en_male_tim_uranus_bigtts", "Tim(男)"),
        ]
        static let byteDanceTTSDefaultVoice = "en_female_stokie_uranus_bigtts"
    }

    enum TTSEngine: String, CaseIterable {
        case system = "system"
        case byteDance = "byteDance"

        var displayName: String {
            switch self {
            case .system: return "系统发音"
            case .byteDance: return "豆包语音"
            }
        }
    }

    enum UserDefaultsKey {
        static let deepSeekAPIKey = "deepSeekAPIKey"
        static let dotAPIKey = "dotAPIKey"
        static let pushInterval = "pushIntervalMinutes"
        static let pushOnlyLearning = "pushOnlyLearning"
        static let autoTranslate = "autoTranslateEnabled"
        static let pushEnabled = "pushEnabled"
        static let cachedDeviceId = "cachedDeviceId"
        static let cachedTaskKey = "cachedTaskKey"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let enableMnemonic = "enableMnemonic"
        static let showExamples = "showExamples"
        static let ttsEngine = "ttsEngine"
        static let byteDanceTTSAppId = "byteDanceTTSAppId"
        static let byteDanceTTSAPIKey = "byteDanceTTSAPIKey"
        static let ttsFallbackToSystem = "ttsFallbackToSystem"
        static let byteDanceTTSVoice = "byteDanceTTSVoice"
        static let hideOnFocusLost = "hideOnFocusLost"
        static let autoCorrect = "autoCorrect"
    }

    enum Defaults {
        static let pushIntervalMinutes = 30
        static let pushOnlyLearning = true
        static let autoTranslate = true
        static let enableMnemonic = true
        static let showExamples = true
        static let ttsFallbackToSystem = true
        static let hideOnFocusLost = true
        static let autoCorrect = false
    }

    enum Notification {
        static let openWordBook = Foundation.Notification.Name("SnapDict.openWordBook")
        static let openSettings = Foundation.Notification.Name("SnapDict.openSettings")
    }
}
