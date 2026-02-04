//
//  DeploymentService.swift
//  LingCode
//
//  One-click deployment service with platform integrations and pre-deploy validation.
//  Supports Vercel, Netlify, Railway, Fly.io, Heroku, and Docker.
//

import Foundation
import Combine

@MainActor
class DeploymentService: ObservableObject {
    static let shared = DeploymentService()
    
    // MARK: - Published State
    
    @Published var status: DeploymentStatus = .idle
    @Published var currentConfig: DeploymentConfig?
    @Published var availablePlatforms: [DeploymentPlatform] = []
    @Published var detectedProjectType: ProjectType = .unknown
    @Published var configs: [DeploymentConfig] = []
    @Published var history: [DeploymentHistoryEntry] = []
    @Published var validationResult: DeploymentValidationResult = .empty
    @Published var deploymentLogs: String = ""
    @Published var lastDeploymentURL: String?
    
    // MARK: - Private
    
    private let terminalService = TerminalExecutionService.shared
    private let gitService = GitService.shared
    private var projectURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var currentProcess: Process?
    
    private let historyURL: URL
    private let configsURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        
        historyURL = lingcodeDir.appendingPathComponent("deployment_history.json")
        configsURL = lingcodeDir.appendingPathComponent("deployment_configs.json")
        
