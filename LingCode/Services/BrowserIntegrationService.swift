//
//  BrowserIntegrationService.swift
//  LingCode
//
//  Browser integration for controlling Chrome/Safari for web app testing
//

import Foundation
import Combine
import AppKit

// MARK: - Browser Types

enum BrowserType: String, CaseIterable {
    case chrome = "Google Chrome"
    case safari = "Safari"
    case firefox = "Firefox"
    case edge = "Microsoft Edge"
    
    var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .safari: return "com.apple.Safari"
        case .firefox: return "org.mozilla.firefox"
        case .edge: return "com.microsoft.edgemac"
        }
    }
    
    var isInstalled: Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}

// MARK: - Browser State

struct BrowserState {
    let url: String
    let title: String
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

struct BrowserTab: Identifiable {
    let id: Int
    let title: String
    let url: String
    let isActive: Bool
}

struct ElementInfo: Identifiable {
    let id = UUID()
    let tag: String
    let text: String?
    let attributes: [String: String]
    let rect: CGRect?
    let selector: String
}

struct ConsoleMessage: Identifiable {
    let id = UUID()
    let level: ConsoleLevel
    let message: String
    let source: String?
    let timestamp: Date
}

enum ConsoleLevel: String {
    case log, info, warn, error, debug
}

// MARK: - Browser Integration Service

class BrowserIntegrationService: ObservableObject {
    static let shared = BrowserIntegrationService()
    
    @Published var isConnected: Bool = false
    @Published var currentBrowser: BrowserType = .chrome
    @Published var currentState: BrowserState?
    @Published var tabs: [BrowserTab] = []
    @Published var consoleMessages: [ConsoleMessage] = []
    @Published var lastError: String?
    
    private var debuggingPort: Int = 9222
    private var webSocketTask: URLSessionWebSocketTask?
    private var messageId: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    
    private init() {
        // Check which browsers are available
        detectAvailableBrowsers()
    }
    
    // MARK: - Browser Detection
    
    func detectAvailableBrowsers() -> [BrowserType] {
        return BrowserType.allCases.filter { $0.isInstalled }
    }
    
    func getDefaultBrowser() -> BrowserType {
        // Check if Chrome is available (preferred for DevTools Protocol)
        if BrowserType.chrome.isInstalled {
            return .chrome
        }
        // Fall back to Safari
        if BrowserType.safari.isInstalled {
            return .safari
        }
        return .chrome
    }
    
    // MARK: - Connection Management
    
    /// Launch browser with debugging enabled
    func launchWithDebugging(browser: BrowserType = .chrome, url: String? = nil) async throws {
        currentBrowser = browser
        
        switch browser {
        case .chrome:
            try await launchChromeWithDebugging(url: url)
        case .safari:
            try await launchSafariWithDebugging(url: url)
        default:
            throw BrowserError.unsupportedBrowser
        }
    }
    
    private func launchChromeWithDebugging(url: String?) async throws {
        // Kill any existing Chrome debugging sessions
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "remote-debugging-port=\(debuggingPort)"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        // Wait a moment
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Launch Chrome with remote debugging
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        
        var args = [
            "-na", "Google Chrome",
            "--args",
            "--remote-debugging-port=\(debuggingPort)",
            "--no-first-run",
            "--no-default-browser-check"
        ]
        
        if let url = url {
            args.append(url)
        }
        
        task.arguments = args
        try task.run()
        
        // Wait for Chrome to start
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Connect to DevTools
        try await connectToDevTools()
    }
    
    private func launchSafariWithDebugging(url: String?) async throws {
        // Safari uses different automation (AppleScript / Safari Web Inspector)
        // For now, just open Safari
        let script = """
        tell application "Safari"
            activate
            if (count of windows) = 0 then
                make new document
            end if
            \(url != nil ? "set URL of document 1 to \"\(url!)\"" : "")
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            throw BrowserError.appleScriptError(error.description)
        }
        
        await MainActor.run {
            isConnected = true
        }
    }
    
    private func connectToDevTools() async throws {
        // Get list of debuggable pages
        let listURL = URL(string: "http://localhost:\(debuggingPort)/json/list")!
        
        let (data, _) = try await URLSession.shared.data(from: listURL)
        
        guard let pages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstPage = pages.first,
              let webSocketDebuggerUrl = firstPage["webSocketDebuggerUrl"] as? String,
              let wsURL = URL(string: webSocketDebuggerUrl) else {
            throw BrowserError.noDebuggablePages
        }
        
        // Connect via WebSocket
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessages()
        
        // Enable necessary domains
        _ = try await sendCommand("Page.enable")
        _ = try await sendCommand("Runtime.enable")
        _ = try await sendCommand("Console.enable")
        _ = try await sendCommand("DOM.enable")
        
        await MainActor.run {
            isConnected = true
        }
        
        // Get initial state
        await refreshState()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        Task { @MainActor in
            isConnected = false
            currentState = nil
            tabs = []
        }
    }
    
    // MARK: - Navigation
    
    func navigate(to url: String) async throws {
        switch currentBrowser {
        case .chrome:
            _ = try await sendCommand("Page.navigate", params: ["url": url])
        case .safari:
            let script = """
            tell application "Safari"
                set URL of document 1 to "\(url)"
            end tell
            """
            try executeAppleScript(script)
        default:
            throw BrowserError.unsupportedBrowser
        }
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await refreshState()
    }
    
    func goBack() async throws {
        switch currentBrowser {
        case .chrome:
            _ = try await sendCommand("Page.navigateToHistoryEntry", params: ["entryId": -1])
        case .safari:
            try executeAppleScript("tell application \"Safari\" to go back document 1")
        default:
            throw BrowserError.unsupportedBrowser
        }
    }
    
    func goForward() async throws {
        switch currentBrowser {
        case .chrome:
            _ = try await sendCommand("Page.navigateToHistoryEntry", params: ["entryId": 1])
        case .safari:
            try executeAppleScript("tell application \"Safari\" to go forward document 1")
        default:
            throw BrowserError.unsupportedBrowser
        }
    }
    
    func reload() async throws {
        switch currentBrowser {
        case .chrome:
            _ = try await sendCommand("Page.reload")
        case .safari:
            try executeAppleScript("tell application \"Safari\" to do JavaScript \"location.reload()\" in document 1")
        default:
            throw BrowserError.unsupportedBrowser
        }
    }
    
    // MARK: - Interaction
    
    func click(selector: String) async throws {
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (el) {
                el.click();
                return true;
            }
            return false;
        })()
        """
        
        let result = try await executeJavaScript(js)
        if result as? Bool != true {
            throw BrowserError.elementNotFound(selector)
        }
    }
    
