//
//  CursorStreamingFileCard.swift
//  LingCode
//
//  Cursor-style streaming file card component
//

import SwiftUI
import AppKit

enum DiffLineType {
    case added
    case removed
    case unchanged
}

struct CursorStreamingFileCard: View {
    let file: StreamingFileInfo
    let isExpanded: Bool
    let projectURL: URL?
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onApply: () -> Void
    let onReject: (() -> Void)? // Optional reject callback
    
    @State private var isHovered = false
    @State private var isApplied = false
    @State private var isRejected = false
    @State private var validationResult: ValidationResult?
    @State private var shouldAutoScroll = true // Track if we should auto-scroll
    @State private var scrollPosition: CGFloat = 0
    
    // PROBLEM 1 FIX: Sanitized content (reasoning/markdown removed)
    // PROBLEM 2 FIX: Frozen content buffer (immutable once streaming completes)
    @State private var sanitizedContent: String = ""
    @State private var frozenContent: String? = nil // Immutable buffer for finalized code
    
    init(
        file: StreamingFileInfo,
        isExpanded: Bool,
        projectURL: URL?,
        onToggle: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onReject: (() -> Void)? = nil
    ) {
        self.file = file
        self.isExpanded = isExpanded
        self.projectURL = projectURL
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.onApply = onApply
        self.onReject = onReject
    }
    
    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            // Only show validation warnings when NOT streaming (generation complete)
            // Don't show errors during code generation as they're expected
            if !file.isStreaming, let validation = validationResult, !validation.isValid {
                validationWarningView(validation)
            }
            expandedContent
        }
        .background(fileCardBackground)
        .overlay(fileCardOverlay)
        .cornerRadius(8)
        .shadow(
            color: isHovered ? Color.black.opacity(0.12) : Color.black.opacity(0.04),
            radius: isHovered ? 4 : 2,
            x: 0,
            y: isHovered ? 2 : 1
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: file.content)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .onAppear {
            // PROBLEM 1 FIX: Initialize sanitized content on appear
            sanitizeAndUpdateContent()
            
            // PROBLEM 2 FIX: If already not streaming, freeze content immediately
            if !file.isStreaming && frozenContent == nil {
                freezeContent()
            }
            
            // Only validate when not streaming (generation complete)
            if !file.isStreaming {
                validateFile()
            }
        }
        .onChange(of: file.content) { _, _ in
            // PROBLEM 1 FIX: Sanitize content whenever it changes
            sanitizeAndUpdateContent()
            
            // Only validate when not streaming (generation complete)
            if !file.isStreaming {
                validateFile()
            }
        }
        .onChange(of: file.isStreaming) { wasStreaming, isStreaming in
            // PROBLEM 2 FIX: Freeze content when streaming completes
            if wasStreaming && !isStreaming {
                // Streaming completed - freeze content for selection
                freezeContent()
                validateFile()
            }
        }
    }
    
    private func validateFile() {
        let change = CodeChange(
            id: UUID(),
            filePath: file.path,
            fileName: file.name,
            operationType: .update,
            originalContent: nil, // Would get from file system
            newContent: frozenContent ?? sanitizedContent, // PROBLEM 1 FIX: Use sanitized content
            lineRange: nil,
            language: file.language
        )
        
        validationResult = CodeValidationService.shared.validateChange(
            change,
            requestedScope: "AI generated code",
            projectConfig: nil
        )
    }
    
    private func validationWarningView(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ValidationBadgeView(validationResult: validation)
            
            if !validation.issues.isEmpty {
                ValidationIssuesView(issues: validation.issues)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            validation.severity == .critical 
                ? Color.red.opacity(0.1)
                : Color.orange.opacity(0.1)
        )
    }
    
    // MARK: - View Components
    
    private var fileHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                fileIconView
                fileNameView
                filePathView
                Spacer()
                statusBadgeView
                actionButtonsView
                expandButton
            }
            
            // Change summary
            if let summary = file.changeSummary, !summary.isEmpty {
                HStack(spacing: 6) {
                    if file.addedLines > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 8))
                            Text("+\(file.addedLines)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.green)
                    }
                    if file.removedLines > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 8))
                            Text("-\(file.removedLines)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.leading, 24) // Align with file name
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8) // More compact header
        .background(headerBackground)
        .overlay(headerOverlay)
        .onHover(perform: handleHover)
    }
    
    private var fileIconView: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: fileIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(fileIconColor)
            
            if file.isStreaming {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.6), radius: 2)
                    
                    Circle()
                        .stroke(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.4), lineWidth: 1)
                        .frame(width: 10, height: 10)
                        .scaleEffect(file.isStreaming ? 1.5 : 1.0)
                        .opacity(file.isStreaming ? 0.0 : 0.6)
                        .animation(
                            Animation.easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false),
                            value: file.isStreaming
                        )
                }
                .offset(x: 2, y: -2)
            }
        }
    }
    
    @State private var isFileNameHovered = false
    
    private var fileNameView: some View {
        Button(action: onOpen) {
            Text(file.name)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(isFileNameHovered ? Color(red: 0.2, green: 0.6, blue: 1.0) : .primary)
                .textSelection(.enabled) // PROBLEM 1 FIX: Make filename selectable
                .lineLimit(1)
                .underline(isFileNameHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Click to open file in editor")
        .scaleEffect(isFileNameHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFileNameHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isFileNameHovered = hovering
            }
            // Change cursor to pointer on hover
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    @State private var isFilePathHovered = false
    
    private var filePathView: some View {
        Button(action: onOpen) {
            Text(file.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isFilePathHovered ? Color(red: 0.2, green: 0.6, blue: 1.0) : .secondary.opacity(0.6))
                .textSelection(.enabled) // PROBLEM 1 FIX: Make file path selectable
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Click to open file in editor")
        .scaleEffect(isFilePathHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFilePathHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isFilePathHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private var statusBadgeView: some View {
        Group {
            if file.isStreaming {
                streamingBadge
            } else {
                readyBadge
            }
        }
    }
    
    private var streamingBadge: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .shadow(color: Color.white.opacity(0.8), radius: 1)
                
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .scaleEffect(file.isStreaming ? 1.5 : 1.0)
                    .opacity(file.isStreaming ? 0.0 : 0.8)
                    .animation(
                        Animation.easeOut(duration: 0.8)
                            .repeatForever(autoreverses: false),
                        value: file.isStreaming
                    )
            }
            Text("Generating")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3), radius: 2)
        )
    }
    
    private var readyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Text("Ready")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(red: 0.2, green: 0.8, blue: 0.4))
        )
    }
    
    @State private var isButtonPressed = false
    
    @ViewBuilder
    private var actionButtonsView: some View {
        if isHovered || isExpanded {
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isButtonPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isButtonPressed = false
                        }
                    }
                    onOpen()
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isButtonPressed ? 0.9 : 1.0)
                .help("Open file")
                
                if !isRejected {
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isApplied = true
                        }
                        onApply()
                    }) {
                        Image(systemName: isApplied ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isApplied ? Color(red: 0.2, green: 0.8, blue: 0.4) : Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isApplied ? 1.1 : 1.0)
                    .help(isApplied ? "Applied" : "Apply changes")
                    .disabled(isApplied)
                }
                
                if let reject = onReject, !isApplied {
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isRejected = true
                        }
                        reject()
                    }) {
                        Image(systemName: isRejected ? "xmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isRejected ? Color.red : Color.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isRejected ? 1.1 : 1.0)
                    .help(isRejected ? "Rejected" : "Reject changes")
                    .disabled(isRejected)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .scale(scale: 0.8))
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
    }
    
    @State private var isExpandButtonHovered = false
    
    private var expandButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onToggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isExpandButtonHovered ? Color(red: 0.2, green: 0.6, blue: 1.0) : .secondary)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isExpandButtonHovered ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isExpandButtonHovered)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isExpandButtonHovered = hovering
            }
        }
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor).opacity(0.4))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }
    
    private var headerOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                file.isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: file.isStreaming ? 1.5 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: file.isStreaming)
    }
    
    @ViewBuilder
    private var expandedContent: some View {
        if isExpanded {
            Divider()
                .padding(.horizontal, 12)
                .transition(.opacity)
            codePreview
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
        }
    }
    
    private var codePreview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                codeLinesView
                    .padding(.vertical, 8)
                    .id("bottom")
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                        }
                    )
            }
            .coordinateSpace(name: "scroll")
            .frame(maxHeight: 200) // Compact height like Cursor, scrollable
            .background(
                Color(NSColor.textBackgroundColor)
                    .opacity(0.5)
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                // Track scroll position
                scrollPosition = offset
                // If user scrolls up significantly, disable auto-scroll
                if offset < -50 {
                    shouldAutoScroll = false
                } else if offset > -10 {
                    // Near bottom, re-enable auto-scroll
                    shouldAutoScroll = true
                }
            }
            .onChange(of: sanitizedContent) { _, _ in
                // PROBLEM 2 FIX: Only auto-scroll if content is not frozen (still streaming)
                // Once frozen, don't auto-scroll to preserve user selection
                if shouldAutoScroll && frozenContent == nil {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Scroll to bottom on appear
                shouldAutoScroll = true
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
    
    private var codeLinesView: some View {
        // PROBLEM 2 FIX: Use frozen content if available, otherwise use sanitized content
        // Frozen content is immutable and selection-safe
        let displayContent = frozenContent ?? sanitizedContent
        
        let unifiedDiff = calculateUnifiedDiff(from: displayContent)
        
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(unifiedDiff.enumerated()), id: \.offset) { index, diffLine in
                codeLineView(
                    index: index,
                    line: diffLine.content,
                    type: diffLine.type,
                    originalLineNumber: diffLine.originalLineNumber,
                    newLineNumber: diffLine.newLineNumber,
                    isSelectable: frozenContent != nil // PROBLEM 2 FIX: Only selectable when frozen
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                    removal: .opacity
                ))
            }
            if file.isStreaming {
                let lines = displayContent.components(separatedBy: .newlines)
                streamingCursorView(lineCount: lines.count)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: displayContent)
    }
    
    struct UnifiedDiffLine {
        let content: String
        let type: DiffLineType
        let originalLineNumber: Int?
        let newLineNumber: Int?
    }
    
    // PROBLEM 1 FIX: Sanitize content to remove reasoning/markdown
    private func sanitizeAndUpdateContent() {
        let sanitized = ContentSanitizer.shared.sanitizeContent(file.content)
        sanitizedContent = sanitized
    }
    
    // PROBLEM 2 FIX: Freeze content when streaming completes
    // Creates immutable buffer for selection-safe rendering
    private func freezeContent() {
        // Freeze the current sanitized content
        frozenContent = sanitizedContent
    }
    
    /// Calculate unified diff showing both removed and added lines
    /// PROBLEM 2 FIX: Accepts content parameter to use frozen/sanitized content
    private func calculateUnifiedDiff(from content: String? = nil) -> [UnifiedDiffLine] {
        // Use provided content or fall back to sanitized content
        let sourceContent = content ?? sanitizedContent
        
        guard let projectURL = projectURL else {
            // New file - all lines are additions
            return sourceContent.components(separatedBy: .newlines).enumerated().map { index, line in
                UnifiedDiffLine(content: line, type: .added, originalLineNumber: nil, newLineNumber: index + 1)
            }
        }
        
        let fileURL = projectURL.appendingPathComponent(file.path)
        
        // If file doesn't exist, all lines are new (green)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return sourceContent.components(separatedBy: .newlines).enumerated().map { index, line in
                UnifiedDiffLine(content: line, type: .added, originalLineNumber: nil, newLineNumber: index + 1)
            }
        }
        
        // Compare existing vs new content using a simple diff algorithm
        let existingLines = existingContent.components(separatedBy: .newlines)
        let newLines = sourceContent.components(separatedBy: .newlines)
        
        var unifiedDiff: [UnifiedDiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        
        // Simple longest common subsequence (LCS) based diff
        while oldIndex < existingLines.count || newIndex < newLines.count {
            let oldLine = oldIndex < existingLines.count ? existingLines[oldIndex] : nil
            let newLine = newIndex < newLines.count ? newLines[newIndex] : nil
            
            if let old = oldLine, let new = newLine {
                if old == new {
                    // Lines match - unchanged
                    unifiedDiff.append(UnifiedDiffLine(
                        content: new,
                        type: .unchanged,
                        originalLineNumber: oldIndex + 1,
                        newLineNumber: newIndex + 1
                    ))
                    oldIndex += 1
                    newIndex += 1
                } else {
                    // Lines differ - check if it's a modification or insertion/deletion
                    // Look ahead to see if next old line matches current new line
                    if oldIndex + 1 < existingLines.count && existingLines[oldIndex + 1] == new {
                        // Old line was removed
                        unifiedDiff.append(UnifiedDiffLine(
                            content: old,
                            type: .removed,
                            originalLineNumber: oldIndex + 1,
                            newLineNumber: nil
                        ))
                        oldIndex += 1
                    } else if newIndex + 1 < newLines.count && old == newLines[newIndex + 1] {
                        // New line was added
                        unifiedDiff.append(UnifiedDiffLine(
                            content: new,
                            type: .added,
                            originalLineNumber: nil,
                            newLineNumber: newIndex + 1
                        ))
                        newIndex += 1
                    } else {
                        // Both changed - show removed then added
                        unifiedDiff.append(UnifiedDiffLine(
                            content: old,
                            type: .removed,
                            originalLineNumber: oldIndex + 1,
                            newLineNumber: nil
                        ))
                        unifiedDiff.append(UnifiedDiffLine(
                            content: new,
                            type: .added,
                            originalLineNumber: nil,
                            newLineNumber: newIndex + 1
                        ))
                        oldIndex += 1
                        newIndex += 1
                    }
                }
            } else if let old = oldLine {
                // Line removed
                unifiedDiff.append(UnifiedDiffLine(
                    content: old,
                    type: .removed,
                    originalLineNumber: oldIndex + 1,
                    newLineNumber: nil
                ))
                oldIndex += 1
            } else if let new = newLine {
                // Line added
                unifiedDiff.append(UnifiedDiffLine(
                    content: new,
                    type: .added,
                    originalLineNumber: nil,
                    newLineNumber: newIndex + 1
                ))
                newIndex += 1
            }
        }
        
        return unifiedDiff
    }
    
    private func calculateLineTypes() -> [DiffLineType] {
        // Legacy method - kept for compatibility
        // PROBLEM 2 FIX: Use sanitized/frozen content
        let displayContent = frozenContent ?? sanitizedContent
        return calculateUnifiedDiff(from: displayContent).map { $0.type }
    }
    
    private func getLineNumberText(type: DiffLineType, index: Int, originalLineNumber: Int?, newLineNumber: Int?) -> String {
        if type == .removed, let orig = originalLineNumber {
            return "\(orig)"
        } else if type == .added, let new = newLineNumber {
            return "\(new)"
        } else if type == .unchanged, let orig = originalLineNumber {
            return "\(orig)"
        } else {
            return "\(index + 1)"
        }
    }
    
    private func codeLineView(index: Int, line: String, type: DiffLineType, originalLineNumber: Int? = nil, newLineNumber: Int? = nil, isSelectable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number - show original for removed, new for added, both for unchanged
            let lineNumberText = getLineNumberText(
                type: type,
                index: index,
                originalLineNumber: originalLineNumber,
                newLineNumber: newLineNumber
            )
            
            Text(lineNumberText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            // Change indicator
            Text(changeIndicator(for: type))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(indicatorColor(for: type))
                .frame(width: 14)
            
            // Code content
            // PROBLEM 2 FIX: Only enable selection when content is frozen (streaming completed)
            // During streaming, render as non-selectable preview to prevent selection breakage
            Group {
                if isSelectable {
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(textColor(for: type))
                        .textSelection(.enabled) // PROBLEM 2 FIX: Selectable when frozen
                } else {
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(textColor(for: type))
                        .textSelection(.disabled) // PROBLEM 2 FIX: Non-selectable during streaming
                }
            }
        }
        .padding(.vertical, 1.5) // More compact vertical padding
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor(for: type))
    }
    
    private func changeIndicator(for type: DiffLineType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }
    
    private func indicatorColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .clear
        }
    }
    
    private func textColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return Color(red: 0.2, green: 0.6, blue: 0.2) // Dark green
        case .removed: return Color(red: 0.7, green: 0.2, blue: 0.2) // Dark red
        case .unchanged: return .primary
        }
    }
    
    private func backgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return Color.green.opacity(0.1)
        case .removed: return Color.red.opacity(0.1)
        case .unchanged: return Color.clear
        }
    }
    
    private func streamingCursorView(lineCount: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineCount + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 12)
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3))
                    .frame(width: 2, height: 14)
                
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 1.0))
                    .frame(width: 2, height: 14)
                    .opacity(0.9)
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.8), radius: 2)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: file.isStreaming
                    )
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
    }
    
    private var fileCardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
    
    private var fileCardOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                file.isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3) : Color.clear,
                lineWidth: file.isStreaming ? 1.5 : 0
            )
            .shadow(
                color: file.isStreaming ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2) : Color.clear,
                radius: file.isStreaming ? 4 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: file.isStreaming)
    }
    
    // MARK: - Helpers
    
    private func handleHover(_ hovering: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
    
    private var fileIcon: String {
        let ext = URL(fileURLWithPath: file.name).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "terminal"
        case "json": return "doc.text"
        case "html": return "globe"
        case "css": return "paintbrush"
        case "md": return "doc.text"
        default: return "doc"
        }
    }
    
    private var fileIconColor: Color {
        let ext = URL(fileURLWithPath: file.name).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 1.0, green: 0.4, blue: 0.2)
        case "js", "jsx": return Color(red: 1.0, green: 0.8, blue: 0.0)
        case "ts", "tsx": return Color(red: 0.0, green: 0.5, blue: 0.8)
        case "py": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "json": return Color(red: 0.9, green: 0.9, blue: 0.9)
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

// MARK: - Scroll Position Tracking

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
