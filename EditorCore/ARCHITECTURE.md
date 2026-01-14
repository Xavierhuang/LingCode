# EditorCore Architecture

## Module Overview

EditorCore is a pure Swift module that implements a Cursor-style AI Edit Session engine. It provides a clean separation between AI-generated edits and the actual editor, allowing for preview, diff generation, and explicit accept/reject workflows.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      EditorCore Module                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  AIEditSession   │────────▶│ EditSessionState  │         │
│  │  (Orchestrator)  │         │   (State Machine) │         │
│  └────────┬─────────┘         └──────────────────┘         │
│           │                                                   │
│           │ uses                                              │
│           ▼                                                   │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  StreamParser    │────────▶│   DiffEngine     │         │
│  │  (Text Parser)   │         │  (Diff Computer) │         │
│  └──────────────────┘         └────────┬─────────┘         │
│                                         │                    │
│                                         │ generates          │
│                                         ▼                    │
│                                ┌──────────────────┐          │
│                                │  ProposedEdit    │          │
│                                │  (Edit Proposal) │          │
│                                └──────────────────┘          │
│                                                               │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  FileSnapshot    │         │  EditMetadata    │         │
│  │  (File State)    │         │  (Edit Info)    │         │
│  └──────────────────┘         └──────────────────┘         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### AIEditSession
- Main entry point for edit sessions
- Manages session lifecycle
- Coordinates between parser, diff engine, and state machine
- Provides streaming text interface
- Handles transaction creation, commit, and rollback
- Supports undo/redo operations
- Ensures atomic operations (no partial commits)

### EditSessionState
- State machine for session lifecycle
- States: idle → streaming → parsing → proposed → accepted/rejected
- Ensures valid state transitions
- Thread-safe state management

### StreamParser
- Parses streaming AI text output
- Extracts code blocks, file paths, and edit instructions
- Supports JSON edit format and traditional code blocks
- Produces structured edit proposals

### DiffEngine
- Computes unified diffs between old and new content
- Supports line-level and character-level diffs
- Generates diff hunks with context
- Provides diff statistics (added/removed lines)

### ProposedEdit
- Represents a single edit proposal for a file
- Contains file path, original content, proposed content, and diff
- Includes metadata (confidence, edit type, etc.)
- Immutable once created

### FileSnapshot
- Immutable representation of file state
- Contains path, content, and optional metadata
- Used for diff computation

### EditTransaction
- Groups multiple ProposedEdit objects into a single atomic operation
- Ensures all edits are applied together or not at all
- Validates transaction before commit
- Tracks affected files

### TransactionSnapshot
- Captures file state before a transaction is applied
- Used for undo operations
- Immutable snapshot of affected files

### TransactionHistory
- Manages undo/redo stack
- Tracks applied and reverted transactions
- Provides transaction snapshots for restoration

## Data Flow

1. **Session Creation**: Client creates `AIEditSession` with instruction + file snapshots
2. **Streaming**: Client feeds streaming text chunks to session
3. **Parsing**: `StreamParser` extracts edits from stream
4. **Diff Generation**: `DiffEngine` computes diffs for each edit
5. **Proposal**: Session transitions to `proposed` state with `ProposedEdit` objects
6. **Transaction Creation**: Client creates `EditTransaction` from selected edits
7. **Transaction Ready**: Session validates and prepares transaction
8. **Commit/Rollback**: Client commits (atomic) or rolls back transaction
9. **Undo/Redo**: Client can undo committed transactions or redo reverted ones

## State Machine

```
idle ──[start]──▶ streaming ──[text chunk]──▶ streaming
  │                                              │
  │                                              │
  │                                    [stream complete]
  │                                              │
  │                                              ▼
  │                                        parsing
  │                                              │
  │                                    [parse complete]
  │                                              │
  │                                              ▼
  │                                        proposed
  │                                              │
  │                              [prepare transaction]
  │                                              │
  │                                              ▼
  │                                  transactionReady
  │                                              │
  │                              [commit]    [rollback]
  │                                              │
  │                                              ▼
  │                            committed / rolledBack
  │                                              │
  │                                    [reset to idle]
  │                                              │
  └────────────────────────────────────────────┘
```

## Transaction Model

- **EditTransaction**: Groups multiple edits into a single atomic operation
- **TransactionSnapshot**: Captures state before transaction (for undo)
- **TransactionHistory**: Manages undo/redo stack
- **Atomic Operations**: All edits in a transaction are applied together or not at all
- **Reversibility**: Every committed transaction can be undone

## Design Principles

1. **Immutability**: File snapshots and proposed edits are immutable
2. **Pure Functions**: Diff computation is deterministic and side-effect free
3. **Composability**: Components can be used independently
4. **Testability**: All logic is testable without UI or file system
5. **Future-Ready**: Architecture supports future AST integration
6. **Atomicity**: Transactions ensure all-or-nothing operations
7. **Reversibility**: All committed transactions can be undone
8. **Safety**: No partial editor state is ever committed
