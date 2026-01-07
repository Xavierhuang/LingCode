//
//  LingCodeApp.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

@main
struct LingCodeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            
            CommandGroup(after: .saveItem) {
                Button("Save As...") {
                    // Handled by view model
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    // Handled by ContentView
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Find and Replace") {
                    // Handled by ContentView
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                
                Button("Go to Line...") {
                    // Handled by ContentView
                }
                .keyboardShortcut("g", modifiers: [.command, .control])
            }
            
            CommandGroup(after: .toolbar) {
                Button("Command Palette...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowCommandPalette"), object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}