    func type(selector: String, text: String) async throws {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (el) {
                el.focus();
                el.value = '\(escapedText)';
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
            }
            return false;
        })()
        """
        
        let result = try await executeJavaScript(js)
        if result as? Bool != true {
            throw BrowserError.elementNotFound(selector)
        }
    }
    
    func select(selector: String, value: String) async throws {
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (el && el.tagName === 'SELECT') {
                el.value = '\(value.replacingOccurrences(of: "'", with: "\\'"))';
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
            }
            return false;
        })()
        """
        
        let result = try await executeJavaScript(js)
        if result as? Bool != true {
            throw BrowserError.elementNotFound(selector)
        }
    }
    
    func hover(selector: String) async throws {
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (el) {
                const event = new MouseEvent('mouseover', { bubbles: true, cancelable: true });
                el.dispatchEvent(event);
                return true;
            }
            return false;
        })()
        """
        
        let result = try await executeJavaScript(js)
        if result as? Bool != true {
            throw BrowserError.elementNotFound(selector)
        }
    }
    
    func scroll(x: Int = 0, y: Int) async throws {
        let js = "window.scrollBy(\(x), \(y))"
        _ = try await executeJavaScript(js)
    }
    
    func scrollToElement(selector: String) async throws {
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (el) {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                return true;
            }
            return false;
        })()
        """
        
        let result = try await executeJavaScript(js)
        if result as? Bool != true {
            throw BrowserError.elementNotFound(selector)
        }
    }
    
    // MARK: - Data Extraction
    
    func getElementText(selector: String) async throws -> String {
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            return el ? el.textContent : null;
        })()
        """
        
        if let result = try await executeJavaScript(js) as? String {
            return result
        }
        throw BrowserError.elementNotFound(selector)
    }
    
    func getElementAttribute(selector: String, attribute: String) async throws -> String? {
        let js = """
        (function() {
            const el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            return el ? el.getAttribute('\(attribute)') : null;
        })()
        """
        
        return try await executeJavaScript(js) as? String
    }
    
    func getElements(selector: String) async throws -> [ElementInfo] {
        let js = """
        (function() {
            const elements = document.querySelectorAll('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            return Array.from(elements).map((el, i) => ({
                tag: el.tagName.toLowerCase(),
                text: el.textContent?.substring(0, 100),
                id: el.id,
                className: el.className,
                href: el.href,
                rect: el.getBoundingClientRect()
            }));
        })()
        """
        
        guard let results = try await executeJavaScript(js) as? [[String: Any]] else {
            return []
        }
        
        return results.enumerated().map { index, dict in
            var attributes: [String: String] = [:]
            if let id = dict["id"] as? String, !id.isEmpty {
                attributes["id"] = id
            }
            if let className = dict["className"] as? String, !className.isEmpty {
                attributes["class"] = className
            }
            if let href = dict["href"] as? String {
                attributes["href"] = href
            }
            
            var rect: CGRect?
            if let rectDict = dict["rect"] as? [String: Double] {
                rect = CGRect(
                    x: rectDict["x"] ?? 0,
                    y: rectDict["y"] ?? 0,
                    width: rectDict["width"] ?? 0,
                    height: rectDict["height"] ?? 0
                )
            }
            
            return ElementInfo(
                tag: dict["tag"] as? String ?? "unknown",
                text: dict["text"] as? String,
                attributes: attributes,
                rect: rect,
                selector: "\(selector):nth-child(\(index + 1))"
            )
        }
    }
    
    func getPageHTML() async throws -> String {
        let js = "document.documentElement.outerHTML"
        return try await executeJavaScript(js) as? String ?? ""
    }
    
    func screenshot() async throws -> NSImage? {
        guard currentBrowser == .chrome else {
            throw BrowserError.unsupportedOperation
        }
        
        let result = try await sendCommand("Page.captureScreenshot", params: ["format": "png"])
        
        guard let dataString = result["data"] as? String,
              let data = Data(base64Encoded: dataString) else {
            return nil
        }
        
        return NSImage(data: data)
    }
    
    // MARK: - JavaScript Execution
    
    func executeJavaScript(_ script: String) async throws -> Any? {
        switch currentBrowser {
        case .chrome:
            let result = try await sendCommand("Runtime.evaluate", params: [
                "expression": script,
                "returnByValue": true
            ])
            
            if let exceptionDetails = result["exceptionDetails"] as? [String: Any],
               let exception = exceptionDetails["exception"] as? [String: Any],
               let description = exception["description"] as? String {
                throw BrowserError.javaScriptError(description)
            }
            
            if let resultObj = result["result"] as? [String: Any] {
                return resultObj["value"]
            }
            return nil
            
        case .safari:
            let escapedScript = script
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            
            let appleScript = """
            tell application "Safari"
                do JavaScript "\(escapedScript)" in document 1
            end tell
            """
            
            let script = NSAppleScript(source: appleScript)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            
            if let error = error {
                throw BrowserError.appleScriptError(error.description)
            }
            
            return result?.stringValue
            
        default:
            throw BrowserError.unsupportedBrowser
        }
    }
    
    // MARK: - State Management
    
    func refreshState() async {
        guard currentBrowser == .chrome, isConnected else { return }
        
        do {
            // Get current URL and title
            let js = "JSON.stringify({ url: location.href, title: document.title })"
            if let result = try await executeJavaScript(js) as? String,
               let data = result.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                
                await MainActor.run {
                    currentState = BrowserState(
                        url: info["url"] ?? "",
                        title: info["title"] ?? "",
                        isLoading: false,
                        canGoBack: true,
                        canGoForward: true
                    )
                }
            }
        } catch {
            print("Browser: Failed to refresh state: \(error)")
        }
    }
    
    // MARK: - Chrome DevTools Protocol
    
    private func sendCommand(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard let webSocketTask = webSocketTask else {
            throw BrowserError.notConnected
        }
        
        messageId += 1
        let id = messageId
        
        var message: [String: Any] = ["id": id, "method": method]
        if let params = params {
            message["params"] = params
        }
        
        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask.send(.string(string))
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            
            // Timeout
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = pendingRequests.removeValue(forKey: id) {
                    cont.resume(throwing: BrowserError.timeout)
                }
            }
        }
    }
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessages()
                
            case .failure(let error):
                print("Browser WebSocket error: \(error)")
                Task { @MainActor in
                    self?.isConnected = false
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Handle response to our request
        if let id = json["id"] as? Int,
           let continuation = pendingRequests.removeValue(forKey: id) {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                continuation.resume(throwing: BrowserError.protocolError(message))
            } else if let result = json["result"] as? [String: Any] {
                continuation.resume(returning: result)
            } else {
                continuation.resume(returning: [:])
            }
            return
        }
        
        // Handle events
        if let method = json["method"] as? String,
           let params = json["params"] as? [String: Any] {
            handleEvent(method: method, params: params)
        }
    }
    
    private func handleEvent(method: String, params: [String: Any]) {
        switch method {
        case "Console.messageAdded":
            if let message = params["message"] as? [String: Any],
               let text = message["text"] as? String,
               let levelStr = message["level"] as? String {
                let level = ConsoleLevel(rawValue: levelStr) ?? .log
                let consoleMsg = ConsoleMessage(
                    level: level,
                    message: text,
                    source: message["source"] as? String,
                    timestamp: Date()
                )
                Task { @MainActor in
                    consoleMessages.append(consoleMsg)
                    if consoleMessages.count > 100 {
                        consoleMessages = Array(consoleMessages.suffix(100))
                    }
                }
            }
            
        case "Page.loadEventFired":
            Task {
                await refreshState()
            }
            
        default:
            break
        }
    }
    
    // MARK: - AppleScript Helpers
    
    private func executeAppleScript(_ script: String) throws {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            throw BrowserError.appleScriptError(error.description)
        }
    }
}

// MARK: - Errors

enum BrowserError: Error, LocalizedError {
    case unsupportedBrowser
    case unsupportedOperation
    case notConnected
    case noDebuggablePages
    case timeout
    case elementNotFound(String)
    case javaScriptError(String)
    case protocolError(String)
    case appleScriptError(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedBrowser: return "This browser is not supported"
        case .unsupportedOperation: return "This operation is not supported for this browser"
        case .notConnected: return "Not connected to browser"
        case .noDebuggablePages: return "No debuggable pages found"
        case .timeout: return "Request timed out"
        case .elementNotFound(let selector): return "Element not found: \(selector)"
        case .javaScriptError(let msg): return "JavaScript error: \(msg)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .appleScriptError(let msg): return "AppleScript error: \(msg)"
        }
    }
}
