//
//  StringExtensions.swift
//  Found
//
//  Created by lixindong on 2023/5/6.
//

import Foundation
import AppKit

extension String {
    var lineCount: Int {
        let font = NSFont.systemFont(ofSize: 14)
        let textRect = NSString(string: self).boundingRect(with: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil)
        let numberOfLines = Int(ceil(textRect.size.height / font.boundingRectForFont.height))
        print("Number of lines: \(numberOfLines)")
        return numberOfLines
    }
}
