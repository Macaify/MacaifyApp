//
//  ChatTokens.swift
//  XCAChatGPTMac
//
//  Design tokens for Chat UI. Keep values minimal and
//  prefer system colors to support light/dark modes.
//

import SwiftUI

enum ChatTokens {
    static let bubbleRadius: CGFloat = 10
    static let gap: CGFloat = 12
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let controlHeight: CGFloat = 32

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
    static var strokeColor: Color { Color.gray.opacity(0.12) }
}

