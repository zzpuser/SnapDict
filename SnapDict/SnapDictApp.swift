import SwiftUI
import SwiftData

@main
struct SnapDictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WordEntry.self, TranslationCache.self, TTSCache.self)
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
}