        loadHistory()
        loadConfigs()
    }
    
    // MARK: - Project Setup
    
    func setProject(_ url: URL) {
        projectURL = url
        detectProjectType()
        detectAvailablePlatforms()
        loadWorkspaceDeployConfig()
    }
    
    // MARK: - Project Detection
    
    private func detectProjectType() {
        guard let url = projectURL else {
            detectedProjectType = .unknown
            return
        }
        
        let fm = FileManager.default
        
        // Check package.json for JS frameworks
        let packageJsonURL = url.appendingPathComponent("package.json")
        if fm.fileExists(atPath: packageJsonURL.path),
           let data = try? Data(contentsOf: packageJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            let deps = (json["dependencies"] as? [String: Any]) ?? [:]
            let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
            let allDeps = deps.merging(devDeps) { $1 }
            
            if allDeps["next"] != nil {
                detectedProjectType = .nextjs
                return
            }
            if allDeps["nuxt"] != nil {
                detectedProjectType = .nuxt
                return
            }
            if allDeps["@sveltejs/kit"] != nil || allDeps["svelte"] != nil {
                detectedProjectType = .svelte
                return
            }
            if allDeps["vue"] != nil {
                detectedProjectType = .vue
                return
            }
            if allDeps["react"] != nil {
                detectedProjectType = .react
                return
            }
            
            detectedProjectType = .nodejs
            return
        }
        
        // Python
        if fm.fileExists(atPath: url.appendingPathComponent("requirements.txt").path) ||
           fm.fileExists(atPath: url.appendingPathComponent("pyproject.toml").path) {
            detectedProjectType = .python
            return
        }
        
        // Rust
        if fm.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path) {
            detectedProjectType = .rust
            return
        }
        
        // Go
        if fm.fileExists(atPath: url.appendingPathComponent("go.mod").path) {
            detectedProjectType = .go
            return
        }
        
        // Swift
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            detectedProjectType = .swift
            return
        }
        
        // Static site (has index.html)
        if fm.fileExists(atPath: url.appendingPathComponent("index.html").path) {
            detectedProjectType = .staticSite
            return
        }
        
        detectedProjectType = .unknown
    }
    
    private func detectAvailablePlatforms() {
        var platforms: [DeploymentPlatform] = []
        
        for platform in DeploymentPlatform.allCases {
            if let cli = platform.cliCommand {
                let result = terminalService.executeSync("which \(cli)")
                if result.exitCode == 0 && !result.output.isEmpty {
                    platforms.append(platform)
                }
            } else if platform == .custom {
                platforms.append(platform)
            }
        }
        
        // Sort by recommended for project type
        let recommended = Set(detectedProjectType.recommendedPlatforms)
        availablePlatforms = platforms.sorted { p1, p2 in
            let r1 = recommended.contains(p1)
            let r2 = recommended.contains(p2)
            if r1 != r2 { return r1 }
            return p1.rawValue < p2.rawValue
        }
    }
    
    // MARK: - Configuration
    
    func createConfig(for platform: DeploymentPlatform) -> DeploymentConfig {
        var config = DeploymentConfig(
            platform: platform,
            buildCommand: detectedProjectType.defaultBuildCommand,
            outputDirectory: detectedProjectType.defaultOutputDirectory,
            autoDetected: true
        )
        
        // Set branch from current git branch
        config.branch = gitService.currentBranch.isEmpty ? "main" : gitService.currentBranch
        
        return config
    }
    
    func saveConfig(_ config: DeploymentConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        saveConfigs()
    }
    
    func deleteConfig(_ id: UUID) {
        configs.removeAll { $0.id == id }
        saveConfigs()
    }
    
    // MARK: - Validation
    
    func validate(config: DeploymentConfig) async -> DeploymentValidationResult {
        guard let url = projectURL else {
            return DeploymentValidationResult(
                testsPass: false,
                buildSucceeds: false,
                envVarsValid: false,
                cliAvailable: false,
                errors: ["No project selected"],
                warnings: []
            )
        }
        
        status = .validating
        var result = DeploymentValidationResult.empty
        result.errors = []
        result.warnings = []
        
        // Check CLI availability
        if let cli = config.platform.cliCommand {
            let cliCheck = terminalService.executeSync("which \(cli)")
            result.cliAvailable = cliCheck.exitCode == 0
            if !result.cliAvailable {
                result.errors.append("\(config.platform.rawValue) CLI not found. Install with: \(config.platform.installInstructions)")
            }
        } else {
            result.cliAvailable = true
        }
        
        // Check environment variables
        result.envVarsValid = validateEnvironmentVariables(config)
        if !result.envVarsValid {
            result.warnings.append("Some environment variables may be missing")
        }
        
        // Run tests (optional, check if test script exists)
        status = .runningTests
        let testResult = await runTests(in: url)
        result.testsPass = testResult
        if !testResult {
            result.warnings.append("Tests did not pass (deployment can continue)")
        }
        
        // Run build
        status = .building
        if let buildCmd = config.buildCommand {
            let buildResult = await runBuild(command: buildCmd, in: url)
            result.buildSucceeds = buildResult.success
            if !buildResult.success {
                result.errors.append("Build failed: \(buildResult.error ?? "Unknown error")")
            }
        } else {
            result.buildSucceeds = true
        }
        
        validationResult = result
        status = result.isValid ? .idle : .failed(error: result.errors.first ?? "Validation failed")
        
        return result
    }
    
    private func validateEnvironmentVariables(_ config: DeploymentConfig) -> Bool {
        // Check if required env vars are set
        // For now, just check if .env exists and warn if using production with .env.local
        guard let url = projectURL else { return true }
        
        let envFile = url.appendingPathComponent(".env")
        let envLocalFile = url.appendingPathComponent(".env.local")
        
        if config.environment == .production {
            if FileManager.default.fileExists(atPath: envLocalFile.path) {
                // .env.local typically shouldn't be used in production
                return true // Warning only
            }
        }
        
        return true
    }
    
    private func runTests(in directory: URL) async -> Bool {
        // Check if test script exists
        let packageJsonURL = directory.appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: packageJsonURL.path),
           let data = try? Data(contentsOf: packageJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any],
           scripts["test"] != nil {
            
            let result = await runCommand("npm test", in: directory, timeout: 120)
            return result.exitCode == 0
        }
        
        // No test script, consider it passing
        return true
    }
    
    private func runBuild(command: String, in directory: URL) async -> (success: Bool, error: String?) {
        let result = await runCommand(command, in: directory, timeout: 300)
        return (result.exitCode == 0, result.exitCode == 0 ? nil : result.output)
    }
    
    // MARK: - Deployment
    
    func deploy(config: DeploymentConfig, skipValidation: Bool = false) async -> DeploymentResult {
        guard let url = projectURL else {
            let result = DeploymentResult(
                config: config,
                status: .failed(error: "No project selected")
            )
            addToHistory(result)
            return result
        }
        
        currentConfig = config
        deploymentLogs = ""
        let startTime = Date()
        
        // Validation (unless skipped)
        if !skipValidation {
            let validation = await validate(config: config)
            if !validation.isValid {
                let result = DeploymentResult(
                    config: config,
                    status: .failed(error: validation.errors.first ?? "Validation failed"),
                    buildLogs: deploymentLogs,
                    startTime: startTime,
                    endTime: Date()
                )
                addToHistory(result)
                return result
            }
        }
        
        // Run pre-deploy commands
        for cmd in config.preDeployCommands {
            appendLog("[Pre-deploy] Running: \(cmd)")
            let result = await runCommand(cmd, in: url, timeout: 120)
            if result.exitCode != 0 {
                let deployResult = DeploymentResult(
                    config: config,
                    status: .failed(error: "Pre-deploy command failed: \(cmd)"),
                    buildLogs: deploymentLogs,
                    startTime: startTime,
                    endTime: Date()
                )
                addToHistory(deployResult)
                return deployResult
            }
        }
        
        // Deploy
        status = .deploying
        appendLog("[Deploy] Starting deployment to \(config.platform.rawValue)...")
        
        let deployCommand = getDeployCommand(for: config)
        appendLog("[Deploy] Command: \(deployCommand)")
        
        let deployResult = await runCommand(deployCommand, in: url, timeout: 600)
        
        // Parse deployment URL from output
        let deployedURL = parseDeploymentURL(from: deployResult.output, platform: config.platform)
        lastDeploymentURL = deployedURL
        
        appendLog(deployResult.output)
        
        if deployResult.exitCode != 0 {
            status = .failed(error: "Deployment failed")
            let result = DeploymentResult(
                config: config,
                status: .failed(error: deployResult.output),
                buildLogs: deploymentLogs,
                deployLogs: deployResult.output,
                startTime: startTime,
                endTime: Date()
            )
            addToHistory(result)
            return result
        }
        
        // Run post-deploy commands
        for cmd in config.postDeployCommands {
            appendLog("[Post-deploy] Running: \(cmd)")
            _ = await runCommand(cmd, in: url, timeout: 120)
        }
        
        status = .success(url: deployedURL)
        let result = DeploymentResult(
            config: config,
            status: .success(url: deployedURL),
            url: deployedURL,
            buildLogs: deploymentLogs,
            deployLogs: deployResult.output,
            startTime: startTime,
            endTime: Date()
        )
        addToHistory(result)
        
        return result
    }
    
    private func getDeployCommand(for config: DeploymentConfig) -> String {
        if let custom = config.customDeployCommand, !custom.isEmpty {
            return custom
        }
        
        var envVars = ""
        if !config.environmentVariables.isEmpty {
            envVars = config.environmentVariables.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + " "
        }
        
        switch config.platform {
        case .vercel:
            var cmd = "\(envVars)vercel"
            if config.environment == .production {
                cmd += " --prod"
            }
            return cmd
            
        case .netlify:
            var cmd = "\(envVars)netlify deploy"
            if config.environment == .production {
                cmd += " --prod"
            }
            if let dir = config.outputDirectory {
                cmd += " --dir=\(dir)"
            }
            return cmd
            
        case .railway:
            return "\(envVars)railway up"
            
        case .fly:
            return "\(envVars)fly deploy"
            
        case .heroku:
            return "git push heroku \(config.branch):main"
            
        case .docker:
            return "docker compose up -d --build"
            
        case .custom:
            return config.customDeployCommand ?? "echo 'No deploy command configured'"
        }
    }
    
    private func parseDeploymentURL(from output: String, platform: DeploymentPlatform) -> String? {
        let patterns: [String]
        
        switch platform {
        case .vercel:
            patterns = [
                #"https://[a-zA-Z0-9-]+\.vercel\.app"#,
                #"https://[a-zA-Z0-9-]+\.vercel\.sh"#
            ]
        case .netlify:
            patterns = [
                #"https://[a-zA-Z0-9-]+\.netlify\.app"#,
                #"https://[a-zA-Z0-9-]+--[a-zA-Z0-9-]+\.netlify\.app"#
            ]
        case .railway:
            patterns = [
                #"https://[a-zA-Z0-9-]+\.railway\.app"#
            ]
        case .fly:
            patterns = [
                #"https://[a-zA-Z0-9-]+\.fly\.dev"#
            ]
        case .heroku:
            patterns = [
                #"https://[a-zA-Z0-9-]+\.herokuapp\.com"#
            ]
        default:
            patterns = [
                #"https?://[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}"#
            ]
        }
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range, in: output) {
                return String(output[range])
            }
        }
        
        return nil
    }
    
    // MARK: - Command Execution
    
    private func runCommand(_ command: String, in directory: URL, timeout: TimeInterval) async -> (exitCode: Int32, output: String) {
        return await withCheckedContinuation { continuation in
            var output = ""
            var completed = false
            
            terminalService.execute(
                command,
                workingDirectory: directory,
                environment: nil,
                onOutput: { text in
                    output += text
                    Task { @MainActor in
                        self.appendLog(text)
                    }
                },
                onError: { error in
                    output += error
                    Task { @MainActor in
                        self.appendLog("[ERROR] \(error)")
                    }
                },
                onComplete: { exitCode in
                    if !completed {
                        completed = true
                        continuation.resume(returning: (exitCode, output))
                    }
                }
            )
            
            // Timeout handling
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if !completed {
                    completed = true
                    self.terminalService.cancel()
                    continuation.resume(returning: (-1, output + "\n[TIMEOUT] Command timed out after \(Int(timeout)) seconds"))
                }
            }
        }
    }
    
    private func appendLog(_ text: String) {
        deploymentLogs += text
        if !text.hasSuffix("\n") {
            deploymentLogs += "\n"
        }
    }
    
    // MARK: - Cancel
    
    func cancelDeployment() {
        terminalService.cancel()
        status = .cancelled
    }
    
    // MARK: - History
    
    private func addToHistory(_ result: DeploymentResult) {
        let entry = DeploymentHistoryEntry(
            platform: result.config.platform,
            environment: result.config.environment,
            branch: result.config.branch,
            commitHash: getCommitHash(),
            commitMessage: getCommitMessage(),
            url: result.url,
            success: result.status == .success(url: result.url),
            errorMessage: {
                if case .failed(let error) = result.status {
                    return error
                }
                return nil
            }(),
            timestamp: result.startTime,
            duration: result.duration
        )
        
        history.insert(entry, at: 0)
        
        // Keep only last 50 entries
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        
        saveHistory()
    }
    
    private func getCommitHash() -> String? {
        guard let url = projectURL else { return nil }
        let result = terminalService.executeSync("git rev-parse --short HEAD", workingDirectory: url)
        return result.exitCode == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
    
    private func getCommitMessage() -> String? {
        guard let url = projectURL else { return nil }
        let result = terminalService.executeSync("git log -1 --pretty=%s", workingDirectory: url)
        return result.exitCode == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
    
    // MARK: - Persistence
    
    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyURL.path),
              let data = try? Data(contentsOf: historyURL),
              let loaded = try? JSONDecoder().decode([DeploymentHistoryEntry].self, from: data) else {
            return
        }
        history = loaded
    }
    
    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL)
    }
    
    private func loadConfigs() {
        guard FileManager.default.fileExists(atPath: configsURL.path),
              let data = try? Data(contentsOf: configsURL),
              let loaded = try? JSONDecoder().decode([DeploymentConfig].self, from: data) else {
            return
        }
        configs = loaded
    }
    
    private func saveConfigs() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: configsURL)
    }
    
    // MARK: - WORKSPACE.md Integration
    
    private func loadWorkspaceDeployConfig() {
        guard let url = projectURL else { return }
        
        let workspaceMdURL = url.appendingPathComponent("WORKSPACE.md")
        guard FileManager.default.fileExists(atPath: workspaceMdURL.path),
              let content = try? String(contentsOf: workspaceMdURL, encoding: .utf8) else {
            return
        }
        
        // Parse ## Deployment section
        guard let deploymentRange = content.range(of: "## Deployment", options: .caseInsensitive) else {
            return
        }
        
        let afterDeployment = content[deploymentRange.upperBound...]
        let nextSectionIndex = afterDeployment.range(of: "\n## ")?.lowerBound ?? afterDeployment.endIndex
        let deploymentSection = String(afterDeployment[..<nextSectionIndex])
        
        // Parse key-value pairs
        var platform: DeploymentPlatform?
        var branch = "main"
        var buildCommand: String?
        var environment = DeploymentEnvironment.production
        var preDeployCommands: [String] = []
        
        let lines = deploymentSection.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            
            let content = String(trimmed.dropFirst(2))
            let parts = content.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            
            let key = parts[0].lowercased()
            let value = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "target", "platform":
                platform = DeploymentPlatform.allCases.first { $0.rawValue.lowercased() == value.lowercased() }
            case "branch":
                branch = value
            case "build command", "build":
                buildCommand = value
            case "environment", "env":
                environment = DeploymentEnvironment.allCases.first { $0.rawValue.lowercased() == value.lowercased() } ?? .production
            case "pre-deploy", "predeploy":
                preDeployCommands.append(value)
            default:
                break
            }
        }
        
        // Create config if platform was specified
        if let platform = platform {
            let config = DeploymentConfig(
                platform: platform,
                name: "WORKSPACE.md Config",
                branch: branch,
                buildCommand: buildCommand ?? detectedProjectType.defaultBuildCommand,
                outputDirectory: detectedProjectType.defaultOutputDirectory,
                environment: environment,
                preDeployCommands: preDeployCommands,
                autoDetected: true
            )
            
            // Add to configs if not already present
            if !configs.contains(where: { $0.platform == platform && $0.name == config.name }) {
                configs.insert(config, at: 0)
                currentConfig = config
            }
        }
    }
    
    // MARK: - Quick Deploy
    
    /// One-click deploy with auto-detected or saved config
    func quickDeploy() async -> DeploymentResult? {
        // Use current config, or first available, or create new
        let config: DeploymentConfig
        
        if let current = currentConfig {
            config = current
        } else if let first = configs.first {
            config = first
        } else if let recommended = availablePlatforms.first {
            config = createConfig(for: recommended)
        } else {
            status = .failed(error: "No deployment platform available. Please install a CLI (vercel, netlify, etc.)")
            return nil
        }
        
        return await deploy(config: config)
    }
}
