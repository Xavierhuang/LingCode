//
//  DeploymentAutoConfigService.swift
//  LingCode
//
//  Auto-detects the deployment platform from a pasted token / SSH string / URL,
//  builds a DeploymentConfig, persists it to WORKSPACE.md via ApplyCodeService,
//  then fires off DeploymentService.deploy().
//

import Foundation

// MARK: - Auto-config result

struct AutoConfigResult {
    let platform: DeploymentPlatform
    let config: DeploymentConfig
    /// Human-readable explanation shown in MagicDeployView status area.
    let detectionSummary: String
}

// MARK: - Errors

enum AutoConfigError: LocalizedError {
    case emptyInput
    case unrecognizedInput(String)
    case noProjectURL
    case workspaceMdWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Please paste a token, SSH string, or deployment URL."
        case .unrecognizedInput(let hint):
            return "Could not detect a platform. \(hint)"
        case .noProjectURL:
            return "No workspace folder is open."
        case .workspaceMdWriteFailed(let reason):
            return "Could not save deployment config to WORKSPACE.md: \(reason)"
        }
    }
}

// MARK: - Service

final class DeploymentAutoConfigService {
    static let shared = DeploymentAutoConfigService()
    private init() {}

    private let applyService = ApplyCodeService.shared

    // MARK: - Public entry point

    /// Parse `input`, detect platform, write to WORKSPACE.md, then deploy.
    /// Throws `AutoConfigError` if detection or the file write fails.
    /// The deploy itself runs through `DeploymentService` so the caller can
    /// observe `DeploymentService.shared.status` for progress updates.
    @MainActor
    func analyzeAndConfigure(
        input: String,
        projectURL: URL,
        sshPassword: String = "",
        pemFilePath: String = "",
        onStep: @escaping (String) -> Void
    ) async throws -> AutoConfigResult {

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AutoConfigError.emptyInput }

        onStep("Auto-detecting platform...")
        let detected = try await detectPlatform(input: trimmed, projectURL: projectURL, sshPassword: sshPassword, pemFilePath: pemFilePath)
        onStep("Detected \(detected.platform.rawValue) — \(detected.detectionSummary)")

        onStep("Configuring credentials...")
        var config = detected.config

        onStep("Saving to WORKSPACE.md...")
        try await writeWorkspaceMd(config: config, projectURL: projectURL)

        DeploymentService.shared.setProject(projectURL)
        DeploymentService.shared.currentConfig = config
        DeploymentService.shared.saveConfig(config)

        onStep("Starting deployment pipeline...")
        Task {
            _ = await DeploymentService.shared.deploy(config: config)
        }

