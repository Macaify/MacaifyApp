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
    // 记录触发抓取时的前台 App 信息，供调用方透传到上下文
    var currentSourceBundleId: String? = nil
    var currentSourceAppName: String? = nil

    func startup(task: @escaping (_ text: String?) -> Void) {
        let (bid, name) = frontmostAppInfo()
        print("[StartupPB] frontmost before copy: \(bid ?? "?") / \(name ?? "?")")
        currentSourceBundleId = bid
        currentSourceAppName = name
        let oldValue = getLatestTextFromPasteboard().text
        print("oldClip \(oldValue ?? "nil")")
        // Try AX first for better reliability
        if let ax = getSelectedTextAX(), !ax.isEmpty {
            task(ax)
            return
        }

        performGlobalCopyShortcut()

        func tryRead(attempt: Int) {
            let cp = getLatestTextFromPasteboard()
            let t = cp.text ?? ""
            let use: String? = (t.isEmpty || (oldValue != nil && t == oldValue)) ? nil : t
            print("[StartupPB] attempt=\(attempt) got=\(t.count) sameOld=\(oldValue != nil && t == oldValue)")
            if let use {
                task(use)
                if let oldValue { copy(text: oldValue) }
            } else if attempt < 3 { // retry a few times to tolerate slow apps
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    tryRead(attempt: attempt + 1)
                }
            } else {
                task(nil)
                if let oldValue { copy(text: oldValue) }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            tryRead(attempt: 0)
        }
    }

    func consumed() {
        if let current = currentPasted, !current.isEmpty {
            lastPasted = current
        }
        currentPasted = ""
    }
}
