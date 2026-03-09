import AppKit
import ApplicationServices
import Carbon

@MainActor
enum SelectedTextReader {
    struct AppContext: Sendable {
        let processIdentifier: pid_t
        let localizedName: String?
        let bundleIdentifier: String?

        var description: String {
            let name = localizedName ?? bundleIdentifier ?? "unknown"
            return "\(name), pid: \(processIdentifier)"
        }
    }

    private struct PasteboardSnapshot {
        struct Item {
            let entries: [(type: NSPasteboard.PasteboardType, data: Data)]
        }

        let items: [Item]
    }

    /// 获取当前前台应用上下文
    static func captureFrontmostAppContext() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            debugLog("no frontmost application")
            return nil
        }

        return AppContext(
            processIdentifier: app.processIdentifier,
            localizedName: app.localizedName,
            bundleIdentifier: app.bundleIdentifier
        )
    }

    /// 获取前台应用中当前选中的文字
    static func getSelectedText() -> String? {
        guard let context = captureFrontmostAppContext() else { return nil }
        return getSelectedText(from: context)
    }

    static func getSelectedText(from context: AppContext) -> String? {
        // 提示 Chromium 系浏览器启用完整 AX 树（首次设置后 Chrome 会异步构建，后续调用即可生效）
        requestEnhancedAccessibility(for: context)

        if let element = focusedElement(for: context) {
            if let text = readSelectedTextAttribute(from: element, context: context) {
                return text
            }
            if let text = readSelectedTextRange(from: element, context: context) {
                return text
            }
        }

        // focusedElement 失败时（如 Chrome 网页内容区域），尝试从 AXWebArea 读取
        if let text = readSelectedTextFromWebArea(for: context) {
            return text
        }

        return nil
    }

    static func getSelectedTextForHotKey(from context: AppContext) async -> String? {
        if let text = getSelectedText(from: context) {
            return text
        }

        await waitForModifierRelease()

        if let text = getSelectedText(from: context) {
            return text
        }

        return await copySelectedTextUsingClipboard(from: context)
    }

    /// 检查是否已授予辅助功能权限
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能权限（弹出系统授权对话框）
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 已发送过 AXEnhancedUserInterface 的 pid 集合，避免重复设置
    private static var enhancedAccessibilityPids: Set<pid_t> = []

    /// 请求目标应用启用增强辅助功能（Chromium 系浏览器需要此设置才会暴露完整 AX 树）
    private static func requestEnhancedAccessibility(for context: AppContext) {
        guard !enhancedAccessibilityPids.contains(context.processIdentifier) else { return }
        enhancedAccessibilityPids.insert(context.processIdentifier)

        let appElement = appElement(for: context)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func appElement(for context: AppContext) -> AXUIElement {
        AXUIElementCreateApplication(context.processIdentifier)
    }

    private static func focusedElement(for context: AppContext) -> AXUIElement? {
        let appElement = appElement(for: context)

        var focusedElement: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if appResult == .success, let element = asAXUIElement(focusedElement) {
            return element
        }

        debugLog("[\(context.description)] focusedElement(app) failed: \(describe(appResult))")

        let systemWideElement = AXUIElementCreateSystemWide()
        var systemFocusedElement: CFTypeRef?
        let systemResult = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &systemFocusedElement)
        guard systemResult == .success, let systemElement = asAXUIElement(systemFocusedElement) else {
            debugLog("[\(context.description)] focusedElement(systemWide) failed: \(describe(systemResult))")
            return nil
        }

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(systemElement, &pid)
        guard pidResult == .success else {
            debugLog("[\(context.description)] focusedElement(systemWidePid) failed: \(describe(pidResult))")
            return nil
        }

        guard pid == context.processIdentifier else {
            debugLog("[\(context.description)] focusedElement(systemWidePid) mismatch: \(pid)")
            return nil
        }

        return systemElement
    }

    /// focusedElement 失败时，通过 focusedWindow → 遍历子树找 AXWebArea → 读取 selectedText
    private static func readSelectedTextFromWebArea(for context: AppContext) -> String? {
        let appElement = appElement(for: context)

        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard windowResult == .success, let window = asAXUIElement(windowRef) else {
            debugLog("[\(context.description)] webArea: focusedWindow failed: \(describe(windowResult))")
            return nil
        }

        guard let webArea = findElementWithRole(in: window, role: "AXWebArea", maxDepth: 5) else {
            debugLog("[\(context.description)] webArea: AXWebArea not found")
            return nil
        }

        if let text = readSelectedTextAttribute(from: webArea, context: context) {
            debugLog("[\(context.description)] webArea: selectedText success")
            return text
        }

        if let text = readSelectedTextRange(from: webArea, context: context) {
            debugLog("[\(context.description)] webArea: selectedTextRange success")
            return text
        }

        debugLog("[\(context.description)] webArea: no selected text")
        return nil
    }

    private static func findElementWithRole(in element: AXUIElement, role: String, maxDepth: Int) -> AXUIElement? {
        guard maxDepth > 0 else { return nil }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let elementRole = roleRef as? String,
           elementRole == role {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let childArray = childrenRef as? [AnyObject] else {
            return nil
        }

        let children = childArray.compactMap { asAXUIElement($0 as CFTypeRef) }

        for child in children {
            if let found = findElementWithRole(in: child, role: role, maxDepth: maxDepth - 1) {
                return found
            }
        }

        return nil
    }

    private static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readSelectedTextAttribute(from element: AXUIElement, context: AppContext) -> String? {
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textResult == .success, let text = selectedText as? String else {
            debugLog("[\(context.description)] selectedText failed: \(describe(textResult))")
            return nil
        }

        guard let trimmed = trimmedOrNil(text) else {
            debugLog("[\(context.description)] selectedText empty")
            return nil
        }

        debugLog("[\(context.description)] selectedText success: \(trimmed)")
        return trimmed
    }

    private static func readSelectedTextRange(from element: AXUIElement, context: AppContext) -> String? {
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeResult == .success, let rangeRef else {
            debugLog("[\(context.description)] selectedTextRange failed: \(describe(rangeResult))")
            return nil
        }

        guard CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            debugLog("[\(context.description)] selectedTextRange invalid type")
            return nil
        }

        let rangeValue = unsafeDowncast(rangeRef, to: AXValue.self)
        guard AXValueGetType(rangeValue) == .cfRange else {
            debugLog("[\(context.description)] selectedTextRange invalid AXValue type")
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            debugLog("[\(context.description)] selectedTextRange decode failed")
            return nil
        }

        guard range.length > 0 else {
            debugLog("[\(context.description)] selectedTextRange empty")
            return nil
        }

        var textRef: CFTypeRef?
        let stringResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &textRef
        )
        guard stringResult == .success, let text = textRef as? String else {
            debugLog("[\(context.description)] stringForRange failed: \(describe(stringResult))")
            return nil
        }

        guard let trimmed = trimmedOrNil(text) else {
            debugLog("[\(context.description)] stringForRange empty")
            return nil
        }

        debugLog("[\(context.description)] stringForRange success: \(trimmed)")
        return trimmed
    }

    private static func waitForModifierRelease(timeoutNanoseconds: UInt64 = 250_000_000) async {
        let interval: UInt64 = 20_000_000
        var elapsed: UInt64 = 0

        while elapsed < timeoutNanoseconds {
            if activeModifierFlags.isEmpty {
                return
            }

            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                return
            }

            elapsed += interval
        }
    }

    private static func copySelectedTextUsingClipboard(from context: AppContext) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let clearChangeCount = clearPasteboard(pasteboard)

        defer {
            restorePasteboard(snapshot, to: pasteboard)
        }

        guard postCopyShortcut(to: context.processIdentifier) else {
            debugLog("[\(context.description)] clipboard fallback failed: post copy shortcut")
            return nil
        }

        let attempts = 6
        for attempt in 1...attempts {
            do {
                try await Task.sleep(nanoseconds: 40_000_000)
            } catch {
                return nil
            }

            guard pasteboard.changeCount != clearChangeCount else { continue }

            if let copied = pasteboard.string(forType: .string), let trimmed = trimmedOrNil(copied) {
                debugLog("[\(context.description)] clipboard fallback success on attempt \(attempt): \(trimmed)")
                return trimmed
            }
        }

        debugLog("[\(context.description)] clipboard fallback failed: pasteboard unchanged or empty")
        return nil
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let entries = item.types.compactMap { type in
                item.data(forType: type).map { (type: type, data: $0) }
            }
            return PasteboardSnapshot.Item(entries: entries)
        }
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    private static func clearPasteboard(_ pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        return pasteboard.changeCount
    }

    private static func restorePasteboard(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let items: [NSPasteboardItem] = snapshot.items.compactMap { item in
            guard !item.entries.isEmpty else { return nil }
            let pasteboardItem = NSPasteboardItem()
            for entry in item.entries {
                pasteboardItem.setData(entry.data, forType: entry.type)
            }
            return pasteboardItem
        }

        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func postCopyShortcut(to pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    private static func asAXUIElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static var activeModifierFlags: NSEvent.ModifierFlags {
        NSEvent.modifierFlags.intersection([.command, .shift, .option, .control])
    }

    private static func describe(_ error: AXError) -> String {
        switch error {
        case .success:
            return "success"
        case .failure:
            return "failure"
        case .illegalArgument:
            return "illegalArgument"
        case .invalidUIElement:
            return "invalidUIElement"
        case .invalidUIElementObserver:
            return "invalidUIElementObserver"
        case .cannotComplete:
            return "cannotComplete"
        case .attributeUnsupported:
            return "attributeUnsupported"
        case .actionUnsupported:
            return "actionUnsupported"
        case .notificationUnsupported:
            return "notificationUnsupported"
        case .notImplemented:
            return "notImplemented"
        case .notificationAlreadyRegistered:
            return "notificationAlreadyRegistered"
        case .notificationNotRegistered:
            return "notificationNotRegistered"
        case .apiDisabled:
            return "apiDisabled"
        case .noValue:
            return "noValue"
        case .parameterizedAttributeUnsupported:
            return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:
            return "notEnoughPrecision"
        @unknown default:
            return "unknown(\(error.rawValue))"
        }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[SelectedTextReader] \(message)")
        #endif
    }
}
