//
//  LingCodeApp.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

@main
struct LingCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup(id: "main") {
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
            
            // Window menu - keep the default window list AND add our custom items
            // This ensures windows appear in the menu for App Store compliance
            CommandGroup(after: .windowList) {
                Divider()
                Button("Show Main Window") {
                    WindowManager.shared.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
    }
}

// App delegate to handle window closing behavior
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure at least one window is open on launch
        if NSApplication.shared.windows.isEmpty {
            openMainWindow()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, open a new one
            openMainWindow()
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window closes - keep app running
        return false
    }
    
    func openMainWindow() {
        WindowManager.shared.showMainWindow()
    }
}

// Window manager to handle window operations
class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    func showMainWindow() {
        // Activate the app first
        NSApp.activate(ignoringOtherApps: true)
        
        // Get all windows
        let allWindows = NSApplication.shared.windows
        
        // Strategy 1: Find and restore a visible, non-minimized window
        if let visibleWindow = allWindows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            visibleWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Strategy 2: Restore a minimized window
        if let minimizedWindow = allWindows.first(where: { $0.isMiniaturized }) {
            minimizedWindow.deminiaturize(nil)
            minimizedWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Strategy 3: If no visible or minimized windows exist, always create a NEW window
        // This ensures that when all windows are closed, we get a fresh new window
        // instead of trying to restore hidden/closed windows
        createNewWindow()
    }
    
    private func createNewWindow() {
        // Create a new window with ContentView
        // This ensures a window is always created, even when all windows are closed
        DispatchQueue.main.async {
            let contentView = ContentView()
            let hostingController = NSHostingController(rootView: contentView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.contentViewController = hostingController
            window.title = "LingCode"
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            // Set window restoration identifier to match WindowGroup id
            // This helps macOS restore the window properly
            window.identifier = NSUserInterfaceItemIdentifier("main")
            
            // Make sure window is properly added to the app
            window.isReleasedWhenClosed = false
        }
    }
}