        return AutoConfigResult(
            platform: detected.platform,
            config: config,
            detectionSummary: detected.detectionSummary
        )
    }

    // MARK: - Platform detection

    private func detectPlatform(input: String, projectURL: URL, sshPassword: String = "", pemFilePath: String = "") async throws -> AutoConfigResult {
        let lower = input.lowercased()
        let fm = FileManager.default

        // ── Vercel token (starts with "Bearer " or matches vercel token format)
        // Vercel tokens: typically "xxxxxxxxxxx" or contain "vercel"
        let isVercelToken = lower.contains("vercel")
            || lower.hasPrefix("token_")
            || matchesPattern(#"^[a-zA-Z0-9]{24,}$"#, in: input)
            && fm.fileExists(atPath: projectURL.appendingPathComponent("next.config.js").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("next.config.ts").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("vercel.json").path)

        if isVercelToken && (lower.contains("vercel") || hasFile("vercel.json", in: projectURL) || hasNextConfig(in: projectURL)) {
            let projectType = detectProjectType(in: projectURL)
            let config = DeploymentConfig(
                platform: .vercel,
                name: "Vercel (Magic Deploy)",
                buildCommand: projectType.defaultBuildCommand,
                outputDirectory: projectType.defaultOutputDirectory,
                environment: .production,
                environmentVariables: ["VERCEL_TOKEN": input],
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .vercel,
                config: config,
                detectionSummary: "Vercel token detected\(hasNextConfig(in: projectURL) ? " + Next.js project" : "")"
            )
        }

        // ── Netlify token / site ID
        // Netlify personal access tokens look like a 40-char hex string
        // Site IDs are UUID-format
        if lower.contains("netlify") || isUUID(input) || isHex40(input) {
            let projectType = detectProjectType(in: projectURL)
            var envVars: [String: String] = [:]
            if isUUID(input) {
                envVars["NETLIFY_SITE_ID"] = input
            } else {
                envVars["NETLIFY_AUTH_TOKEN"] = input
            }
            let config = DeploymentConfig(
                platform: .netlify,
                name: "Netlify (Magic Deploy)",
                buildCommand: projectType.defaultBuildCommand,
                outputDirectory: projectType.defaultOutputDirectory ?? "dist",
                environment: .production,
                environmentVariables: envVars,
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .netlify,
                config: config,
                detectionSummary: isUUID(input) ? "Netlify Site ID detected" : "Netlify token detected"
            )
        }

        // ── Railway token  (railway tokens contain "railway" or look like JWT)
        if lower.contains("railway") || isJWT(input) {
            let config = DeploymentConfig(
                platform: .railway,
                name: "Railway (Magic Deploy)",
                buildCommand: detectProjectType(in: projectURL).defaultBuildCommand,
                environment: .production,
                environmentVariables: ["RAILWAY_TOKEN": input],
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .railway,
                config: config,
                detectionSummary: "Railway token detected"
            )
        }

        // ── Fly.io token
        if lower.contains("fly") || lower.hasPrefix("fo1_") || lower.hasPrefix("fo2_") {
            let config = DeploymentConfig(
                platform: .fly,
                name: "Fly.io (Magic Deploy)",
                buildCommand: detectProjectType(in: projectURL).defaultBuildCommand,
                environment: .production,
                environmentVariables: ["FLY_API_TOKEN": input],
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .fly,
                config: config,
                detectionSummary: "Fly.io token detected"
            )
        }

        // ── Heroku API key (32-char hex with dashes)
        if lower.contains("heroku") || matchesPattern(#"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"#, in: lower) {
            let config = DeploymentConfig(
                platform: .heroku,
                name: "Heroku (Magic Deploy)",
                buildCommand: detectProjectType(in: projectURL).defaultBuildCommand,
                environment: .production,
                environmentVariables: ["HEROKU_API_KEY": input],
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .heroku,
                config: config,
                detectionSummary: "Heroku API key detected"
            )
        }

        // ── SSH string: user@host, user:password@host, user@host:port
        if matchesPattern(#"^[\w\-\.]+(@|:[\w\S]+@)[\w\-\.]+(:\d+)?$"#, in: input)
            || matchesPattern(#"^[\w\-\.]+(@|:[\w\S]+@)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$"#, in: input) {

            // Parse user, host, port, and inline password from formats:
            //   user@host, user@host:port, user:password@host, user:password@host:port
            let sshTarget = SSHTarget(raw: input, passwordOverride: sshPassword, pemKeyPath: pemFilePath)
            let projectType = detectProjectType(in: projectURL)
            let deployScript = buildSSHDeployScript(
                target: sshTarget,
                projectURL: projectURL,
                projectType: projectType
            )
            let config = DeploymentConfig(
                platform: .docker,
                name: "SSH Deploy (Magic Deploy)",
                buildCommand: nil,   // build runs remotely inside the script
                environment: .production,
                postDeployCommands: [],
                customDeployCommand: deployScript,
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .docker,
                config: config,
                detectionSummary: "SSH \(sshTarget.userAtHost) — \(projectType.rawValue)"
            )
        }

        // ── Generic HTTPS URL — treat as custom
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            let config = DeploymentConfig(
                platform: .custom,
                name: "Custom Deploy (Magic Deploy)",
                environment: .production,
                postDeployCommands: [],
                customDeployCommand: "curl -X POST \(input)",
                autoDetected: true
            )
            return AutoConfigResult(
                platform: .custom,
                config: config,
                detectionSummary: "Webhook URL detected"
            )
        }

        throw AutoConfigError.unrecognizedInput(
            "Try pasting a Vercel/Netlify/Railway token, a Fly.io token, a Heroku API key, or an SSH string like user@host."
        )
    }

    // MARK: - WORKSPACE.md write

    private func writeWorkspaceMd(config: DeploymentConfig, projectURL: URL) async throws {
        let mdURL = projectURL.appendingPathComponent("WORKSPACE.md")
        let existing = (try? String(contentsOf: mdURL, encoding: .utf8)) ?? ""
        let updated = upsertDeploymentSection(in: existing, config: config)

        return try await withCheckedThrowingContinuation { continuation in
            let change = CodeChange(
                id: UUID(),
                filePath: mdURL.path,
                fileName: "WORKSPACE.md",
                operationType: existing.isEmpty ? .create : .update,
                originalContent: existing.isEmpty ? nil : existing,
                newContent: updated,
                lineRange: nil,
                language: "markdown"
            )
            applyService.writeChanges([change], workspaceURL: projectURL) { result in
                if result.success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: AutoConfigError.workspaceMdWriteFailed(
                            result.errors.first ?? "Unknown error"
                        )
                    )
                }
            }
        }
    }

    /// Insert or replace the `## Deployment` section in a WORKSPACE.md string.
    private func upsertDeploymentSection(in existing: String, config: DeploymentConfig) -> String {
        let section = buildDeploymentSection(config: config)

        guard !existing.isEmpty else {
            return "# Workspace\n\n\(section)"
        }

        // Replace existing ## Deployment block if present
        if let range = existing.range(of: "## Deployment", options: .caseInsensitive) {
            let before = String(existing[..<range.lowerBound])
            let rest = String(existing[range.lowerBound...])
            // Find the next ## heading after the Deployment section
            let afterHeader = rest.dropFirst("## Deployment".count)
            if let nextSection = afterHeader.range(of: "\n## ") {
                let tail = String(afterHeader[nextSection.lowerBound...])
                return before + section + "\n" + tail
            } else {
                return before + section
            }
        }

        // Append at the end
        return existing.trimmingCharacters(in: .newlines) + "\n\n" + section + "\n"
    }

    private func buildDeploymentSection(config: DeploymentConfig) -> String {
        var lines = ["## Deployment", ""]
        lines.append("- Target: \(config.platform.rawValue)")
        lines.append("- Environment: \(config.environment.rawValue)")
        lines.append("- Branch: \(config.branch)")
        if let build = config.buildCommand {
            lines.append("- Build Command: \(build)")
        }
        if let output = config.outputDirectory {
            lines.append("- Output Directory: \(output)")
        }
        if let custom = config.customDeployCommand {
            lines.append("- Deploy Command: \(custom)")
        }
        for cmd in config.preDeployCommands {
            lines.append("- Pre-Deploy: \(cmd)")
        }
        lines.append("- Auto-Detected: true")
        lines.append("- Last Configured: \(ISO8601DateFormatter().string(from: Date()))")
        return lines.joined(separator: "\n")
    }

    // MARK: - SSH target parsing

    private struct SSHTarget {
        let user: String
        let host: String
        let port: Int
        let password: String  // empty = use SSH key
        let pemKeyPath: String  // path to .pem file (AWS EC2); empty = default SSH key

        /// user@host (no password, safe to log)
        var userAtHost: String { "\(user)@\(host)" }

        /// ssh -p <port> user@host  (no password)
        var sshConnectArgs: String {
            port == 22 ? userAtHost : "-p \(port) \(userAtHost)"
        }

        init(raw: String, passwordOverride: String = "", pemKeyPath: String = "") {
            // Supported formats:
            //   user@host
            //   user@host:port
            //   user:password@host
            //   user:password@host:port
            var working = raw

            // Extract port from trailing :port
            var parsedPort = 22
            let lastColon = working.lastIndex(of: ":")
            let atIndex = working.firstIndex(of: "@")
            if let lc = lastColon, let at = atIndex, lc > at {
                let portStr = String(working[working.index(after: lc)...])
                if let p = Int(portStr) {
                    parsedPort = p
                    working = String(working[..<lc])
                }
            }
            port = parsedPort

            // Split user[:password]@host
            let atParts = working.components(separatedBy: "@")
            let hostPart = atParts.last ?? ""
            let userPart = atParts.dropLast().joined(separator: "@")

            host = hostPart
            if userPart.contains(":") {
                let up = userPart.components(separatedBy: ":")
                user = up[0].isEmpty ? "root" : up[0]
                password = passwordOverride.isEmpty ? up.dropFirst().joined(separator: ":") : passwordOverride
            } else {
                user = userPart.isEmpty ? "root" : userPart
                password = passwordOverride
            }
            self.pemKeyPath = pemKeyPath
        }
    }

    // MARK: - SSH deploy script builder

    /// Generates a fully self-contained bash script that:
    ///  1. Checks for sshpass and installs it locally if a password is provided
    ///  2. Rsyncs the project to the server
    ///  3. On the server: installs all runtime dependencies for the project type
    ///  4. Builds the project
    ///  5. Starts/restarts with pm2 (Node) or gunicorn (Python) or the appropriate runtime
    ///  6. Sets up nginx as a reverse proxy if not already configured
    private func buildSSHDeployScript(target: SSHTarget, projectURL: URL, projectType: ProjectType) -> String {
        let fm = FileManager.default
        let projectName = projectURL.lastPathComponent
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let deployDir = "/var/www/\(projectName)"

        let hasDockerfile = fm.fileExists(atPath: projectURL.appendingPathComponent("Dockerfile").path)
        let hasCompose = fm.fileExists(atPath: projectURL.appendingPathComponent("docker-compose.yml").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("docker-compose.yaml").path)
        let hasPM2Config = fm.fileExists(atPath: projectURL.appendingPathComponent("ecosystem.config.js").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("ecosystem.config.cjs").path)

        // Build the SSH prefix (with sshpass if password provided, or -i pem if key provided)
        let sshPrefix: String
        let scpPrefix: String
        let rsyncPrefix: String
        if !target.pemKeyPath.isEmpty {
            let portFlag = target.port == 22 ? "" : "-p \(target.port) "
            let pemFlag = "-i '\(target.pemKeyPath)' -o StrictHostKeyChecking=no "
            sshPrefix = "ssh \(pemFlag)\(portFlag)\(target.userAtHost)"
            scpPrefix = "scp \(pemFlag)\(target.port == 22 ? "" : "-P \(target.port) ")"
            rsyncPrefix = "rsync -avz --delete -e 'ssh \(pemFlag)\(target.port == 22 ? "" : "-p \(target.port)")' "
        } else if target.password.isEmpty {
            let portFlag = target.port == 22 ? "" : "-p \(target.port) "
            sshPrefix = "ssh \(portFlag)\(target.userAtHost)"
            scpPrefix = "scp \(target.port == 22 ? "" : "-P \(target.port) ")"
            rsyncPrefix = "rsync -avz --delete \(target.port == 22 ? "" : "-e 'ssh -p \(target.port)' ")"
        } else {
            let portFlag = target.port == 22 ? "" : "-p \(target.port) "
            sshPrefix = "sshpass -p '\(target.password)' ssh \(portFlag)\(target.userAtHost)"
            scpPrefix = "sshpass -p '\(target.password)' scp \(target.port == 22 ? "" : "-P \(target.port) ")"
            rsyncPrefix = "sshpass -p '\(target.password)' rsync -avz --delete \(target.port == 22 ? "" : "-e 'ssh -p \(target.port)' ")"
        }

        // ── Remote setup commands per project type ────────────────────────
        let remoteSetup: String
        let remoteBuild: String
        let remoteStart: String

        if hasCompose {
            // Docker Compose — simplest path
            remoteSetup = """
                # Install Docker if missing
                if ! command -v docker &>/dev/null; then
                  echo "[deploy] Installing Docker..."
                  curl -fsSL https://get.docker.com | sh
                  sudo usermod -aG docker $USER
                fi
                if ! docker compose version &>/dev/null 2>&1; then
                  sudo apt-get install -y docker-compose-plugin 2>/dev/null || true
                fi
                """
            remoteBuild = "docker compose pull 2>/dev/null; docker compose build --parallel"
            remoteStart = "docker compose down --remove-orphans; docker compose up -d"

        } else if hasDockerfile {
            remoteSetup = """
                if ! command -v docker &>/dev/null; then
                  echo "[deploy] Installing Docker..."
                  curl -fsSL https://get.docker.com | sh
                fi
                """
            remoteBuild = "docker build -t \(projectName):latest ."
            remoteStart = "docker stop \(projectName) 2>/dev/null; docker rm \(projectName) 2>/dev/null; docker run -d --name \(projectName) --restart unless-stopped -p 3000:3000 \(projectName):latest"

        } else {
            switch projectType {
            case .react, .nextjs, .vue, .nuxt, .svelte, .nodejs:
                let buildCmd: String
                let startCmd: String
                switch projectType {
                case .nextjs:
                    buildCmd = "npm run build"
                    startCmd = "npm start"
                case .react, .vue, .svelte:
                    buildCmd = "npm run build"
                    startCmd = "npx serve -s dist -l 3000 2>/dev/null || npx serve -s build -l 3000"
                case .nuxt:
                    buildCmd = "npm run build"
                    startCmd = "node .output/server/index.mjs"
                default:
                    buildCmd = "npm install --omit=dev 2>/dev/null || npm install --production"
                    startCmd = "node ."
                }
                let pm2StartCmd = hasPM2Config
                    ? "pm2 startOrRestart ecosystem.config.js --env production"
                    : "pm2 startOrRestart \(projectName) --name \(projectName) -- \(startCmd) || pm2 start --name \(projectName) \"\(startCmd)\""

                remoteSetup = """
                    # Install Node.js via nvm if missing
                    if ! command -v node &>/dev/null; then
                      echo "[deploy] Installing Node.js..."
                      export NVM_DIR="$HOME/.nvm"
                      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
                      . "$NVM_DIR/nvm.sh"
                      nvm install --lts
                      nvm use --lts
                      nvm alias default node
                    fi
                    export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
                    # Install pm2 globally if missing
                    if ! command -v pm2 &>/dev/null; then
                      echo "[deploy] Installing pm2..."
                      npm install -g pm2
                      pm2 startup | tail -1 | bash 2>/dev/null || true
                    fi
                    # Install nginx if missing
                    if ! command -v nginx &>/dev/null; then
                      echo "[deploy] Installing nginx..."
                      sudo apt-get update -qq && sudo apt-get install -y nginx
                    fi
                    """
                remoteBuild = """
                    export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
                    npm ci --prefer-offline 2>/dev/null || npm install
                    \(buildCmd)
                    """
                remoteStart = """
                    export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
                    \(pm2StartCmd)
                    pm2 save
                    # Configure nginx reverse proxy if not already done
                    if [ ! -f /etc/nginx/sites-enabled/\(projectName) ]; then
                      echo "[deploy] Configuring nginx..."
                      sudo tee /etc/nginx/sites-available/\(projectName) > /dev/null << 'NGINX'
                    server {
                        listen 80;
                        server_name _;
                        location / {
                            proxy_pass http://localhost:3000;
                            proxy_http_version 1.1;
                            proxy_set_header Upgrade \\$http_upgrade;
                            proxy_set_header Connection 'upgrade';
                            proxy_set_header Host \\$host;
                            proxy_set_header X-Real-IP \\$remote_addr;
                            proxy_cache_bypass \\$http_upgrade;
                        }
                    }
                    NGINX
                      sudo ln -sf /etc/nginx/sites-available/\(projectName) /etc/nginx/sites-enabled/\(projectName)
                      sudo nginx -t && sudo systemctl reload nginx
                    fi
                    """

            case .python:
                remoteSetup = """
                    # Install Python3 / pip if missing
                    if ! command -v python3 &>/dev/null; then
                      echo "[deploy] Installing Python3..."
                      sudo apt-get update -qq && sudo apt-get install -y python3 python3-pip python3-venv
                    fi
                    if ! command -v nginx &>/dev/null; then
                      sudo apt-get update -qq && sudo apt-get install -y nginx
                    fi
                    """
                remoteBuild = """
                    python3 -m venv .venv
                    source .venv/bin/activate
                    pip install -r requirements.txt --quiet
                    """
                remoteStart = """
                    source .venv/bin/activate
                    # Use gunicorn if available, else uvicorn, else flask dev server
                    if pip show gunicorn &>/dev/null; then
                      pkill -f gunicorn 2>/dev/null; nohup gunicorn -w 4 -b 0.0.0.0:5000 app:app &>/tmp/\(projectName).log &
                    elif pip show uvicorn &>/dev/null; then
                      pkill -f uvicorn 2>/dev/null; nohup uvicorn main:app --host 0.0.0.0 --port 5000 &>/tmp/\(projectName).log &
                    else
                      pkill -f "python3 app" 2>/dev/null; nohup python3 app.py &>/tmp/\(projectName).log &
                    fi
                    """

            case .rust:
                remoteSetup = """
                    if ! command -v cargo &>/dev/null; then
                      echo "[deploy] Installing Rust..."
                      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                      source "$HOME/.cargo/env"
                    fi
                    source "$HOME/.cargo/env"
                    """
                remoteBuild = """
                    source "$HOME/.cargo/env"
                    cargo build --release
                    """
                remoteStart = """
                    source "$HOME/.cargo/env"
                    pkill -f ./target/release 2>/dev/null
                    nohup ./target/release/\(projectName) &>/tmp/\(projectName).log &
                    echo "[deploy] Started \(projectName) (PID $!)"
                    """

            case .go:
                remoteSetup = """
                    if ! command -v go &>/dev/null; then
                      echo "[deploy] Installing Go..."
                      GO_VERSION=1.22.0
                      wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz
                      sudo rm -rf /usr/local/go
                      sudo tar -C /usr/local -xzf /tmp/go.tar.gz
                      echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
                    fi
                    export PATH=$PATH:/usr/local/go/bin
                    """
                remoteBuild = """
                    export PATH=$PATH:/usr/local/go/bin
                    go mod tidy && go build -o \(projectName) .
                    """
                remoteStart = """
                    pkill -f ./\(projectName) 2>/dev/null
                    nohup ./\(projectName) &>/tmp/\(projectName).log &
                    echo "[deploy] Started \(projectName) (PID $!)"
                    """

            default:
                remoteSetup = "echo '[deploy] No specific runtime detected — running generic deploy'"
                remoteBuild = "echo '[deploy] No build step'"
                remoteStart = "echo '[deploy] No start command configured'"
            }
        }

        // ── Assemble the full local bash script ───────────────────────────
        let rsyncExcludes = "--exclude '.git' --exclude 'node_modules' --exclude '.next' --exclude 'dist' --exclude 'build' --exclude '__pycache__' --exclude '.env' --exclude '*.log'"

        return """
        #!/usr/bin/env bash
        set -euo pipefail

        # ── LingCode Magic Deploy ─────────────────────────────────────────
        # Target:  \(target.userAtHost)\(target.port == 22 ? "" : ":\(target.port)")
        # Project: \(projectName) (\(projectType.rawValue))
        # Generated: $(date)
        # ─────────────────────────────────────────────────────────────────

        \(target.password.isEmpty ? "" : """
        # Install sshpass locally if needed (required for password auth)
        if ! command -v sshpass &>/dev/null; then
          echo "[deploy] Installing sshpass locally..."
          if command -v brew &>/dev/null; then brew install hudochenkov/sshpass/sshpass 2>/dev/null || brew install sshpass; fi
          if command -v apt-get &>/dev/null; then sudo apt-get install -y sshpass; fi
        fi
        """)

        echo "[deploy] Step 1/5 — Verifying SSH connection..."
        \(sshPrefix) 'echo "[deploy] SSH connection OK"'

        echo "[deploy] Step 2/5 — Syncing project files..."
        \(sshPrefix) "mkdir -p \(deployDir)"
        \(rsyncPrefix)\(rsyncExcludes) "\(projectURL.path)/" "\(target.userAtHost):\(deployDir)/"

        echo "[deploy] Step 3/5 — Installing runtime dependencies on server..."
        \(sshPrefix) 'bash -l -s' << 'REMOTE_SETUP'
        set -euo pipefail
        cd \(deployDir)
        \(remoteSetup)
        REMOTE_SETUP

        echo "[deploy] Step 4/5 — Building project on server..."
        \(sshPrefix) 'bash -l -s' << 'REMOTE_BUILD'
        set -euo pipefail
        cd \(deployDir)
        \(remoteBuild)
        REMOTE_BUILD

        echo "[deploy] Step 5/5 — Starting application..."
        \(sshPrefix) 'bash -l -s' << 'REMOTE_START'
        set -euo pipefail
        cd \(deployDir)
        \(remoteStart)
        REMOTE_START

        echo ""
        echo "[deploy] ✓ Deployment complete!"
        echo "[deploy] App is running on: http://\(target.host)"
        """
    }

    private func detectProjectType(in projectURL: URL) -> ProjectType {
        let fm = FileManager.default
        let packageJsonURL = projectURL.appendingPathComponent("package.json")
        if fm.fileExists(atPath: packageJsonURL.path),
           let data = try? Data(contentsOf: packageJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let deps = ((json["dependencies"] as? [String: Any]) ?? [:])
                .merging((json["devDependencies"] as? [String: Any]) ?? [:]) { $1 }
            if deps["next"] != nil { return .nextjs }
            if deps["nuxt"] != nil { return .nuxt }
            if deps["@sveltejs/kit"] != nil || deps["svelte"] != nil { return .svelte }
            if deps["vue"] != nil { return .vue }
            if deps["react"] != nil { return .react }
            return .nodejs
        }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("requirements.txt").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("pyproject.toml").path) { return .python }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) { return .rust }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("go.mod").path) { return .go }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) { return .swift }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("index.html").path) { return .staticSite }
        return .unknown
    }

    // MARK: - String helpers

    private func hasFile(_ name: String, in url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
    }

    private func hasNextConfig(in url: URL) -> Bool {
        hasFile("next.config.js", in: url) || hasFile("next.config.ts", in: url) || hasFile("next.config.mjs", in: url)
    }

    private func matchesPattern(_ pattern: String, in string: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: []))
            .map { $0.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil }
            ?? false
    }

    private func isUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }

    private func isHex40(_ string: String) -> Bool {
        string.count == 40 && matchesPattern(#"^[a-fA-F0-9]+$"#, in: string)
    }

    private func isJWT(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty }
    }
}
