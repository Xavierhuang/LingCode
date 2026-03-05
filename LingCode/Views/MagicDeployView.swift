//
//  MagicDeployView.swift
//  LingCode
//
//  Compact, Apple-native macOS popover for one-tap deployment.
//
//  UX states (animated with SwiftUI transitions):
//    .input    — paste field + hint chips + platform cards + "Magic Deploy" button
//    .progress — pipeline step checklist (Detect → Config → Test → Build → Deploy)
//    .success  — green checkmark, live URL, auto-dismisses after 5 s
//    .failure  — error banner + "Try Again" link back to .input
//
//  Fixed frame: 380 × 320 pt. Never resizes during state transitions.
//

import SwiftUI

// MARK: - Popover state

private enum DeployPopoverState: Equatable {
    case input
    case progress
    case success(url: String?)
    case failure(message: String)
}

// MARK: - Platform signup cards model

private struct DeployPlatformCard: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let icon: String
    let accentColor: Color
    let signupURL: String
    let pricingNote: String
}

private let platformCards: [DeployPlatformCard] = [
    DeployPlatformCard(
        id: "vercel",
        name: "Vercel",
        tagline: "Best for Next.js, React, and static sites.",
        icon: "v.circle.fill",
        accentColor: Color(white: 0.9),
        signupURL: "https://vercel.com/signup",
        pricingNote: "Free tier available"
    ),
    DeployPlatformCard(
        id: "netlify",
        name: "Netlify",
        tagline: "Frontend hosting with CI/CD, forms, and functions.",
        icon: "n.circle.fill",
        accentColor: Color(red: 0.23, green: 0.8, blue: 0.7),
        signupURL: "https://app.netlify.com/signup",
        pricingNote: "Free tier available"
    ),
    DeployPlatformCard(
        id: "aws",
        name: "AWS",
        tagline: "Full cloud — EC2, S3, Lambda, RDS, and 200+ services.",
        icon: "cloud.fill",
        accentColor: Color(red: 1.0, green: 0.6, blue: 0.1),
        signupURL: "https://aws.amazon.com/free",
        pricingNote: "12-month free tier"
    ),
    DeployPlatformCard(
        id: "digitalocean",
        name: "DigitalOcean",
        tagline: "Simple cloud VMs, managed DBs, and App Platform.",
        icon: "drop.fill",
        accentColor: Color(red: 0.0, green: 0.45, blue: 1.0),
        signupURL: "https://cloud.digitalocean.com/registrations/new",
        pricingNote: "$200 free credit"
    ),
    DeployPlatformCard(
        id: "railway",
        name: "Railway",
        tagline: "Deploy backends, databases, and full-stack apps.",
        icon: "tram.fill",
        accentColor: Color(red: 0.55, green: 0.35, blue: 0.95),
        signupURL: "https://railway.app",
        pricingNote: "Starts free"
    ),
    DeployPlatformCard(
        id: "fly",
        name: "Fly.io",
        tagline: "Run Docker containers close to your users globally.",
        icon: "airplane",
        accentColor: Color(red: 0.55, green: 0.75, blue: 0.95),
        signupURL: "https://fly.io/app/sign-up",
        pricingNote: "Generous free allowance"
    ),
    DeployPlatformCard(
        id: "heroku",
        name: "Heroku",
        tagline: "Platform-as-a-service for any language or framework.",
        icon: "h.circle.fill",
        accentColor: Color(red: 0.43, green: 0.26, blue: 0.72),
        signupURL: "https://signup.heroku.com",
        pricingNote: "Paid plans from $5/mo"
    ),
    DeployPlatformCard(
        id: "namecheap",
        name: "Namecheap",
        tagline: "Buy a custom domain for your deployed app.",
        icon: "globe",
        accentColor: Color(red: 0.95, green: 0.55, blue: 0.1),
        signupURL: "https://www.namecheap.com",
        pricingNote: "Domains from $1/yr"
    ),
]

// MARK: - Domain registrar cards model

private struct DomainRegistrar: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let icon: String
    let color: Color
    let url: String
    let priceNote: String
}

