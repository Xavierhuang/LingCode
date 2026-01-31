//
//  TransactionDiskExecution.swift
//  EditorCore
//
//  High-integrity disk execution: snapshot before apply, restore on any failure.
//  ApplyCodeService (LingCode) implements DiskWriteAdapter to perform physical writes.
//

import Foundation

/// Snapshot of workspace state for rollback on transaction failure.
public protocol WorkspaceSnapshotProtocol {
    func restore(to workspaceURL: URL) throws
}

/// Adapter that performs a single edit to disk (write or delete).
public protocol DiskWriteAdapter {
    /// Write or delete one edit. Returns the file URL that was affected. Throws on failure.
    func writeEdit(_ edit: ProposedEdit, workspaceURL: URL) throws -> URL
}

/// High-integrity execution: create snapshot, apply each edit via adapter, restore on any failure.
extension EditTransaction {

    /// Execute this transaction to disk with snapshot and rollback. Single unified pipeline.
    /// - Parameters:
    ///   - workspaceURL: Project root for resolving relative paths.
    ///   - createSnapshot: Called once before applying; result is used to restore on failure.
    ///   - adapter: Performs each edit (write or delete); throws on failure.
    ///   - onProgress: Optional progress (current index, total count).
    /// - Returns: Success with applied file URLs, or failure (snapshot is restored before return).
    public func executeToDisk(
        workspaceURL: URL,
        createSnapshot: () -> WorkspaceSnapshotProtocol,
        adapter: DiskWriteAdapter,
        onProgress: ((Int, Int) -> Void)?
    ) -> Result<[URL], Error> {
        let snapshot = createSnapshot()
        var applied: [URL] = []
        let total = edits.count

        for (index, edit) in edits.enumerated() {
            onProgress?(index + 1, total)
            do {
                let url = try adapter.writeEdit(edit, workspaceURL: workspaceURL)
                applied.append(url)
            } catch {
                try? snapshot.restore(to: workspaceURL)
                return .failure(error)
            }
        }
        return .success(applied)
    }
}
