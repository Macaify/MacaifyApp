//
//  SelectedText.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/16.
//

import Foundation

import Cocoa
import ApplicationServices
import Carbon.HIToolbox
//
//func getSelectedText() -> String? {
//    let systemWideElement = AXUIElementCreateSystemWide()
//    guard let focusedElement = try? systemWideElement.focusedUIElement(),
//          let selectedText = try? focusedElement.selectedText() else {
//        return nil
//    }
//    return selectedText
//}
//
//extension AXUIElement {
//    func focusedUIElement() throws -> AXUIElement? {
//        var result: AnyObject?
//        let status = AXUIElementCopyAttributeValue(self, kAXFocusedUIElementAttribute as CFString, &result)
//        guard status == .success else { throw NSError(domain: NSCocoaErrorDomain, code: Int(status), userInfo: nil) }
//        return result as? AXUIElement
//    }
//
//    func selectedText() throws -> String? {
//        var result: AnyObject?
//        let status = AXUIElementCopyAttributeValue(self, kAXSelectedTextAttribute as CFString, &result)
//        guard status == .success else { throw NSError(domain: NSCocoaErrorDomain, code: Int(status), userInfo: nil) }
//        return result as? String
//    }
//}


import Cocoa
//
//func getSelectedText() -> String? {
//    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
//        return nil
//    }
//
//
//
//    guard let focusedWindow = frontmostApp.windows.first(where: { \$0.isMainWindow && \$0.isVisible }) else {
//        return nil
//    }
//    guard let selectedText = focusedWindow.selectedText else {
//        return nil
//    }
//    return selectedText
//}
//
//extension NSWindow {
//    var selectedText: String? {
//        let element = accessibilityFocusedUIElement()
//        var selectedText: AnyObject?
//        let status = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
//        return status == .success ? selectedText as? String : nil
//    }
//}

func performGlobalCopyShortcut() {
    func keyEvents(forPressAndReleaseVirtualKey virtualKey: Int) -> [CGEvent] {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        return [
            CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(virtualKey), keyDown: true)!,
            CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(virtualKey), keyDown: false)!,
        ]
    }

    let tapLocation = CGEventTapLocation.cghidEventTap
    let events = keyEvents(forPressAndReleaseVirtualKey: Int(kVK_ANSI_C)) // C

    // Slight spacing between down/up improves reliability in some apps
    if let down = events.first, let up = events.last {
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: tapLocation)
        usleep(8_000)
        up.post(tap: tapLocation)
    }
}

func performGlobalPasteShortcut() {
    func keyEvents(forPressAndReleaseVirtualKey virtualKey: Int) -> [CGEvent] {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        return [
            CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(virtualKey), keyDown: true)!,
            CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(virtualKey), keyDown: false)!,
        ]
    }

    let tapLocation = CGEventTapLocation.cghidEventTap
    let events = keyEvents(forPressAndReleaseVirtualKey: Int(kVK_ANSI_V)) // V

    if let down = events.first, let up = events.last {
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: tapLocation)
        usleep(8_000)
        up.post(tap: tapLocation)
    }
}

// MARK: - Accessibility helpers
@discardableResult
func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
    let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt]
    return AXIsProcessTrustedWithOptions(opts)
}

func getSelectedTextAX() -> String? {
    guard hasAccessibilityPermission() else { return nil }
    let systemWide = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    let statusFocused = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
    guard statusFocused == .success, let element = focused else { return nil }
    var selected: AnyObject?
    let statusText = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected)
    if statusText == .success, let s = selected as? String, !s.isEmpty {
        return s
    }
    return nil
}

func frontmostAppInfo() -> (bundleId: String?, name: String?) {
    if let app = NSWorkspace.shared.frontmostApplication {
        return (app.bundleIdentifier, app.localizedName)
    }
    return (nil, nil)
}

func getLatestTextFromPasteboard() -> (text: String?, time: Date?) {
    // Using direct string(forType:) is more reliable across apps
    let text = NSPasteboard.general.string(forType: .string)
    return (text, Date())
}

func copy(text: String) {
    // Declare types instead of full clear to avoid edge cases with some apps
    NSPasteboard.general.declareTypes([.string], owner: nil)
    NSPasteboard.general.setString(text, forType: .string)
}
