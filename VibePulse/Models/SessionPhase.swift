//
//  SessionPhase.swift
//  VibePulse
//
//  Session lifecycle state machine (reused from Vibe Notch)
//

import Foundation

/// Permission context for tools waiting for approval
struct PermissionContext: Sendable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let receivedAt: Date

    var formattedInput: String? {
        guard let input = toolInput else { return nil }

        if toolName == "Bash", let command = input["command"]?.value as? String {
            return command.count > 100 ? String(command.prefix(100)) + "..." : command
        }
        if toolName == "Write" || toolName == "Edit", let path = input["file_path"]?.value as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        let priorityKeys = ["command", "file_path", "path", "query", "pattern", "url"]
        for key in priorityKeys {
            if let value = input[key]?.value as? String {
                return value.count > 100 ? String(value.prefix(100)) + "..." : value
            }
        }

        return nil
    }
}

extension PermissionContext: Equatable {
    nonisolated static func == (lhs: PermissionContext, rhs: PermissionContext) -> Bool {
        lhs.toolUseId == rhs.toolUseId &&
        lhs.toolName == rhs.toolName &&
        lhs.receivedAt == rhs.receivedAt
    }
}

enum SessionPhase: Sendable {
    case idle
    case processing
    case waitingForInput
    case waitingForApproval(PermissionContext)
    case compacting
    case ended

    nonisolated func canTransition(to next: SessionPhase) -> Bool {
        switch (self, next) {
        case (.ended, _): return false
        case (_, .ended): return true
        case (.idle, .processing): return true
        case (.idle, .waitingForApproval): return true
        case (.idle, .compacting): return true
        case (.processing, .waitingForInput): return true
        case (.processing, .waitingForApproval): return true
        case (.processing, .compacting): return true
        case (.processing, .idle): return true
        case (.waitingForInput, .processing): return true
        case (.waitingForInput, .idle): return true
        case (.waitingForInput, .compacting): return true
        case (.waitingForApproval, .processing): return true
        case (.waitingForApproval, .idle): return true
        case (.waitingForApproval, .waitingForInput): return true
        case (.waitingForApproval, .waitingForApproval): return true
        case (.compacting, .processing): return true
        case (.compacting, .idle): return true
        case (.compacting, .waitingForInput): return true
        default: return self == next
        }
    }

    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForInput: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .processing, .compacting: return true
        default: return false
        }
    }

    var isWaitingForApproval: Bool {
        if case .waitingForApproval = self { return true }
        return false
    }

    var approvalToolName: String? {
        if case .waitingForApproval(let ctx) = self { return ctx.toolName }
        return nil
    }
}

extension SessionPhase: Equatable {
    nonisolated static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.processing, .processing): return true
        case (.waitingForInput, .waitingForInput): return true
        case (.waitingForApproval(let a), .waitingForApproval(let b)): return a == b
        case (.compacting, .compacting): return true
        case (.ended, .ended): return true
        default: return false
        }
    }
}

extension SessionPhase: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .idle: return "idle"
        case .processing: return "processing"
        case .waitingForInput: return "waitingForInput"
        case .waitingForApproval(let ctx): return "waitingForApproval(\(ctx.toolName))"
        case .compacting: return "compacting"
        case .ended: return "ended"
        }
    }
}
