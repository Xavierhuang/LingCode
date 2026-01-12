//
//  PTYTerminalService.swift
//  LingCode
//
//  Real PTY (pseudo-terminal) terminal implementation
//

import Foundation
import Darwin
import AppKit
import Combine

// PTY functions - use system posix_openpt

/// Real PTY terminal service with proper shell integration
class PTYTerminalService: ObservableObject {
    static let shared = PTYTerminalService()
    
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var process: Process?
    private var outputTask: DispatchWorkItem?
    
    private init() {}
    
    // MARK: - PTY Setup
    
    /// Open a PTY pair
    private func openPTY() -> Bool {
        var masterFD: Int32 = -1
        
        // Open master PTY
        masterFD = Darwin.posix_openpt(O_RDWR)
        guard masterFD >= 0 else {
            print("Failed to open PTY master: \(String(cString: strerror(errno)))")
            return false
        }
        
        // Grant access to slave
        guard grantpt(masterFD) == 0 else {
            close(masterFD)
            print("Failed to grant PTY: \(String(cString: strerror(errno)))")
            return false
        }
        
        // Unlock slave
        guard unlockpt(masterFD) == 0 else {
            close(masterFD)
            print("Failed to unlock PTY: \(String(cString: strerror(errno)))")
            return false
        }
        
        // Get slave name
        guard let slaveName = ptsname(masterFD) else {
            close(masterFD)
            print("Failed to get PTY slave name")
            return false
        }
        
        // Open slave
        let openedSlaveFD = open(slaveName, O_RDWR)
        guard openedSlaveFD >= 0 else {
            close(masterFD)
            print("Failed to open PTY slave: \(String(cString: strerror(errno)))")
            return false
        }
        
        self.masterFD = masterFD
        self.slaveFD = openedSlaveFD
        
        return true
    }
    
    // MARK: - Terminal Execution
    
    /// Start a shell in the PTY
    func startShell(workingDirectory: URL? = nil) {
        guard !isRunning else { return }
        
        // Close existing PTY if any
        closePTY()
        
        // Open new PTY
        guard openPTY() else {
            output += "Error: Failed to initialize terminal\n"
            return
        }
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l"] // Login shell
        
        // Set up file handles
        process.standardInput = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardOutput = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardError = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        
        // Set working directory
        if let wd = workingDirectory {
            process.currentDirectoryURL = wd
        }
        
        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env
        
        // Set terminal size
        var winsize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &winsize)
        
        do {
            try process.run()
            self.process = process
            self.isRunning = true
            
            // Start reading output
            startReadingOutput()
            
            // Monitor process
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.output += "\n[Process exited with code: \(process.terminationStatus)]\n"
                }
            }
        } catch {
            output += "Error starting shell: \(error.localizedDescription)\n"
            closePTY()
        }
    }
    
    /// Send input to the terminal
    func sendInput(_ input: String) {
        guard masterFD >= 0, isRunning else { return }
        
        let data = (input + "\n").data(using: .utf8) ?? Data()
        _ = data.withUnsafeBytes { bytes in
            write(masterFD, bytes.baseAddress, data.count)
        }
    }
    
    /// Start reading output from PTY
    private func startReadingOutput() {
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, self.masterFD >= 0 else { return }
            
            var buffer = [UInt8](repeating: 0, count: 4096)
            
            while self.isRunning {
                let bytesRead = read(self.masterFD, &buffer, buffer.count)
                
                if bytesRead > 0 {
                    if let string = String(data: Data(buffer.prefix(bytesRead)), encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.output += string
                        }
                    }
                } else if bytesRead == 0 {
                    // EOF
                    break
                } else if errno != EAGAIN && errno != EINTR {
                    // Error
                    break
                }
                
                // Small delay to prevent CPU spinning
                usleep(10000) // 10ms
            }
        }
        
        outputTask = task
        DispatchQueue.global(qos: .userInitiated).async(execute: task)
    }
    
    /// Stop the terminal
    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
        outputTask?.cancel()
        outputTask = nil
        closePTY()
    }
    
    /// Close PTY file descriptors
    private func closePTY() {
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
    }
    
    /// Set terminal size
    func setSize(rows: UInt16, cols: UInt16) {
        guard masterFD >= 0 else { return }
        var winsize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &winsize)
    }
    
    deinit {
        stop()
        closePTY()
    }
}

