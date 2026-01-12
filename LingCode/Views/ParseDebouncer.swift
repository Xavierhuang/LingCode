//
//  ParseDebouncer.swift
//  LingCode
//
//  Helper class to manage debounced parsing tasks
//

import Foundation

class ParseDebouncer {
    private var parseTask: Task<Void, Never>?
    private let debounceInterval: UInt64
    var lastParsedContentHash: Int = 0
    
    init(debounceInterval: UInt64 = 200_000_000) {
        self.debounceInterval = debounceInterval
    }
    
    func debounce(action: @escaping () async -> Void) {
        parseTask?.cancel()
        parseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceInterval)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    
    func cancel() {
        parseTask?.cancel()
        parseTask = nil
    }
}
