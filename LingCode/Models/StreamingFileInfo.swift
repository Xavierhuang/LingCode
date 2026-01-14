//
//  StreamingFileInfo.swift
//  LingCode
//
//  Model for streaming file information
//

import Foundation

struct StreamingFileInfo: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    var language: String
    var content: String
    var isStreaming: Bool
    var changeSummary: String? // Summary of what changed
    var addedLines: Int = 0
    var removedLines: Int = 0
    
    // Equatable conformance for SwiftUI onChange support
    static func == (lhs: StreamingFileInfo, rhs: StreamingFileInfo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.path == rhs.path &&
               lhs.name == rhs.name &&
               lhs.language == rhs.language &&
               lhs.content == rhs.content &&
               lhs.isStreaming == rhs.isStreaming &&
               lhs.changeSummary == rhs.changeSummary &&
               lhs.addedLines == rhs.addedLines &&
               lhs.removedLines == rhs.removedLines
    }
}

