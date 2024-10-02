//
//  PlainButton.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/16.
//

import SwiftUI
import KeyboardShortcuts

struct PlainButton: View, Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let width: CGFloat?
    let height: CGFloat?
    var backgroundColor: Color
    var pressedBackgroundColor: Color
    var foregroundColor: Color
    let cornerRadius: CGFloat
    var shortcut: KeyEquivalent?
    var modifiers: EventModifiers = []
    var autoShowShortcutHelp: Bool
    var showLabel: Bool
    let action: () -> Void
    @EnvironmentObject var globalConfig: GlobalConfig
    
    @State private var hovered = false

    init(icon: String = "",
         label: String = "",
         width: CGFloat? = nil,
         height: CGFloat? = nil,
         backgroundColor: Color = .white,
         pressedBackgroundColor: Color = Color.gray.opacity(0.1),
         foregroundColor: Color = Color.text,
         cornerRadius: CGFloat = 6,
         shortcut: KeyEquivalent? = nil,
         modifiers: EventModifiers = [],
         autoShowShortcutHelp: Bool = true,
         showLabel: Bool = true,
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
        self.autoShowShortcutHelp = autoShowShortcutHelp
        self.showLabel = showLabel
        self.width = width
        self.height = height
    }
    
    var body: some View {
        let btn = Button(action: action) {
            HStack {
                if !icon.isEmpty {
                    Image(systemName: icon)
                }
                if showLabel && !label.isEmpty {
                    Text(LocalizedStringKey(label))
                        .lineLimit(1)
                }
                if autoShowShortcutHelp, let shortcut = shortcut, globalConfig.showShortcutHelp  {
                    Text(shortcut.description.uppercased())
                        .modifier(EventModifierSymbolModifier(modifiers))
                        .lineLimit(1)
                }
            }
        }
            .frame(minHeight: 32)
            .frame(width: width, height: height)
            .buttonStyle(RoundedButtonStyle(cornerRadius: cornerRadius, backgroundColor: backgroundColor, pressedBackgroundColor: pressedBackgroundColor, width: width, height: height))
            .cornerRadius(cornerRadius)
            .foregroundColor(foregroundColor)
            .onHover { hover in
                hovered = hover
            }
        
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