private let domainRegistrars: [DomainRegistrar] = [
    DomainRegistrar(id: "namecheap",   name: "Namecheap",   tagline: "Affordable domains, free WhoisGuard privacy.",          icon: "tag.fill",        color: Color(red: 0.95, green: 0.55, blue: 0.1),  url: "https://www.namecheap.com",                     priceNote: "from $1/yr"),
    DomainRegistrar(id: "godaddy",     name: "GoDaddy",      tagline: "World's largest domain registrar.",                    icon: "globe.badge.chevron.backward", color: Color(red: 0.0, green: 0.55, blue: 0.27), url: "https://www.godaddy.com/domains",               priceNote: "from $1/yr"),
    DomainRegistrar(id: "cloudflare",  name: "Cloudflare",   tagline: "Register at cost price, free CDN + DDoS protection.",  icon: "bolt.shield.fill", color: Color(red: 0.92, green: 0.50, blue: 0.15), url: "https://www.cloudflare.com/products/registrar/", priceNote: "at cost"),
    DomainRegistrar(id: "google",      name: "Google Domains", tagline: "Simple DNS, Google reliability.",                    icon: "g.circle.fill",    color: Color(red: 0.26, green: 0.52, blue: 0.96), url: "https://domains.google",                        priceNote: "from $12/yr"),
    DomainRegistrar(id: "porkbun",     name: "Porkbun",      tagline: "Low prices, free SSL, fun UI.",                        icon: "star.fill",        color: Color(red: 0.9,  green: 0.3,  blue: 0.5),  url: "https://porkbun.com",                           priceNote: "from $2/yr"),
]

// MARK: - Main view

struct MagicDeployView: View {
    @ObservedObject private var deployService = DeploymentService.shared
    private let autoConfig = DeploymentAutoConfigService.shared

    let projectURL: URL
    var onDismiss: (() -> Void)?

    @State private var inputText: String = ""
    @State private var sshPassword: String = ""
    @State private var pemFilePath: String = ""
    @State private var stepMessage: String = ""
    @State private var popoverState: DeployPopoverState = .input
    @State private var showPlatformCards: Bool = false
    @FocusState private var inputFocused: Bool

    private var looksLikeSSH: Bool {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // user@host, user@ip, user:pass@host — but not AWS EC2 (handled separately)
        return t.contains("@") && !t.hasPrefix("http") && !t.contains(".vercel")
            && !t.contains(".netlify") && !t.lowercased().contains("token")
            && !t.lowercased().contains("railway") && !t.lowercased().contains("heroku")
            && !looksLikeAWS
    }

    private var looksLikeAWS: Bool {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.contains("amazonaws.com")
            || t.hasPrefix("ec2-user@")
            || t.hasPrefix("ubuntu@ec2")
            || t.contains(".compute.amazonaws.com")
            || (t.contains("@") && t.contains("ec2-"))
    }

    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(width: 380, height: 420)

