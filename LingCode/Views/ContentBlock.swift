//
//  ContentBlock.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

struct ContentBlock: Identifiable {
    let id = UUID()
    let content: String
    let isCode: Bool
    let language: String?
    var isTerminalCommand: Bool = false
}



