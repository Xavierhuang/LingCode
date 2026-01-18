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
    
    /// Start watching a directory for file changes
    func startWatching(_ directoryURL: URL, callback: @escaping (URL) -> Void) {
        let path = directoryURL.path
        
        guard !watchedPaths.contains(path) else {
            // Already watching, just add callback
            if fileChangeCallbacks[path] == nil {
                fileChangeCallbacks[path] = []
            }
            fileChangeCallbacks[path]?.append(callback)
            return
        }
        
        watchedPaths.insert(path)
        
        if fileChangeCallbacks[path] == nil {
            fileChangeCallbacks[path] = []
        }
        fileChangeCallbacks[path]?.append(callback)
        
        // Create FSEventStream
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let pathsToWatch = [path] as CFArray
        let latency: CFTimeInterval = 0.1 // 100ms latency for near real-time updates
        
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
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            print("🔴 [FileWatcher] Failed to create FSEventStream for \(path)")
            return
        }
        
        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
        
        print("🟢 [FileWatcher] Started watching: \(path)")
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
        print("🟢 [FileWatcher] Stopped watching all directories")
    }
    
    /// Handle file system events
    private func handleFileEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer?,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>?
    ) {
        guard let paths = eventPaths?.assumingMemoryBound(to: Unmanaged<CFString>.self),
              let flags = eventFlags else {
            return
        }
        
        for i in 0..<numEvents {
            let path = paths[i].takeUnretainedValue() as String
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
