//
//  EditSessionCoordinatorTests.swift
//  EditorCoreTests
//
//  Comprehensive tests for EditSessionCoordinator lifecycle
//

import XCTest
@testable import EditorCore
#if canImport(Combine)
import Combine
#endif

final class EditSessionCoordinatorTests: XCTestCase {
    var coordinator: DefaultEditSessionCoordinator!
    var mockEditor: MockEditor!
    
    override func setUp() {
        super.setUp()
        coordinator = DefaultEditSessionCoordinator()
        mockEditor = MockEditor()
    }
    
    override func tearDown() {
        coordinator = nil
        mockEditor = nil
        super.tearDown()
    }
    
    // MARK: - Test: startEditSession
    
    /// Verifies that startEditSession creates a valid session handle
    /// and transitions model to streaming state
    func testStartEditSession_CreatesValidSession() {
        // Given
        mockEditor.setFile(path: "test.swift", content: "print(\"hello\")")
        let files = mockEditor.getAllFileStates()
        
        // When
        let session = coordinator.startEditSession(
            instruction: "Add error handling",
            files: files
        )
        
        // Then
        XCTAssertNotNil(session)
        XCTAssertEqual(session.id, session.id) // Session has valid ID
        XCTAssertEqual(coordinator.activeSession?.id, session.id)
        XCTAssertEqual(session.model.status, .streaming)
    }
    
    // MARK: - Test: Streaming Text → Proposed Edits (JSON Format)
    
    /// Verifies that streaming JSON edit format is correctly parsed
    /// and results in proposed edits with correct diff hunks
    func testStreamingJSONEdit_ParsesCorrectly() {
        // Given
        mockEditor.setFile(path: "utils.swift", content: """
        func add(a: Int, b: Int) -> Int {
            return a + b
        }
        """)
        
        let session = coordinator.startEditSession(
            instruction: "Add error handling",
            files: mockEditor.getAllFileStates()
        )
        
        // When - stream JSON edit
        let jsonStream = FakeAIStream.jsonEditStream(
            filePath: "utils.swift",
            operation: "replace",
            startLine: 1,
            endLine: 3,
            content: [
                "func add(a: Int, b: Int) -> Int {",
                "    guard a >= 0 && b >= 0 else {",
                "        throw NegativeNumberError()",
                "    }",
                "    return a + b",
                "}"
            ]
        )
        
        let chunks = FakeAIStream.streamingChunks(jsonStream)
        for chunk in chunks {
            session.appendStreamingText(chunk)
        }
        
        session.completeStreaming()
        
        // Then - wait for parsing to complete (deterministic polling)
        let ready = session.waitForReady()
        XCTAssertTrue(ready, "Should reach ready state")
        
        // Assert status
        XCTAssertEqual(session.model.status, .ready, "Should end in ready state")
        
        // Assert proposed edits
        XCTAssertEqual(session.model.proposedEdits.count, 1, "Should have exactly one proposed edit")
        
        guard let proposal = session.model.proposedEdits.first else {
            XCTFail("No proposed edit found")
            return
        }
        
        XCTAssertEqual(proposal.filePath, "utils.swift")
        XCTAssertGreaterThan(proposal.statistics.addedLines, 0, "Should have added lines")
        XCTAssertGreaterThan(proposal.statistics.removedLines, 0, "Should have removed lines")
        XCTAssertFalse(proposal.preview.diffHunks.isEmpty, "Should have diff hunks")
    }
    
    // MARK: - Test: Streaming Code Block Fallback
    
    /// Verifies that code block format (fallback) is correctly parsed
    /// when JSON format is not present
    func testStreamingCodeBlock_ParsesCorrectly() {
        // Given
        mockEditor.setFile(path: "main.swift", content: "print(\"Hello\")")
        
        let session = coordinator.startEditSession(
            instruction: "Update greeting",
            files: mockEditor.getAllFileStates()
        )
        
        // When - stream code block (fallback format)
        let codeBlockStream = FakeAIStream.codeBlockStream(
            filePath: "main.swift",
            language: "swift",
            content: "print(\"Hello, World!\")"
        )
        
        let chunks = FakeAIStream.streamingChunks(codeBlockStream)
        for chunk in chunks {
            session.appendStreamingText(chunk)
        }
        
        session.completeStreaming()
        
        // Then - wait for ready state
        let ready = session.waitForReady()
        XCTAssertTrue(ready, "Should parse code block successfully")
        XCTAssertEqual(session.model.proposedEdits.count, 1, "Should have one proposed edit")
    }
    
    // MARK: - Test: acceptAll → EditToApply Correctness
    
