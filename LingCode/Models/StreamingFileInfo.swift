//
//  StreamingFileInfo.swift
//  LingCode
//
//  Model for streaming file information
//

import Foundation

struct StreamingFileInfo: Identifiable {
    let id: String
    let path: String
    let name: String
    var language: String
    var content: String
    var isStreaming: Bool
    var changeSummary: String? // Summary of what changed
    var addedLines: Int = 0
    var removedLines: Int = 0
}

