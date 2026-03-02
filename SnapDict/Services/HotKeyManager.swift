import Carbon
import HotKey
import SwiftUI

@MainActor
@Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKey: HotKey?
    var onHotKey: (() -> Void)?

    private init() {}

    func register() {
        let keyCode = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hotKeyKeyCode) as? UInt32
        let modifiers = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.hotKeyModifiers) as? UInt32

        let key: Key
        let mods: NSEvent.ModifierFlags

        if let keyCode, let modifiers {
            key = Key(carbonKeyCode: keyCode)!
            mods = NSEvent.ModifierFlags(carbonFlags: modifiers)
        } else {
            // Default: Cmd+Shift+E
            key = .e
            mods = [.command, .shift]
        }

        registerHotKey(key: key, modifiers: mods)
    }

    func registerHotKey(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey = nil
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.onHotKey?()
        }
    }

    func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(keyCode, forKey: Constants.UserDefaultsKey.hotKeyKeyCode)
        UserDefaults.standard.set(modifiers, forKey: Constants.UserDefaultsKey.hotKeyModifiers)

        if let key = Key(carbonKeyCode: keyCode) {
            let mods = NSEvent.ModifierFlags(carbonFlags: modifiers)
            registerHotKey(key: key, modifiers: mods)
        }
    }
}
