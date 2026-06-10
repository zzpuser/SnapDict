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
        static func dotImagePath(deviceId: String) -> String {
            "/api/authV2/open/device/\(deviceId)/image"
        }

        static let byteDanceTTSEndpoint = "https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse"
        static let byteDanceTTSResourceId = "seed-tts-2.0"
        static let byteDanceTTSVoices: [(id: String, name: String)] = [
            ("zh_female_vv_uranus_bigtts", "VV（女）"),
            ("zh_female_tianmeixiaoyuan_uranus_bigtts", "甜美小源（女）"),
            ("zh_male_sunwukong_uranus_bigtts", "悟空（男）"),
            ("en_female_stokie_uranus_bigtts", "Stokie（女，英文）"),
            ("en_male_tim_uranus_bigtts", "Tim（男，英文）"),
        ]
        static let byteDanceTTSDefaultVoice = "zh_female_vv_uranus_bigtts"
        /// TTS 下载/准备阶段总超时（秒）：SSE 流挂起时的兜底，超时自动取消并回退
        static let ttsFetchTimeout: TimeInterval = 20
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

    enum PushRandomMode: String, CaseIterable {
        case minCount = "minCount"
        case allWords = "allWords"

        var displayName: String {
            switch self {
            case .minCount: return "优先低频"
            case .allWords: return "完全随机"
            }
        }

        var description: String {
            switch self {
            case .minCount: return "低频单词被选中概率更高，但所有单词都有机会出现"
            case .allWords: return "从所有单词中随机选取，忽略推送次数"
            }
        }
    }

    enum PushMode: String, CaseIterable {
        case text = "text"
        case image = "image"

        var displayName: String {
            switch self {
            case .text: return "文本"
            case .image: return "图片"
            }
        }
    }

    enum DitherType: String, CaseIterable {
        case none = "NONE"
        case diffusion = "DIFFUSION"
        case ordered = "ORDERED"

        var displayName: String {
            switch self {
            case .none: return "关闭抖动"
            case .diffusion: return "误差扩散"
            case .ordered: return "有序抖动"
            }
        }
    }

    enum DitherKernel: String, CaseIterable {
        case floydSteinberg = "FLOYD_STEINBERG"
        case jarvisJudiceNinke = "JARVIS_JUDICE_NINKE"
        case stucki = "STUCKI"
        case atkinson = "ATKINSON"
        case burkes = "BURKES"
        case sierra = "SIERRA"
        case twoRowSierra = "TWO_ROW_SIERRA"
        case sierraLite = "SIERRA_LITE"
        case simple2D = "SIMPLE_2D"
        case stevensonArce = "STEVENSON_ARCE"

        var displayName: String {
            switch self {
            case .floydSteinberg: return "Floyd-Steinberg"
            case .jarvisJudiceNinke: return "Jarvis-Judice-Ninke"
            case .stucki: return "Stucki"
            case .atkinson: return "Atkinson"
            case .burkes: return "Burkes"
            case .sierra: return "Sierra"
            case .twoRowSierra: return "Two-Row Sierra"
            case .sierraLite: return "Sierra Lite"
            case .simple2D: return "Simple 2D"
            case .stevensonArce: return "Stevenson-Arce"
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
        static let showAnalysis = "showAnalysis"
        static let hideOnFocusLost = "hideOnFocusLost"
        static let autoFetchSelectedText = "autoFetchSelectedText"
        static let pushRandomMode = "pushRandomMode"
        static let pushMode = "pushMode"
        static let ditherType = "ditherType"
        static let ditherKernel = "ditherKernel"
        static let panelHeightWordBook = "panelHeightWordBook"
        static let panelHeightSettings = "panelHeightSettings"
        static let ttsEngine = "ttsEngine"
        static let byteDanceTTSAppId = "byteDanceTTSAppId"
        static let byteDanceTTSAPIKey = "byteDanceTTSAPIKey"
        static let ttsFallbackToSystem = "ttsFallbackToSystem"
        static let byteDanceTTSVoice = "byteDanceTTSVoice"
        static let ttsVolume = "ttsVolume"
    }

    enum Defaults {
        static let pushIntervalMinutes = 30
        static let pushOnlyLearning = true
        static let autoTranslate = true
        static let enableMnemonic = true
        static let showExamples = true
        static let showAnalysis = true
        static let hideOnFocusLost = true
        static let autoFetchSelectedText = false
        static let pushMode: PushMode = .text
        static let ditherType: DitherType = .none
        static let ditherKernel: DitherKernel = .floydSteinberg
        static let pushRandomMode: PushRandomMode = .minCount
        static let ttsFallbackToSystem = true
        static let ttsVolume = 100
    }

    enum Notification {
        static let openWordBook = Foundation.Notification.Name("SnapDict.openWordBook")
        static let openSettings = Foundation.Notification.Name("SnapDict.openSettings")
        static let ttsPlaybackStateChanged = Foundation.Notification.Name("SnapDict.ttsPlaybackStateChanged")
    }
}
