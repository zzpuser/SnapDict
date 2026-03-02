import Foundation
import SwiftData

final class CacheService: @unchecked Sendable {
    static let shared = CacheService()

    private var modelContainer: ModelContainer?
    private let queue = DispatchQueue(label: "com.aidict2.cache", qos: .userInitiated)

    private init() {}

    func setup(container: ModelContainer) {
        self.modelContainer = container
        cleanupLegacyDatabase()
    }

    // MARK: - Translation Cache

    func getCachedTranslation(for word: String) -> TranslationResult? {
        let key = normalizeKey(word)
        return queue.sync {
            guard let container = modelContainer else { return nil }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word == key }
            )
            guard let cached = try? context.fetch(descriptor).first,
                  let data = cached.jsonData.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(TranslationResult.self, from: data)
        }
    }

    func cacheTranslation(_ result: TranslationResult) {
        let key = normalizeKey(result.word)
        guard let jsonData = try? JSONEncoder().encode(result),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word == key }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.jsonData = jsonString
                existing.createdAt = .now
            } else {
                context.insert(TranslationCache(word: key, jsonData: jsonString))
            }
            try? context.save()
        }
    }

    func clearTranslationCache() {
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            try? context.delete(model: TranslationCache.self)
            try? context.save()
        }
    }

    // MARK: - TTS Cache

    func getCachedAudio(for word: String) -> Data? {
        let key = normalizeKey(word)
        return queue.sync {
            guard let container = modelContainer else { return nil }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TTSCache>(
                predicate: #Predicate { $0.word == key }
            )
            return try? context.fetch(descriptor).first?.audioData
        }
    }

    func cacheAudio(_ data: Data, for word: String) {
        let key = normalizeKey(word)
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TTSCache>(
                predicate: #Predicate { $0.word == key }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.audioData = data
                existing.createdAt = .now
            } else {
                context.insert(TTSCache(word: key, audioData: data))
            }
            try? context.save()
        }
    }

    func clearTTSCache() {
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            try? context.delete(model: TTSCache.self)
            try? context.save()
        }
    }

    // MARK: - General

    func clearAllCache() {
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            try? context.delete(model: TranslationCache.self)
            try? context.delete(model: TTSCache.self)
            try? context.save()
        }
    }

    /// 返回 (翻译条目数, 音频条目数)
    func cacheCounts() -> (translation: Int, tts: Int) {
        queue.sync {
            guard let container = modelContainer else { return (0, 0) }
            let context = ModelContext(container)
            let tCount = (try? context.fetchCount(FetchDescriptor<TranslationCache>())) ?? 0
            let aCount = (try? context.fetchCount(FetchDescriptor<TTSCache>())) ?? 0
            return (tCount, aCount)
        }
    }

    // MARK: - Private

    private func normalizeKey(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 删除旧的 sqlite3 缓存文件
    private func cleanupLegacyDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyDB = appSupport.appendingPathComponent("AiDict2/cache.db")
        let legacyWAL = appSupport.appendingPathComponent("AiDict2/cache.db-wal")
        let legacySHM = appSupport.appendingPathComponent("AiDict2/cache.db-shm")
        for file in [legacyDB, legacyWAL, legacySHM] {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
