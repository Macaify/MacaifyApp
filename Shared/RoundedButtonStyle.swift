//
//  RoundedButtonStyle.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/13.
//

import SwiftUI

struct RoundedButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    var backgroundColor: Color = .white
    var pressedBackgroundColor: Color = Color.gray.opacity(0.1)
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, height: height)
            .background(
                Group {
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(pressedBackgroundColor)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(backgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            )
    }
}

struct RoundedButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        Button(action: {
                    print("Button pressed")
                }) {
                    Text("press_me")
                        .font(.headline)
                        .foregroundColor(.black)
                }
                .buttonStyle(RoundedButtonStyle(cornerRadius: 8))
    }
}