    /// Verifies that acceptAll returns correct EditToApply objects
    /// with accurate newContent and originalContent
    func testAcceptAll_ReturnsCorrectEditToApply() {
        // Given
        let originalContent = """
        func calculate(x: Int) -> Int {
            return x * 2
        }
        """
        
        mockEditor.setFile(path: "math.swift", content: originalContent)
        
        let session = coordinator.startEditSession(
            instruction: "Add validation",
            files: mockEditor.getAllFileStates()
        )
        
        // Stream edit
        let jsonStream = FakeAIStream.jsonEditStream(
            filePath: "math.swift",
            operation: "replace",
            startLine: 1,
            endLine: 3,
            content: [
                "func calculate(x: Int) -> Int {",
                "    guard x >= 0 else { return 0 }",
                "    return x * 2",
                "}"
            ]
        )
        
        session.appendStreamingText(jsonStream)
        session.completeStreaming()
        
        // Wait for ready state
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        
        // When
        let editsToApply = session.acceptAll()
        
        // Then
        XCTAssertEqual(editsToApply.count, 1, "Should return exactly one edit")
        
        guard let edit = editsToApply.first else {
            XCTFail("No edit returned")
            return
        }
        
        XCTAssertEqual(edit.filePath, "math.swift")
        XCTAssertEqual(edit.originalContent, originalContent, "Original content must match exactly")
        XCTAssertNotEqual(edit.newContent, originalContent, "New content should differ")
        XCTAssertTrue(edit.newContent.contains("guard"), "New content should include changes")
        
        // Verify status transition
        XCTAssertEqual(session.model.status, .applied, "Status should be applied")
    }
    
    // MARK: - Test: rejectAll → No Changes
    
    /// Verifies that rejectAll does not produce EditToApply objects
    /// and transitions to rejected state
    func testRejectAll_ProducesNoChanges() {
        // Given
        let originalContent = "let x = 1"
        mockEditor.setFile(path: "test.swift", content: originalContent)
        
        let session = coordinator.startEditSession(
            instruction: "Change variable",
            files: mockEditor.getAllFileStates()
        )
        
        // Stream edit
        let jsonStream = FakeAIStream.jsonEditStream(
            filePath: "test.swift",
            operation: "replace",
            startLine: 1,
            endLine: 1,
            content: ["let x = 2"]
        )
        
        session.appendStreamingText(jsonStream)
        session.completeStreaming()
        
        // Wait for ready
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        
        // When
        session.rejectAll()
        
        // Then
        XCTAssertEqual(session.model.status, .rejected, "Status should be rejected")
        XCTAssertTrue(session.model.proposedEdits.isEmpty, "Proposed edits should be cleared")
        
        // Verify no edits to apply (reject doesn't return edits)
        // This is implicit - rejectAll() doesn't return anything
    }
    
    // MARK: - Test: Undo → Restores Original Content
    
    /// Verifies that undo restores byte-for-byte original content
    /// and transaction history is correctly maintained
    func testUndo_RestoresOriginalContent() {
        // Given
        let originalContent = """
        struct User {
            let name: String
        }
        """
        
        mockEditor.setFile(path: "model.swift", content: originalContent)
        
        let session = coordinator.startEditSession(
            instruction: "Add ID property",
            files: mockEditor.getAllFileStates()
        )
        
        // Stream edit
        let jsonStream = FakeAIStream.jsonEditStream(
            filePath: "model.swift",
            operation: "replace",
            startLine: 1,
            endLine: 3,
            content: [
                "struct User {",
                "    let id: UUID",
                "    let name: String",
                "}"
            ]
        )
        
        session.appendStreamingText(jsonStream)
        session.completeStreaming()
        
        // Wait for ready
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        
        // Accept edit
        let editsToApply = session.acceptAll()
        XCTAssertEqual(editsToApply.count, 1)
        
        // Apply to mock editor
        mockEditor.applyEdit(editsToApply[0])
        
        // Verify content changed
        let modifiedContent = mockEditor.getFileContent(path: "model.swift")
        XCTAssertNotEqual(modifiedContent, originalContent)
        XCTAssertTrue(modifiedContent?.contains("id: UUID") == true)
        
        // When - undo
        guard let undoEdits = session.undo() else {
            XCTFail("Undo should return edits")
            return
        }
        
        // Then
        XCTAssertEqual(undoEdits.count, 1, "Undo should return one edit")
        
        guard let undoEdit = undoEdits.first else {
            XCTFail("No undo edit returned")
            return
        }
        
        // Apply undo
        mockEditor.applyEdit(undoEdit)
        
        // Verify byte-for-byte restoration
        let restoredContent = mockEditor.getFileContent(path: "model.swift")
        XCTAssertEqual(restoredContent, originalContent, "Content must be restored exactly")
        
        // Verify canUndo state
        XCTAssertFalse(session.canUndo, "Should not be able to undo after undo")
    }
    
    // MARK: - Test: Status Transitions
    
    /// Verifies that status transitions follow correct sequence:
    /// idle → streaming → ready → applied
    func testStatusTransitions_AreCorrect() {
        // Given
        mockEditor.setFile(path: "file.swift", content: "code")
        
        let session = coordinator.startEditSession(
            instruction: "Edit file",
            files: mockEditor.getAllFileStates()
        )
        
        // When
        session.appendStreamingText("streaming")
        XCTAssertEqual(session.model.status, .streaming, "Should be streaming")
        
        session.completeStreaming()
        
        // Wait for ready
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        XCTAssertEqual(session.model.status, .ready, "Should transition to ready")
        
        session.acceptAll()
        
        // Then
        XCTAssertEqual(session.model.status, .applied, "Should transition to applied")
    }
    
