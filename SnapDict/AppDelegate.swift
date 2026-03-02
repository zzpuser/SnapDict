import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var modelContainer: ModelContainer?

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateUserDefaultsIfNeeded()
        setupStatusItem()

        // Register hot key
        HotKeyManager.shared.onHotKey = { [weak self] in
            guard let container = self?.modelContainer else { return }
            PanelManager.shared.showPanel(modelContainer: container)
        }
        HotKeyManager.shared.register()

        // Start push scheduler if enabled
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.pushEnabled) {
            WordPushScheduler.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WordPushScheduler.shared.stop()
    }

    // MARK: - Migration

    private func migrateUserDefaultsIfNeeded() {
        let migrationKey = "didMigrateFromAiDict2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        guard let oldDefaults = UserDefaults(suiteName: "com.zzp.AiDict2") else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let keysToMigrate = [
            Constants.UserDefaultsKey.deepSeekAPIKey,
            Constants.UserDefaultsKey.dotAPIKey,
            Constants.UserDefaultsKey.pushInterval,
            Constants.UserDefaultsKey.pushOnlyLearning,
            Constants.UserDefaultsKey.autoTranslate,
            Constants.UserDefaultsKey.pushEnabled,
            Constants.UserDefaultsKey.cachedDeviceId,
            Constants.UserDefaultsKey.cachedTaskKey,
            Constants.UserDefaultsKey.hotKeyKeyCode,
            Constants.UserDefaultsKey.hotKeyModifiers,
            Constants.UserDefaultsKey.enableMnemonic,
            Constants.UserDefaultsKey.showExamples,
            Constants.UserDefaultsKey.ttsEngine,
            Constants.UserDefaultsKey.byteDanceTTSAppId,
            Constants.UserDefaultsKey.byteDanceTTSAPIKey,
            Constants.UserDefaultsKey.ttsFallbackToSystem,
            Constants.UserDefaultsKey.byteDanceTTSVoice,
        ]

        for key in keysToMigrate {
            if let value = oldDefaults.object(forKey: key),
               UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else { return }

        if let url = Bundle.main.url(forResource: "MenuBarIconTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "SnapDict")
        }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showQuitMenu()
        } else {
            guard let container = modelContainer else { return }
            PanelManager.shared.showPanel(modelContainer: container)
        }
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出 SnapDict", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // 清除 menu，否则后续左键点击也会弹出菜单
        statusItem.menu = nil
    }
}
