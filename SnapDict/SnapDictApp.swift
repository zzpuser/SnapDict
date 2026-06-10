import SwiftUI
import SwiftData

@main
struct SnapDictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var container: ModelContainer

    init() {
        do {
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeDir = appSupport.appendingPathComponent("com.zzp.SnapDict")
            let storeURL = storeDir.appendingPathComponent("SnapDict.store")

            // 从旧的 default.store 迁移到专属路径
            if !fm.fileExists(atPath: storeURL.path) {
                try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
                let legacyURL = appSupport.appendingPathComponent("default.store")
                if fm.fileExists(atPath: legacyURL.path) {
                    try? fm.copyItem(at: legacyURL, to: storeURL)
                    // 同时迁移 WAL 和 SHM 文件
                    for suffix in ["-wal", "-shm"] {
                        let src = appSupport.appendingPathComponent("default.store\(suffix)")
                        let dst = storeDir.appendingPathComponent("SnapDict.store\(suffix)")
                        try? fm.copyItem(at: src, to: dst)
                    }
                }
            }

            try Self.clearLegacyTTSCacheIfNeeded(at: storeURL)

            let config = ModelConfiguration(url: storeURL)
            container = try ModelContainer(for: WordEntry.self, TranslationCache.self, TTSCache.self, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Share container with managers
        WordBookManager.shared.setup(container: container)
        CacheService.shared.setup(container: container)
        appDelegate.modelContainer = container
    }

    var body: some Scene {
        Settings { EmptyView() }
    }

    private static func clearLegacyTTSCacheIfNeeded(at storeURL: URL) throws {
        let cleanupKey = "didResetRebuiltTTSCache"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: cleanupKey) else { return }

        let fm = FileManager.default
        let hasStoreFiles =
            fm.fileExists(atPath: storeURL.path) ||
            fm.fileExists(atPath: "\(storeURL.path)-wal") ||
            fm.fileExists(atPath: "\(storeURL.path)-shm")

        guard hasStoreFiles else {
            defaults.set(true, forKey: cleanupKey)
            return
        }

        let config = ModelConfiguration(url: storeURL)
        let legacyContainer = try ModelContainer(for: WordEntry.self, TranslationCache.self, TTSCache.self, LegacyTTSCache.self, configurations: config)
        let context = ModelContext(legacyContainer)
        try? context.delete(model: LegacyTTSCache.self)
        try? context.save()
        defaults.set(true, forKey: cleanupKey)
    }
}

@Model
private final class LegacyTTSCache {
    @Attribute(.unique) var word: String
    @Attribute(.externalStorage) var audioData: Data
    var createdAt: Date

    init(word: String, audioData: Data, createdAt: Date = .now) {
        self.word = word
        self.audioData = audioData
        self.createdAt = createdAt
    }
}
