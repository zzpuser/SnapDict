import Foundation

struct DotDevice: Codable, Sendable, Identifiable {
    let series: String
    let model: String
    let edition: Int
    let id: String

    var displayName: String {
        "\(series) \(model) (\(id.suffix(6)))"
    }
}

struct DotTask: Codable, Sendable, Identifiable {
    let type: String
    let key: String?

    var id: String { key ?? type }

    var isTextAPI: Bool { type == "TEXT_API" }
}

@Observable
final class DotScreenService: Sendable {
    static let shared = DotScreenService()

    private init() {}

    func fetchDevices() async throws -> [DotDevice] {
        guard let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.dotAPIKey),
              !apiKey.isEmpty else {
            throw DotError.noAPIKey
        }

        guard let url = URL(string: Constants.API.dotBaseURL + Constants.API.dotDevicesPath) else {
            throw DotError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DotError.requestFailed
        }

        return try JSONDecoder().decode([DotDevice].self, from: data)
    }

    struct PushPayload: Sendable {
        let word: String
        let phonetic: String
        let translation: String
        let firstExample: String?
    }

    func fetchTasks(deviceId: String, taskType: String = "loop") async throws -> [DotTask] {
        guard let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.dotAPIKey),
              !apiKey.isEmpty else {
            throw DotError.noAPIKey
        }

        let path = Constants.API.dotTaskListPath(deviceId: deviceId, taskType: taskType)
        guard let url = URL(string: Constants.API.dotBaseURL + path) else {
            throw DotError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DotError.requestFailed
        }

        return try JSONDecoder().decode([DotTask].self, from: data)
    }

    func pushWord(_ payload: PushPayload, to deviceId: String, taskKey: String? = nil) async throws {
        guard let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.dotAPIKey),
              !apiKey.isEmpty else {
            throw DotError.noAPIKey
        }

        let path = Constants.API.dotTextPath(deviceId: deviceId)
        guard let url = URL(string: Constants.API.dotBaseURL + path) else {
            throw DotError.invalidURL
        }

        let message = [
            payload.phonetic.isEmpty ? nil : payload.phonetic,
            payload.translation,
            payload.firstExample
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        var body: [String: Any] = [
            "refreshNow": true,
            "title": payload.word,
            "message": message,
            "signature": "SnapDict"
        ]
        if let taskKey, !taskKey.isEmpty {
            body["taskKey"] = taskKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DotError.requestFailed
        }
    }
}

enum DotError: LocalizedError {
    case noAPIKey
    case invalidURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "请先在设置中配置墨水屏 API Key"
        case .invalidURL: "无效的 API 地址"
        case .requestFailed: "墨水屏请求失败"
        }
    }
}
