//
//  PlainButton.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/16.
//

import SwiftUI

struct PlainButton: View, Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    var backgroundColor: Color
    var pressedBackgroundColor: Color
    var foregroundColor: Color
    let cornerRadius: CGFloat
    var shortcut: KeyEquivalent?
    var modifiers: EventModifiers = []
    let action: () -> Void

    init(icon: String = "",
         label: String = "",
         backgroundColor: Color = .white,
         pressedBackgroundColor: Color = Color.gray.opacity(0.1),
         foregroundColor: Color = Color.text,
         cornerRadius: CGFloat = 6,
         shortcut: KeyEquivalent? = nil,
         modifiers: EventModifiers = [],
         action: @escaping () -> Void) {
        self.action = action
        self.icon = icon
        self.label = label
        self.backgroundColor = backgroundColor
        self.pressedBackgroundColor = pressedBackgroundColor
        self.foregroundColor = foregroundColor
        self.cornerRadius = cornerRadius
        self.shortcut = shortcut
        self.modifiers = modifiers
    }
    
    var body: some View {
        let btn = Button(action: action) {
            HStack {
                if !icon.isEmpty {
                    Image(systemName: icon)
                }
                if !label.isEmpty {
                    Text(label)
                }
            }
        }
            .buttonStyle(RoundedButtonStyle(cornerRadius: 6, backgroundColor: backgroundColor, pressedBackgroundColor: pressedBackgroundColor))
            .cornerRadius(cornerRadius)
            .foregroundColor(foregroundColor)
        
        if let shortcut = shortcut {
            btn.keyboardShortcut(shortcut, modifiers: modifiers)
        } else {
            btn
        }
    }
}


struct PlainButton_Previews: PreviewProvider {
    static var previews: some View {
        PlainButton {
            
        }
    }
}
