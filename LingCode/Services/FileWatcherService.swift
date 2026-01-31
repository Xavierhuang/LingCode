//
//  FileWatcherService.swift
//  LingCode
//
//  File system watcher using FSEvents for incremental indexing
//  Only re-parses files that have changed, dramatically improving performance
//

import Foundation
import CoreServices

/// Service for watching file system changes using FSEvents
/// Enables incremental indexing - only re-parse files that have changed
class FileWatcherService {
    static let shared = FileWatcherService()
    
    private var streamRef: FSEventStreamRef?
    private var watchedPaths: Set<String> = []
    private var fileChangeCallbacks: [String: [(URL) -> Void]] = [:]
    private let callbackQueue = DispatchQueue(label: "com.lingcode.filewatcher", qos: .utility)
    
    private init() {}
    
    deinit {
        stopWatching()
    }
    
    /// Start watching a directory for file changes. Supports multiple directories in one stream.
    func startWatching(_ directoryURL: URL, callback: @escaping (URL) -> Void) {
        let path = directoryURL.path
        
        if fileChangeCallbacks[path] == nil {
            fileChangeCallbacks[path] = []
        }
        fileChangeCallbacks[path]?.append(callback)
        
        guard !watchedPaths.contains(path) else {
            return
        }
        
        watchedPaths.insert(path)
        restartStream()
    }
    
    /// Stop watching a specific directory
    func stopWatching(_ directoryURL: URL) {
        let path = directoryURL.path
        guard watchedPaths.contains(path) else { return }
        watchedPaths.remove(path)
        fileChangeCallbacks.removeValue(forKey: path)
        restartStream()
    }
    
    /// Stop watching all directories
    func stopWatching() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
        watchedPaths.removeAll()
        fileChangeCallbacks.removeAll()
    }
    
    private func restartStream() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
        
        guard !watchedPaths.isEmpty else { return }
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let pathsToWatch = Array(watchedPaths) as CFArray
        let latency: CFTimeInterval = 0.1
        
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
                watcher.handleFileEvents(
                    numEvents: numEvents,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags
                )
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            return
        }
        
        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
    }
    
    /// Handle file system events
    private func handleFileEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer?,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>?
    ) {
        guard let pathsPtr = eventPaths,
              let flags = eventFlags else {
            return
        }
        
        // 🟢 FIX: eventPaths is a CFArray when using kFSEventStreamCreateFlagUseCFTypes
        // Convert to CFArray and safely extract paths
        let pathsArray = unsafeBitCast(pathsPtr, to: CFArray.self)
        
        for i in 0..<numEvents {
            // Safely get CFString from CFArray
            // CFArrayGetValueAtIndex returns UnsafeRawPointer? which we cast to CFString
            guard let cfStringValue = CFArrayGetValueAtIndex(pathsArray, i) else {
                continue
            }
            let cfString = unsafeBitCast(cfStringValue, to: CFString.self)
            
            // Convert CFString to Swift String
            let path = cfString as String
            let flag = flags[i]
            
            // Only process file modifications (not directory changes)
            if flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
               flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
               flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                
                let fileURL = URL(fileURLWithPath: path)
                
                // Find which watched directory this file belongs to
                for watchedPath in watchedPaths {
                    if path.hasPrefix(watchedPath) {
                        // Notify all callbacks for this directory
                        if let callbacks = fileChangeCallbacks[watchedPath] {
                            for callback in callbacks {
                                callback(fileURL)
                            }
                        }
                        break
                    }
                }
            }
        }
    }
}
