//
//  Extensions.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit

extension String {
    func ranges(of searchString: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = self.startIndex
        
        while searchStartIndex < self.endIndex,
              let range = self.range(of: searchString, options: options, range: searchStartIndex..<self.endIndex) {
            ranges.append(range)
            searchStartIndex = range.upperBound
        }
        
        return ranges
    }
}

extension NSColor {
    static var editorBackground: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                return NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
            default:
                return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            }
        }
    }
    
    static var editorText: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                return NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            default:
                return NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            }
        }
    }
}