            VStack(spacing: 0) {
                header
                Divider()
                ZStack {
                    if popoverState == .input {
                        inputPane
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .leading)),
                                removal:   .opacity.combined(with: .move(edge: .leading))
                            ))
                    }
                    if case .progress = popoverState {
                        progressPane
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal:   .opacity.combined(with: .move(edge: .trailing))
                            ))
                    }
                    if case .success(let url) = popoverState {
                        successPane(url: url)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                removal:   .opacity
                            ))
                    }
                    if case .failure(let msg) = popoverState {
                        failurePane(message: msg)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal:   .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(width: 380, height: 420)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            inputFocused = true
            // Sync popover state to the service's live state when reopened mid-deploy
            syncStateFromService()
        }
        .onChange(of: deployService.status) { newStatus in
            handleStatusChange(newStatus)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(headerIconColor)
                .animation(.easeInOut(duration: 0.2), value: popoverState)

            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .animation(.none, value: popoverState)

            Spacer()

            if popoverState == .progress {
                Button {
                    cancelAndReset()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if case .failure = popoverState {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        popoverState = .input
                        stepMessage = ""
                    }
                } label: {
                    Text("Try again")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Input pane

    private var inputPane: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste your deployment credential")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                // Text field
                HStack(spacing: 8) {
                    Image(systemName: credentialIcon)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                        .animation(.easeInOut(duration: 0.15), value: inputText)

                    TextField("Vercel token, Netlify Site ID, or user@host...", text: $inputText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12, design: .monospaced))
                        .focused($inputFocused)
                        .onSubmit { startDeploy() }

                    if !inputText.isEmpty {
                        Button {
                            inputText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(fieldBorderColor, lineWidth: 1)
                )

                // Hint chips — only when field is empty
                if inputText.isEmpty {
                    hintChips
                }

                // SSH password field — shown when input looks like user@host
                if looksLikeSSH {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        SecureField("Server password (leave empty to use SSH key)", text: $sshPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12))
                        if !sshPassword.isEmpty {
                            Button {
                                sshPassword = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                        Text("Or use SSH key auth — no password needed if your key is in ~/.ssh/")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }

                // AWS .pem key picker — shown when input looks like an EC2 host
                if looksLikeAWS {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AWS EC2 detected — select your .pem key file")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.1))
                                .frame(width: 16)

                            if pemFilePath.isEmpty {
                                Text("No .pem file selected")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            } else {
                                Text(URL(fileURLWithPath: pemFilePath).lastPathComponent)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button {
                                let panel = NSOpenPanel()
                                panel.title = "Select .pem Key File"
                                panel.allowedContentTypes = []
                                panel.allowsOtherFileTypes = true
                                panel.message = "Choose the .pem private key file AWS gave you when creating your EC2 instance."
                                panel.prompt = "Select"
                                if panel.runModal() == .OK, let url = panel.url {
                                    pemFilePath = url.path
                                }
                            } label: {
                                Text(pemFilePath.isEmpty ? "Browse..." : "Change")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if !pemFilePath.isEmpty {
                                Button {
                                    pemFilePath = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(pemFilePath.isEmpty
                                    ? Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.6)
                                    : Color.green.opacity(0.5),
                                    lineWidth: 1)
                        )

                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                            Text("The .pem file is the private key downloaded from AWS EC2 → Key Pairs. chmod 400 your-key.pem before use.")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                }

                // ── Platform cards section ────────────────────────────────
                if inputText.isEmpty {
                    platformCardsSection
                }

                // Primary action
                Button(action: startDeploy) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Magic Deploy")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(deployBtnBg)
                    .foregroundColor(deployBtnFg)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Platform cards section

    private var platformCardsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Disclosure header
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showPlatformCards.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showPlatformCards ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Don't have a platform yet?")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            if showPlatformCards {
                VStack(spacing: 5) {
                    ForEach(platformCards) { card in
                        platformCardRow(card)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func platformCardRow(_ card: DeployPlatformCard) -> some View {
        HStack(spacing: 10) {
            // Platform icon
            Image(systemName: card.icon)
                .font(.system(size: 14))
                .foregroundColor(card.accentColor)
                .frame(width: 22)

            // Name + tagline
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(card.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(card.pricingNote)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)
                }
                Text(card.tagline)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Open in browser
            Button {
                if let url = URL(string: card.signupURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 3) {
                    Text("Open")
                        .font(.system(size: 11))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Hint chips

    private var hintChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InputHint.allCases) { hint in
                    Button {
                        inputText = hint.example
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hint.icon)
                                .font(.system(size: 10))
                            Text(hint.label)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Progress pane

    private var progressPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pipeline stepper
            pipelineStepper
                .padding(.horizontal, 14)
                .padding(.top, 16)

            Divider()
                .padding(.top, 12)

            // Current step label
            HStack(spacing: 7) {
                if deployService.status.isInProgress {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
                Text(stepMessage.isEmpty ? deployService.status.displayText : stepMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.15), value: stepMessage)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Live deployment log output — terminal-style box
            DeployTerminalView(logs: deployService.deploymentLogs)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pipeline stepper

    private var pipelineStepper: some View {
        HStack(spacing: 0) {
            ForEach(PipelineStep.allCases) { step in
                HStack(spacing: 0) {
                    PipelineStepDot(step: step, currentStatus: deployService.status)
                    if step != PipelineStep.allCases.last {
                        Rectangle()
                            .frame(maxWidth: .infinity, maxHeight: 1)
                            .foregroundColor(
                                step.isCompleted(for: deployService.status)
                                    ? Color.accentColor.opacity(0.5)
                                    : Color(NSColor.separatorColor)
                            )
                            .animation(.easeInOut(duration: 0.25), value: deployService.status)
                    }
                }
            }
        }
    }

    // MARK: - Success pane

    private func successPane(url: String?) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {

                // ── Success header ────────────────────────────────────────
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.green)
                    }

                    Text("Deployed successfully")
                        .font(.system(size: 13, weight: .semibold))

                    if let urlString = url, let link = URL(string: urlString) {
                        Link(urlString, destination: link)
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.top, 10)

                Divider()

                // ── Connect your own domain ───────────────────────────────
                customDomainSection(deployedURL: url)

                Divider()

                // ── Get a domain ──────────────────────────────────────────
                domainRegistrarSection

                // ── Done ─────────────────────────────────────────────────
                Button("Done") {
                    dismissTask?.cancel()
                    onDismiss?()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Custom domain section

    @State private var customDomainInput: String = ""
    @State private var domainCopied: Bool = false

    private func customDomainSection(deployedURL: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Connect a custom domain")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("Point your domain's DNS to your deployed app. Add these records at your registrar:")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // DNS instructions
            VStack(spacing: 4) {
                dnsRow(type: "CNAME", name: "www", value: deployedURL.map { URL(string: $0)?.host ?? $0 } ?? "your-app.vercel.app")
                dnsRow(type: "A", name: "@", value: "76.76.21.21")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            // Domain input + copy CNAME button
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("yourdomain.com", text: $customDomainInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11, design: .monospaced))

                if !customDomainInput.isEmpty {
                    Button {
                        let host = URL(string: deployedURL ?? "")?.host ?? (deployedURL ?? "")
                        let instructions = "CNAME  www  \(host)\nA  @  76.76.21.21"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instructions, forType: .string)
                        domainCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { domainCopied = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: domainCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(domainCopied ? "Copied" : "Copy DNS")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(domainCopied ? .green : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))

            Text("After adding DNS records, it can take up to 48 hours to propagate.")
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
    }

    private func dnsRow(type: String, name: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(type)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 50, alignment: .leading)
            Text(name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(NSColor.labelColor))
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
    }

    // MARK: - Domain registrar section

    private var domainRegistrarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Don't have a domain yet?")
                    .font(.system(size: 12, weight: .semibold))
            }

            ForEach(domainRegistrars) { registrar in
                registrarRow(registrar)
            }
        }
    }

    private func registrarRow(_ r: DomainRegistrar) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.icon)
                .font(.system(size: 13))
                .foregroundColor(r.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(r.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(r.priceNote)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)
                }
                Text(r.tagline)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(URL(string: r.url)!)
            } label: {
                HStack(spacing: 3) {
                    Text("Open")
                        .font(.system(size: 11))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    // MARK: - Failure pane

    private func failurePane(message: String) -> some View {
        // Just show the terminal log — the output tells the full story.
        // A thin red indicator at the top signals the failure without hiding the details.
        VStack(alignment: .leading, spacing: 0) {
            // Thin failure indicator bar
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                Text("Deploy failed — see output below")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Full terminal output
            DeployTerminalView(logs: deployService.deploymentLogs.isEmpty ? message : deployService.deploymentLogs)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startDeploy() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // AWS EC2 requires a .pem key file
        if looksLikeAWS && pemFilePath.isEmpty {
            withAnimation(.easeInOut(duration: 0.22)) {
                popoverState = .failure(message: "AWS EC2 requires a .pem key file. Click \"Browse...\" to select yours.")
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            popoverState = .progress
            stepMessage = "Starting..."
        }

        let password = sshPassword
        let pemPath = pemFilePath

        Task {
            do {
                _ = try await autoConfig.analyzeAndConfigure(
                    input: trimmed,
                    projectURL: projectURL,
                    sshPassword: password,
                    pemFilePath: pemPath
                ) { step in
                    Task { @MainActor in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            self.stepMessage = step
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        popoverState = .failure(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func cancelAndReset() {
        DeploymentService.shared.cancelDeployment()
        withAnimation(.easeInOut(duration: 0.22)) {
            popoverState = .input
            stepMessage = ""
        }
    }

    /// Called on onAppear — restores the correct pane if the deploy is
    /// already running or finished when the popover is (re)opened.
    private func syncStateFromService() {
        switch deployService.status {
        case .validating, .runningTests, .building, .deploying:
            if popoverState != .progress {
                popoverState = .progress
                stepMessage = deployService.status.displayText
            }
        case .success(let url):
            if case .progress = popoverState { break }
            popoverState = .success(url: url)
        case .failed(let error):
            if case .progress = popoverState { break }
            popoverState = .failure(message: error)
        case .idle, .cancelled:
            // Already at idle — stay on input unless we are mid-way
            if case .progress = popoverState {
                popoverState = .input
                stepMessage = ""
            }
        }
    }

    private func handleStatusChange(_ status: DeploymentStatus) {
        switch status {
        case .success(let url):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                popoverState = .success(url: url)
            }
        case .failed(let error):
            // Only switch to failure if we're in progress (not idle on first load)
            if case .progress = popoverState {
                withAnimation(.easeInOut(duration: 0.22)) {
                    popoverState = .failure(message: error)
                }
            }
        default:
            break
        }
    }

    // MARK: - Computed helpers

    private var headerIcon: String {
        switch popoverState {
        case .input:    return "bolt.fill"
        case .progress: return "arrow.up.circle"
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "exclamationmark.triangle.fill"
        }
    }

    private var headerIconColor: Color {
        switch popoverState {
        case .input:    return .accentColor
        case .progress: return .accentColor
        case .success:  return .green
        case .failure:  return .red
        }
    }

    private var headerTitle: String {
        switch popoverState {
        case .input:    return "Magic Deploy"
        case .progress: return "Deploying..."
        case .success:  return "Live"
        case .failure:  return "Deploy Failed"
        }
    }

    private var credentialIcon: String {
        let t = inputText.lowercased()
        if t.contains("vercel")  { return "v.circle" }
        if t.contains("netlify") { return "n.circle" }
        if t.contains("railway") { return "tram" }
        if t.contains("fly") || t.hasPrefix("fo") { return "airplane" }
        if t.contains("@")       { return "server.rack" }
        if t.hasPrefix("https")  { return "link" }
        return "key"
    }

    private var fieldBorderColor: Color {
        if inputFocused { return Color.accentColor.opacity(0.5) }
        return Color(NSColor.separatorColor)
    }

    private var deployBtnBg: Color {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Color(NSColor.controlColor)
            : Color.accentColor
    }

    private var deployBtnFg: Color {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .white
    }
}

// MARK: - Countdown label (auto-dismiss)

/// Shows "Closes in Xs" and fires `onComplete` when it reaches zero.
private struct CountdownLabel: View {
    let seconds: Int
    let onComplete: () -> Void

    @State private var remaining: Int

    init(seconds: Int, onComplete: @escaping () -> Void) {
        self.seconds = seconds
        self.onComplete = onComplete
        self._remaining = State(initialValue: seconds)
    }

    var body: some View {
        Text("Closes in \(remaining)s")
            .font(.system(size: 10))
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
            .onAppear {
                startCountdown()
            }
    }

    private func startCountdown() {
        guard remaining > 0 else { onComplete(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if remaining > 1 {
                remaining -= 1
                startCountdown()
            } else {
                remaining = 0
                onComplete()
            }
        }
    }
}

// MARK: - Pipeline step dot

private struct PipelineStepDot: View {
    let step: PipelineStep
    let currentStatus: DeploymentStatus

    private enum DotState { case pending, active, done }

    private var dotState: DotState {
        if step.isCompleted(for: currentStatus) { return .done }
        if step.isActive(for: currentStatus)    { return .active }
        return .pending
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .strokeBorder(ringColor, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(fillColor))
                    .animation(.easeInOut(duration: 0.2), value: dotState)

                switch dotState {
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                case .active:
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 11, height: 11)
                        .transition(.opacity)
                case .pending:
                    EmptyView()
                }
            }
            Text(step.label)
                .font(.system(size: 9))
                .foregroundColor(dotState == .pending ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.labelColor))
                .lineLimit(1)
        }
        .frame(minWidth: 44)
    }

    private var fillColor: Color {
        switch dotState {
        case .done:    return Color.accentColor
        case .active:  return Color.accentColor.opacity(0.12)
        case .pending: return Color.clear
        }
    }

    private var ringColor: Color {
        switch dotState {
        case .done, .active: return Color.accentColor
        case .pending:       return Color(NSColor.separatorColor)
        }
    }
}

// MARK: - Pipeline steps model

private enum PipelineStep: String, CaseIterable, Identifiable {
    case detect  = "Detect"
    case config  = "Config"
    case test    = "Test"
    case build   = "Build"
    case deploy  = "Deploy"

    var id: String { rawValue }
    var label: String { rawValue }

    func isActive(for status: DeploymentStatus) -> Bool {
        switch (self, status) {
        case (.config, .validating):   return true
        case (.test,   .runningTests): return true
        case (.build,  .building):     return true
        case (.deploy, .deploying):    return true
        default: return false
        }
    }

    func isCompleted(for status: DeploymentStatus) -> Bool {
        switch status {
        case .idle:        return false
        case .validating:  return self == .detect
        case .runningTests: return [.detect, .config].contains(self)
        case .building:    return [.detect, .config, .test].contains(self)
        case .deploying:   return [.detect, .config, .test, .build].contains(self)
        case .success, .failed, .cancelled: return true
        }
    }
}

// MARK: - Input hint chips model

private enum InputHint: String, CaseIterable, Identifiable {
    case vercel   = "Vercel"
    case netlify  = "Netlify"
    case fly      = "Fly.io"
    case ssh      = "SSH"
    case railway  = "Railway"
    case aws      = "AWS EC2"

    var id: String { rawValue }
    var label: String { rawValue }

    var icon: String {
        switch self {
        case .vercel:   return "v.circle"
        case .netlify:  return "n.circle"
        case .fly:      return "airplane"
        case .ssh:      return "server.rack"
        case .railway:  return "tram"
        case .aws:      return "cloud.fill"
        }
    }

    var example: String {
        switch self {
        case .vercel:   return "vercel_pat_"
        case .netlify:  return "netlify_"
        case .fly:      return "fo1_"
        case .ssh:      return "root@0.0.0.0"
        case .railway:  return "railway_"
        case .aws:      return "ec2-user@ec2-xx-xx-xx-xx.compute.amazonaws.com"
        }
    }
}

// MARK: - Terminal-style deploy log view

/// Renders deployment log output as a proper terminal:
/// - Dark background, monospaced font
/// - Colour-coded lines: [deploy] steps in green, [ERROR] in red, warnings in orange
/// - Auto-scrolls to the bottom as new lines arrive
/// - Toolbar with copy-log and clear buttons
private struct DeployTerminalView: View {
    let logs: String

    @State private var copied = false

    private struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        var color: Color {
            let lower = text.lowercased()
            if lower.contains("[error]") || lower.contains("error:") || lower.contains("fatal") {
                return Color(red: 1.0, green: 0.4, blue: 0.4)
            }
            if lower.contains("[deploy] step") || lower.contains("✓") || lower.contains("complete") || lower.contains("success") {
                return Color(red: 0.4, green: 0.9, blue: 0.5)
            }
            if lower.contains("warn") || lower.contains("warning") {
                return Color(red: 1.0, green: 0.8, blue: 0.3)
            }
            if lower.contains("[deploy]") {
                return Color(red: 0.4, green: 0.75, blue: 1.0)
            }
            return Color(red: 0.78, green: 0.78, blue: 0.78)
        }
    }

    private var lines: [LogLine] {
        logs.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { LogLine(text: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal toolbar
            HStack(spacing: 8) {
                // Traffic-light dots (decorative — macOS terminal look)
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1.0, green: 0.73, blue: 0.22)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.25, green: 0.78, blue: 0.36)).frame(width: 8, height: 8)

                Text("deploy log")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.5))

                Spacer()

                // Line count
                Text("\(lines.count) lines")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.4))

                // Copy button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(copied ? Color.green : Color(white: 0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(red: 0.18, green: 0.18, blue: 0.18))

            Divider()
                .background(Color(white: 0.25))

            // Log lines
            if logs.isEmpty {
                HStack {
                    Text("Waiting for output...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.12, blue: 0.12))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(line.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            // Invisible anchor at the bottom for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("terminalBottom")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .onChange(of: logs) { _ in
                        proxy.scrollTo("terminalBottom", anchor: .bottom)
                    }
                    .onAppear {
                        proxy.scrollTo("terminalBottom", anchor: .bottom)
                    }
                }
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.25), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 130)
    }
}

// MARK: - Reusable trigger button

/// Drop-in button that presents `MagicDeployView` as a `.popover`.
/// Works in any toolbar, status bar, or panel header.
struct MagicDeployButton: View {
    let projectURL: URL
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Deploy")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            MagicDeployView(projectURL: projectURL) {
                isPresented = false
            }
        }
        .help("Magic Deploy — paste a token or SSH string to deploy instantly")
    }
}
