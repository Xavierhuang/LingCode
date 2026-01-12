//
//  KeyBindingsService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit
import Combine

struct KeyBinding: Identifiable, Codable {
    let id: UUID
    let command: String
    let keys: [String]
    let modifiers: [String]
    var isCustom: Bool
    
    init(id: UUID = UUID(), command: String, keys: [String], modifiers: [String], isCustom: Bool = false) {
        self.id = id
        self.command = command
        self.keys = keys
        self.modifiers = modifiers
        self.isCustom = isCustom
    }
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers.contains("command") { parts.append("Cmd") }
        if modifiers.contains("shift") { parts.append("Shift") }
        if modifiers.contains("option") { parts.append("Opt") }
        if modifiers.contains("control") { parts.append("Ctrl") }
        
        parts.append(contentsOf: keys.map { $0.uppercased() })
        
        return parts.joined(separator: "+")
    }
}

class KeyBindingsService: ObservableObject {
    static let shared = KeyBindingsService()
    
    @Published var bindings: [KeyBinding] = []
    
    private let userDefaultsKey = "CustomKeyBindings"
    
    private init() {
        loadDefaultBindings()
        loadCustomBindings()
    }
    
    private func loadDefaultBindings() {
        bindings = [
            KeyBinding(command: "newFile", keys: ["n"], modifiers: ["command"]),
            KeyBinding(command: "openFile", keys: ["o"], modifiers: ["command"]),
            KeyBinding(command: "saveFile", keys: ["s"], modifiers: ["command"]),
            KeyBinding(command: "saveAll", keys: ["s"], modifiers: ["command", "option"]),
            KeyBinding(command: "closeTab", keys: ["w"], modifiers: ["command"]),
            KeyBinding(command: "find", keys: ["f"], modifiers: ["command"]),
            KeyBinding(command: "findInFiles", keys: ["f"], modifiers: ["command", "shift"]),
            KeyBinding(command: "replace", keys: ["h"], modifiers: ["command"]),
            KeyBinding(command: "goToLine", keys: ["g"], modifiers: ["command", "control"]),
            KeyBinding(command: "goToDefinition", keys: ["d"], modifiers: ["command"]),
            KeyBinding(command: "findReferences", keys: ["r"], modifiers: ["command", "shift"]),
            KeyBinding(command: "quickOpen", keys: ["p"], modifiers: ["command"]),
            KeyBinding(command: "commandPalette", keys: ["p"], modifiers: ["command", "shift"]),
            KeyBinding(command: "toggleSidebar", keys: ["b"], modifiers: ["command"]),
            KeyBinding(command: "toggleTerminal", keys: ["`"], modifiers: ["command"]),
            KeyBinding(command: "aiEdit", keys: ["k"], modifiers: ["command"]),
            KeyBinding(command: "aiChat", keys: ["l"], modifiers: ["command"]),
            KeyBinding(command: "formatDocument", keys: ["f"], modifiers: ["command", "shift", "option"]),
            KeyBinding(command: "toggleComment", keys: ["/"], modifiers: ["command"]),
            KeyBinding(command: "indentLine", keys: ["]"], modifiers: ["command"]),
            KeyBinding(command: "outdentLine", keys: ["["], modifiers: ["command"]),
            KeyBinding(command: "duplicateLine", keys: ["d"], modifiers: ["command", "shift"]),
            KeyBinding(command: "deleteLine", keys: ["k"], modifiers: ["command", "shift"]),
            KeyBinding(command: "moveLineUp", keys: ["arrowup"], modifiers: ["option"]),
            KeyBinding(command: "moveLineDown", keys: ["arrowdown"], modifiers: ["option"]),
            KeyBinding(command: "selectWord", keys: ["d"], modifiers: ["command"]),
            KeyBinding(command: "selectLine", keys: ["l"], modifiers: ["command"]),
            KeyBinding(command: "selectAll", keys: ["a"], modifiers: ["command"]),
            KeyBinding(command: "undo", keys: ["z"], modifiers: ["command"]),
            KeyBinding(command: "redo", keys: ["z"], modifiers: ["command", "shift"]),
            KeyBinding(command: "copy", keys: ["c"], modifiers: ["command"]),
            KeyBinding(command: "paste", keys: ["v"], modifiers: ["command"]),
            KeyBinding(command: "cut", keys: ["x"], modifiers: ["command"]),
            KeyBinding(command: "splitRight", keys: ["\\"], modifiers: ["command"]),
            KeyBinding(command: "splitDown", keys: ["\\"], modifiers: ["command", "shift"]),
            KeyBinding(command: "focusNextEditor", keys: ["tab"], modifiers: ["command"]),
            KeyBinding(command: "focusPrevEditor", keys: ["tab"], modifiers: ["command", "shift"]),
            KeyBinding(command: "zoomIn", keys: ["="], modifiers: ["command"]),
            KeyBinding(command: "zoomOut", keys: ["-"], modifiers: ["command"]),
            KeyBinding(command: "resetZoom", keys: ["0"], modifiers: ["command"])
        ]
    }
    
    private func loadCustomBindings() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let custom = try? JSONDecoder().decode([KeyBinding].self, from: data) {
            // Merge custom bindings
            for customBinding in custom {
                if let index = bindings.firstIndex(where: { $0.command == customBinding.command }) {
                    bindings[index] = customBinding
                } else {
                    bindings.append(customBinding)
                }
            }
        }
    }
    
    func saveCustomBindings() {
        let customBindings = bindings.filter { $0.isCustom }
        if let data = try? JSONEncoder().encode(customBindings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    func updateBinding(_ binding: KeyBinding) {
        var updatedBinding = binding
        updatedBinding.isCustom = true
        
        if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
            bindings[index] = updatedBinding
        }
        
        saveCustomBindings()
    }
    
    func resetToDefault(command: String) {
        loadDefaultBindings()
        loadCustomBindings()
        
        // Remove the custom binding for this command
        bindings.removeAll { $0.command == command && $0.isCustom }
        saveCustomBindings()
    }
    
    func getBinding(for command: String) -> KeyBinding? {
        return bindings.first { $0.command == command }
    }
    
    func getCommand(for keys: [String], modifiers: [String]) -> String? {
        return bindings.first { binding in
            Set(binding.keys) == Set(keys) && Set(binding.modifiers) == Set(modifiers)
        }?.command
    }
}

