//
//  SettingView.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/8.
//

import SwiftUI
import KeyboardShortcuts
import Defaults

struct SettingView: View {
    // 返回按钮的操作
    var onBackButtonTap: () -> Void

    var body: some View {
        // 旧版内置设置页已弃用，此处仅作为兼容包装器显示标准设置页。
        StandardSettingsView()
    }
}

extension NSTextView {
    open override var frame: CGRect {
        didSet {
            backgroundColor = .clear //<<here clear
            drawsBackground = true
        }
    }
}
