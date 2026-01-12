//
//  FileTreeView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI
import AppKit

struct FileTreeView: NSViewRepresentable {
    @Binding var rootURL: URL?
    @Binding var refreshTrigger: Bool
    let onFileSelect: (URL) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        print("🏗️ FileTreeView: makeNSView called with rootURL: \(rootURL?.path ?? "nil")")

        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()

        outlineView.headerView = nil
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.title = "Files"
        column.width = 250
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        // Enable double-click to open files
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        outlineView.target = context.coordinator

        // Also enable single-click selection
        outlineView.action = #selector(Coordinator.handleSingleClick(_:))

        // Enable right-click context menu
        // Create a placeholder menu that will be dynamically populated
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        outlineView.backgroundColor = .clear

        context.coordinator.outlineView = outlineView
        context.coordinator.onFileSelect = onFileSelect
        context.coordinator.rootURL = rootURL

        print("🏗️ FileTreeView: Coordinator rootURL set to: \(context.coordinator.rootURL?.path ?? "nil")")

        // Load initial data if rootURL is present
        if rootURL != nil {
            print("🏗️ FileTreeView: Loading initial data")
            outlineView.reloadData()
            outlineView.expandItem(nil, expandChildren: false)
        }

        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else {
            print("⚠️ FileTreeView: updateNSView - outline view is nil")
            return
        }

        print("🔄 FileTreeView: updateNSView called. Current coordinator rootURL: \(context.coordinator.rootURL?.path ?? "nil"), New rootURL: \(rootURL?.path ?? "nil")")

        // Update root URL if changed
        let rootChanged = context.coordinator.rootURL?.path != rootURL?.path

        if rootChanged {
            print("🔄 FileTreeView: Root URL changed from \(context.coordinator.rootURL?.path ?? "nil") to \(rootURL?.path ?? "nil")")
        }

        // ALWAYS update the coordinator's rootURL to match the binding
        context.coordinator.rootURL = rootURL

