import AppKit
import ApplicationServices

/// Delivers transcribed text to the frontmost app's focused field.
///
/// Cascade of strategies, each logged to debug.log:
///  1. Electron apps — clipboard + Cmd+V because they can falsely report AX success
///  2. AX API — write to the focused element's selected-text attribute (no key events at all)
///  3. Unicode typing — synthesized keyboard events with the string on keyDown
///  4. Clipboard + Cmd+V — last resort
enum TextInserter {
    enum PreferredStrategy: Equatable {
        case standard
        case pasteboard
    }

    static func preferredStrategy(for appBundleURL: URL?) -> PreferredStrategy {
        guard let appBundleURL else { return .standard }
        let electronFramework = appBundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: electronFramework.path) ? .pasteboard : .standard
    }

    static func insert(_ text: String) {
        if preferredStrategy(for: NSWorkspace.shared.frontmostApplication?.bundleURL) == .pasteboard {
            insertViaPasteboard(text)
            debugLog("insert: Electron clipboard+CmdV")
            return
        }
        if insertViaAX(text) {
            debugLog("insert: AX ok (\(text.count) chars)")
            return
        }
        if insertViaTyping(text) {
            debugLog("insert: typed \(text.count) chars")
            return
        }
        insertViaPasteboard(text)
        debugLog("insert: fell back to clipboard+CmdV")
    }

    // MARK: - Strategy 1: Accessibility API

    private static func insertViaAX(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focusedRef else {
            debugLog("insert: AX no focused element (\(focusErr.rawValue))")
            return false
        }
        let element = focusedRef as! AXUIElement

        // the element must actually support writing selected text
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard settable.boolValue else {
            debugLog("insert: AX selected-text not settable")
            return false
        }
        let err = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if err != .success {
            debugLog("insert: AX set failed (\(err.rawValue))")
            return false
        }
        return true
    }

    // MARK: - Strategy 2: unicode typing

    private static func insertViaTyping(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index ..< min(index + 16, units.count)])
            // unicode string goes on keyDown ONLY — a string on keyUp makes the
            // window server silently drop the whole pair (observed on macOS 27)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
            usleep(8000) // let the target app drain its event queue
            index += 16
        }
        return true
    }

    // MARK: - Strategy 3: clipboard + Cmd+V

    private static func insertViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(9) // 'v'
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}
