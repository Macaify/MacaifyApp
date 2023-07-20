//
//  StarupPasteboardManager.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/16.
//

import Foundation

class StartupPasteboardManager {
    static let shared = StartupPasteboardManager()
    
    var currentPasted: String?
    var lastPasted: String?

    func startup(task: @escaping (_ text: String?) -> Void) {
        let oldValue = getLatestTextFromPasteboard().text
        print("oldClip \(oldValue)")
        performGlobalCopyShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { // wait 0.05s for copy.
            let cp = getLatestTextFromPasteboard()
            print("newClip", cp.text, cp.time)
            var newValue = cp.text
//            var newValue = cp.text == oldValue ? "" : cp.text
            task(newValue)

            copy(text: oldValue ?? "")
        }
    }

    func consumed() {
        if let current = currentPasted, !current.isEmpty {
            lastPasted = current
        }
        currentPasted = ""
    }
}
