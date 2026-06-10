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

    func updateCachedMnemonic(for word: String, etymology: String?, association: String?) {
        let key = normalizeKey(word)
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word == key }
            )
            guard let cached = try? context.fetch(descriptor).first,
                  let data = cached.jsonData.data(using: .utf8),
                  var result = try? JSONDecoder().decode(TranslationResult.self, from: data) else {
                return
            }
            result.etymology = etymology
            result.association = association
            if let jsonData = try? JSONEncoder().encode(result),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                cached.jsonData = jsonString
                try? context.save()
            }
        }
    }

    func updateCachedExamples(for word: String, examples: [String]) {
        let key = normalizeKey(word)
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word == key }
            )
            guard let cached = try? context.fetch(descriptor).first,
                  let data = cached.jsonData.data(using: .utf8),
                  var result = try? JSONDecoder().decode(TranslationResult.self, from: data) else {
                return
            }
            result.examples = examples
            if let jsonData = try? JSONEncoder().encode(result),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                cached.jsonData = jsonString
                try? context.save()
            }
        }
    }

    // MARK: - Sentence Translation Cache

    func getCachedSentenceTranslation(for key: String) -> SentenceTranslationResult? {
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
            return try? JSONDecoder().decode(SentenceTranslationResult.self, from: data)
        }
    }

    func cacheSentenceTranslation(_ result: SentenceTranslationResult, for key: String) {
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
            // 仅删除单词缓存（不含 "s:" 前缀的句子缓存）
            let prefix = "s:"
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { !$0.word.starts(with: prefix) }
            )
            if let entries = try? context.fetch(descriptor) {
                for entry in entries { context.delete(entry) }
                try? context.save()
            }
        }
    }

    func clearSentenceCache() {
        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            let prefix = "s:"
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word.starts(with: prefix) }
            )
            if let entries = try? context.fetch(descriptor) {
                for entry in entries { context.delete(entry) }
                try? context.save()
            }
        }
    }

    // MARK: - TTS Audio Cache

    func getCachedAudio(for key: String) -> Data? {
        return queue.sync {
            guard let container = modelContainer else { return nil }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TTSCache>(
                predicate: #Predicate { $0.word == key }
            )
            return try? context.fetch(descriptor).first?.audioData
        }
    }

    func cacheAudio(_ data: Data, for key: String) {
        // fire-and-forget：音频体积大（数百 KB），不让写入阻塞调用线程
        queue.async {
            guard let container = self.modelContainer else { return }
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

    /// 返回 (单词翻译条目数, 音频缓存条目数, 句子翻译条目数)
    func cacheCounts() -> (translation: Int, tts: Int, sentence: Int) {
        queue.sync {
            guard let container = modelContainer else { return (0, 0, 0) }
            let context = ModelContext(container)
            let prefix = "s:"
            let wordDesc = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { !$0.word.starts(with: prefix) }
            )
            let sentenceDesc = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word.starts(with: prefix) }
            )
            let ttsDesc = FetchDescriptor<TTSCache>()
            let tCount = (try? context.fetchCount(wordDesc)) ?? 0
            let sCount = (try? context.fetchCount(sentenceDesc)) ?? 0
            let aCount = (try? context.fetchCount(ttsDesc)) ?? 0
            return (tCount, aCount, sCount)
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