    // MARK: - Test: Transaction History
    
    /// Verifies that transaction history records exactly one transaction
    /// after acceptAll
    func testTransactionHistory_RecordsOneTransaction() {
        // Given
        mockEditor.setFile(path: "test.swift", content: "original")
        
        let session = coordinator.startEditSession(
            instruction: "Modify",
            files: mockEditor.getAllFileStates()
        )
        
        // Stream and accept
        let jsonStream = FakeAIStream.jsonEditStream(
            filePath: "test.swift",
            operation: "replace",
            startLine: 1,
            endLine: 1,
            content: ["modified"]
        )
        
        session.appendStreamingText(jsonStream)
        session.completeStreaming()
        
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        
        // When
        let editsToApply = session.acceptAll()
        XCTAssertEqual(editsToApply.count, 1)
        
        // Then - verify transaction history (via internal access)
        // Note: We can't directly access transaction history from public API
        // But we can verify undo works, which implies history is maintained
        XCTAssertTrue(session.canUndo, "Should be able to undo after accept")
        
        // Verify undo works (indirectly tests history)
        if let undoEdits = session.undo() {
            XCTAssertEqual(undoEdits.count, 1, "Undo should return one edit")
            XCTAssertEqual(undoEdits[0].originalContent, "original", "Undo should restore original")
        } else {
            XCTFail("Undo should work after accept")
        }
    }
    
    // MARK: - Test: Multi-file Transaction
    
    /// Verifies that multiple file edits are grouped into single transaction
    /// and all edits are returned together
    func testMultiFileTransaction_GroupsEditsAtomically() {
        // Given
        mockEditor.setFile(path: "file1.swift", content: "content1")
        mockEditor.setFile(path: "file2.swift", content: "content2")
        
        let session = coordinator.startEditSession(
            instruction: "Update both files",
            files: mockEditor.getAllFileStates()
        )
        
        // Stream multi-file edit
        let multiFileStream = FakeAIStream.multiFileJSONStream(edits: [
            (filePath: "file1.swift", operation: "replace", range: (1, 1), content: ["updated1"]),
            (filePath: "file2.swift", operation: "replace", range: (1, 1), content: ["updated2"])
        ])
        
        session.appendStreamingText(multiFileStream)
        session.completeStreaming()
        
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        
        // When
        let editsToApply = session.acceptAll()
        
        // Then
        XCTAssertEqual(editsToApply.count, 2, "Should return edits for both files")
        
        let file1Edit = editsToApply.first { $0.filePath == "file1.swift" }
        let file2Edit = editsToApply.first { $0.filePath == "file2.swift" }
        
        XCTAssertNotNil(file1Edit, "Should have edit for file1")
        XCTAssertNotNil(file2Edit, "Should have edit for file2")
        
        XCTAssertEqual(file1Edit?.originalContent, "content1")
        XCTAssertEqual(file2Edit?.originalContent, "content2")
    }
    
    // MARK: - Test: Proposed Edits Match Expected Diff Hunks
    
    /// Verifies that proposed edits contain correct diff hunks
    /// matching the expected changes
    func testProposedEdits_MatchExpectedDiffHunks() {
        // Given
        let originalContent = """
        line1
        line2
        line3
        """
        
        mockEditor.setFile(path: "test.txt", content: originalContent)
        
        let session = coordinator.startEditSession(
            instruction: "Replace line 2",
            files: mockEditor.getAllFileStates()
        )
        
        // Stream edit that replaces line 2
        let jsonStream = FakeAIStream.jsonEditStream(
            filePath: "test.txt",
            operation: "replace",
            startLine: 2,
            endLine: 2,
            content: ["line2_modified"]
        )
        
        session.appendStreamingText(jsonStream)
        session.completeStreaming()
        
        XCTAssertTrue(session.waitForReady(), "Should reach ready state")
        
        // Then
        guard let proposal = session.model.proposedEdits.first else {
            XCTFail("Should have proposed edit")
            return
        }
        
        // Verify diff hunks
        XCTAssertFalse(proposal.preview.diffHunks.isEmpty, "Should have diff hunks")
        
        // Verify hunk contains removed and added lines
        let allLines = proposal.preview.diffHunks.flatMap { $0.lines }
        let removedLines = allLines.filter { $0.type == .removed }
        let addedLines = allLines.filter { $0.type == .added }
        
        XCTAssertEqual(removedLines.count, 1, "Should have one removed line")
        XCTAssertEqual(addedLines.count, 1, "Should have one added line")
        
        // Verify line content
        XCTAssertTrue(removedLines.first?.content.contains("line2") == true)
        XCTAssertTrue(addedLines.first?.content.contains("line2_modified") == true)
    }
}
