import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var modelContainer: ModelContainer?

    private var statusItem: NSStatusItem!
    private var pendingHotKeyTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateUserDefaultsIfNeeded()
        setupStatusItem()

        // Register hot key
        HotKeyManager.shared.onHotKey = { [weak self] in
            guard let self else { return }
            self.pendingHotKeyTask?.cancel()
            self.pendingHotKeyTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleHotKey()
            }
        }
        HotKeyManager.shared.register()

        // Start push scheduler if enabled
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.pushEnabled) {
            WordPushScheduler.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingHotKeyTask?.cancel()
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
            var selectedText: String? = nil
            let autoFetch = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.autoFetchSelectedText) as? Bool
                ?? Constants.Defaults.autoFetchSelectedText
            if autoFetch {
                selectedText = SelectedTextReader.getSelectedText()
            }
            PanelManager.shared.showPanel(modelContainer: container, selectedText: selectedText)
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

    private func handleHotKey() async {
        guard let container = modelContainer else { return }

        let autoFetch = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.autoFetchSelectedText) as? Bool
            ?? Constants.Defaults.autoFetchSelectedText

        #if DEBUG
        print("[HotKey] triggered, autoFetch=\(autoFetch), accessibility=\(SelectedTextReader.isAccessibilityGranted())")
        #endif

        // 面板可见且不需要取词时，直接 toggle 隐藏
        if PanelManager.shared.isPanelVisible && !(autoFetch && SelectedTextReader.isAccessibilityGranted()) {
            #if DEBUG
            print("[HotKey] panel visible, no autoFetch, toggle hide")
            #endif
            PanelManager.shared.showPanel(modelContainer: container)
            return
        }

        guard autoFetch, SelectedTextReader.isAccessibilityGranted() else {
            #if DEBUG
            print("[HotKey] selectedText=nil")
            #endif
            PanelManager.shared.showPanel(modelContainer: container)
            return
        }

        guard let context = SelectedTextReader.captureFrontmostAppContext() else {
            #if DEBUG
            print("[HotKey] no context, selectedText=nil")
            #endif
            PanelManager.shared.showPanel(modelContainer: container)
            return
        }

        let selectedText = await SelectedTextReader.getSelectedTextForHotKey(from: context)
        guard !Task.isCancelled else { return }

        #if DEBUG
        print("[HotKey] selectedText=\(selectedText ?? "nil")")
        #endif
        PanelManager.shared.showPanel(modelContainer: container, selectedText: selectedText)
    }
}