        // Reload data when root changes or refresh is triggered
        if rootChanged || context.coordinator.lastRefreshTrigger != refreshTrigger {
            context.coordinator.lastRefreshTrigger = refreshTrigger
            print("🔄 FileTreeView: Reloading outline view data, rootURL is: \(context.coordinator.rootURL?.path ?? "nil")")
            
            // Reload file items from disk when refresh is triggered
            if rootURL != nil {
                context.coordinator.reloadFileItems()
            }
            
            outlineView.reloadData()
            
            if rootURL != nil {
                outlineView.expandItem(nil, expandChildren: false)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var outlineView: NSOutlineView?
        var rootURL: URL?
        var onFileSelect: ((URL) -> Void)?
        var lastRefreshTrigger: Bool = false

        private var fileItems: [FileItem] = []

        override init() {
            super.init()
        }

        // MARK: - NSMenuDelegate

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()

            guard let outlineView = outlineView else { return }

            let clickedRow = outlineView.clickedRow

            if clickedRow >= 0, let fileItem = outlineView.item(atRow: clickedRow) as? FileItem {
                // Build context menu for file/folder
                buildFileMenu(menu, for: fileItem)
            } else {
                // Build context menu for empty area (root)
                buildRootMenu(menu)
            }
        }

        private func buildFileMenu(_ menu: NSMenu, for fileItem: FileItem) {
            // Open (files only)
            if !fileItem.isDirectory {
                let openItem = NSMenuItem(title: "Open", action: #selector(openFile), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = fileItem
                menu.addItem(openItem)
                menu.addItem(NSMenuItem.separator())
            }

            // Copy operations
            let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(copyPath), keyEquivalent: "")
            copyPathItem.target = self
            copyPathItem.representedObject = fileItem
            menu.addItem(copyPathItem)

            let copyRelativePathItem = NSMenuItem(title: "Copy Relative Path", action: #selector(copyRelativePath), keyEquivalent: "")
            copyRelativePathItem.target = self
            copyRelativePathItem.representedObject = fileItem
            menu.addItem(copyRelativePathItem)
            menu.addItem(NSMenuItem.separator())

            // System operations
            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
            revealItem.target = self
            revealItem.representedObject = fileItem
            menu.addItem(revealItem)

            if fileItem.isDirectory {
                let terminalItem = NSMenuItem(title: "Open in Terminal", action: #selector(openInTerminal), keyEquivalent: "")
                terminalItem.target = self
                terminalItem.representedObject = fileItem
                menu.addItem(terminalItem)
            }
            menu.addItem(NSMenuItem.separator())

            // File operations
            if !fileItem.isDirectory {
                let duplicateItem = NSMenuItem(title: "Duplicate", action: #selector(duplicateFile), keyEquivalent: "")
                duplicateItem.target = self
                duplicateItem.representedObject = fileItem
                menu.addItem(duplicateItem)
            }

            let renameItem = NSMenuItem(title: "Rename", action: #selector(renameFile), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = fileItem
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteFile), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = fileItem
            menu.addItem(deleteItem)

            // New operations (folders only)
            if fileItem.isDirectory {
                menu.addItem(NSMenuItem.separator())

                let newFileItem = NSMenuItem(title: "New File...", action: #selector(newFileInFolder), keyEquivalent: "")
                newFileItem.target = self
                newFileItem.representedObject = fileItem
                menu.addItem(newFileItem)

                let newFolderItem = NSMenuItem(title: "New Folder...", action: #selector(newFolderInFolder), keyEquivalent: "")
                newFolderItem.target = self
                newFolderItem.representedObject = fileItem
                menu.addItem(newFolderItem)
            }
        }

        private func buildRootMenu(_ menu: NSMenu) {
            let newFileItem = NSMenuItem(title: "New File", action: #selector(newFile), keyEquivalent: "")
            newFileItem.target = self
            menu.addItem(newFileItem)

            let newFolderItem = NSMenuItem(title: "New Folder", action: #selector(newFolder), keyEquivalent: "")
            newFolderItem.target = self
            menu.addItem(newFolderItem)

            menu.addItem(NSMenuItem.separator())

            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "")
            refreshItem.target = self
            menu.addItem(refreshItem)
        }
        
        // MARK: - Click Handlers
        
        @objc func handleSingleClick(_ sender: NSOutlineView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0,
                  let fileItem = sender.item(atRow: clickedRow) as? FileItem else { return }
            
            if !fileItem.isDirectory {
                // Open file on single click
                print("Single click on file: \(fileItem.url.path)")
                onFileSelect?(fileItem.url)
            }
        }
        
        @objc func handleDoubleClick(_ sender: NSOutlineView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0,
                  let fileItem = sender.item(atRow: clickedRow) as? FileItem else { return }
            
            if fileItem.isDirectory {
                // Toggle folder expansion on double click
                if sender.isItemExpanded(fileItem) {
                    sender.collapseItem(fileItem)
                } else {
                    sender.expandItem(fileItem)
                }
            } else {
                // Open file on double click
                print("Double click on file: \(fileItem.url.path)")
                onFileSelect?(fileItem.url)
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                guard let rootURL = rootURL else {
                    print("⚠️ FileTreeView: numberOfChildrenOfItem called with nil rootURL")
                    return 0
                }
                print("📂 FileTreeView: Loading items from root: \(rootURL.path)")
                fileItems = loadFileItems(at: rootURL)
                print("📂 FileTreeView: Loaded \(fileItems.count) items")
                return fileItems.count
            }

            if let fileItem = item as? FileItem {
                if fileItem.isDirectory && fileItem.children == nil {
                    fileItem.children = loadFileItems(at: fileItem.url)
                }
                return fileItem.children?.count ?? 0
            }

            return 0
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return fileItems[index]
            }
            
            if let fileItem = item as? FileItem {
                return fileItem.children?[index] ?? fileItem
            }
            
            return item!
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if let fileItem = item as? FileItem {
                return fileItem.isDirectory
            }
            return false
        }
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let fileItem = item as? FileItem else { return nil }
            
            let identifier = NSUserInterfaceItemIdentifier("FileCell")
            var cellView = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
                
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cellView?.addSubview(imageView)
                
                let textField = NSTextField()
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.translatesAutoresizingMaskIntoConstraints = false
                cellView?.addSubview(textField)
                
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
                
                cellView?.textField = textField
                cellView?.imageView = imageView
            }
            
            cellView?.textField?.stringValue = fileItem.name
            cellView?.imageView?.image = fileItem.icon
            
            return cellView
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            
            if selectedRow >= 0,
               let fileItem = outlineView.item(atRow: selectedRow) as? FileItem,
               !fileItem.isDirectory {
                onFileSelect?(fileItem.url)
            }
        }
        
        @objc private func newFile() {
            // TODO: Implement new file creation
        }
        
        @objc private func newFolder() {
            // TODO: Implement new folder creation
        }
        
        @objc private func refresh() {
            reloadFileItems()
            outlineView?.reloadData()
        }
        
        func reloadFileItems() {
            guard let rootURL = rootURL else { return }
            fileItems = loadFileItems(at: rootURL)
            print("🔄 FileTreeView: Reloaded \(fileItems.count) file items from: \(rootURL.path)")
        }
        
        @objc private func openFile(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem else { return }
            onFileSelect?(fileItem.url)
        }

        @objc private func copyPath(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fileItem.url.path, forType: .string)
        }

        @objc private func copyRelativePath(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem,
                  let rootURL = rootURL else { return }

            let relativePath = fileItem.url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(relativePath, forType: .string)
        }

        @objc private func revealInFinder(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem else { return }
            NSWorkspace.shared.selectFile(fileItem.url.path, inFileViewerRootedAtPath: "")
        }

        @objc private func openInTerminal(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem else { return }
            let script = """
            tell application "Terminal"
                do script "cd '\(fileItem.url.path)'"
                activate
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Error opening terminal: \(error)")
                }
            }
        }

        @objc private func duplicateFile(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem,
                  !fileItem.isDirectory else { return }

            let fileURL = fileItem.url
            let directory = fileURL.deletingLastPathComponent()
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let fileExtension = fileURL.pathExtension
            var copyNumber = 1
            var newURL: URL

            repeat {
                let newFilename = fileExtension.isEmpty
                    ? "\(filename) copy \(copyNumber)"
                    : "\(filename) copy \(copyNumber).\(fileExtension)"
                newURL = directory.appendingPathComponent(newFilename)
                copyNumber += 1
            } while FileManager.default.fileExists(atPath: newURL.path)

            do {
                try FileManager.default.copyItem(at: fileURL, to: newURL)
                refresh()
            } catch {
                print("Failed to duplicate file: \(error)")
            }
        }

        @objc private func renameFile(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem,
                  let outlineView = outlineView,
                  let row = (0..<outlineView.numberOfRows).first(where: {
                      outlineView.item(atRow: $0) as? FileItem === fileItem
                  }) else { return }

            // Start editing the cell
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.editColumn(0, row: row, with: nil, select: true)
        }

        @objc private func deleteFile(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem else { return }

            let alert = NSAlert()
            alert.messageText = "Delete \"\(fileItem.name)\"?"
            alert.informativeText = "This item will be moved to the Trash."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                do {
                    try FileManager.default.trashItem(at: fileItem.url, resultingItemURL: nil)
                    refresh()
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Could not delete file"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }

        @objc private func newFileInFolder(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem,
                  fileItem.isDirectory else { return }

            let alert = NSAlert()
            alert.messageText = "New File"
            alert.informativeText = "Enter the name for the new file:"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            input.placeholderString = "filename.txt"
            alert.accessoryView = input

            alert.window.initialFirstResponder = input

            if alert.runModal() == .alertFirstButtonReturn {
                let filename = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !filename.isEmpty else { return }

                let newFileURL = fileItem.url.appendingPathComponent(filename)

                do {
                    // Create empty file
                    try "".write(to: newFileURL, atomically: true, encoding: .utf8)
                    refresh()
                    // Open the new file
                    onFileSelect?(newFileURL)
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Could not create file"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }

        @objc private func newFolderInFolder(_ sender: NSMenuItem) {
            guard let fileItem = sender.representedObject as? FileItem,
                  fileItem.isDirectory else { return }

            let alert = NSAlert()
            alert.messageText = "New Folder"
            alert.informativeText = "Enter the name for the new folder:"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            input.placeholderString = "New Folder"
            alert.accessoryView = input

            alert.window.initialFirstResponder = input

            if alert.runModal() == .alertFirstButtonReturn {
                let foldername = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !foldername.isEmpty else { return }

                let newFolderURL = fileItem.url.appendingPathComponent(foldername)

                do {
                    try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
                    refresh()
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Could not create folder"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }
        
        private func loadFileItems(at url: URL) -> [FileItem] {
            var items: [FileItem] = []

            print("🔍 FileTreeView: Attempting to load contents of: \(url.path)")

            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            ) else {
                print("❌ FileTreeView: Failed to read directory contents")
                return items
            }

            print("✅ FileTreeView: Found \(contents.count) items in directory")

            let sortedContents = contents.sorted { url1, url2 in
                let isDir1 = (try? url1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let isDir2 = (try? url2.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

                if isDir1 != isDir2 {
                    return isDir1
                }

                return url1.lastPathComponent < url2.lastPathComponent
            }

            for url in sortedContents {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                items.append(FileItem(url: url, isDirectory: isDirectory))
                print("  📄 \(isDirectory ? "📁" : "📄") \(url.lastPathComponent)")
            }

            return items
        }
    }
}

class FileItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileItem]?
    
    var icon: NSImage {
        if isDirectory {
            return NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder") ?? NSImage()
        } else {
            if #available(macOS 12.0, *) {
                return NSWorkspace.shared.icon(forFile: url.path)
            } else {
                return NSWorkspace.shared.icon(forFileType: url.pathExtension)
            }
        }
    }
    
    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }
}

