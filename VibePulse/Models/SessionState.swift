//
//  SessionState.swift
//  VibePulse
//
//  Simplified session state (stripped chat/tool tracking from Vibe Notch)
//

import Foundation

struct SessionState: Equatable, Identifiable, Sendable {
    // MARK: - Identity

    let sessionId: String
    let cwd: String
    let projectName: String

    // MARK: - Instance Metadata

    var pid: Int?
    var tty: String?
    var isInTmux: Bool

    // MARK: - State Machine

    var phase: SessionPhase

    // MARK: - Timestamps

    var lastActivity: Date
    var createdAt: Date

    // MARK: - Identifiable

    var id: String { sessionId }

    // MARK: - Initialization

    nonisolated init(
        sessionId: String,
        cwd: String,
        projectName: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        isInTmux: Bool = false,
        phase: SessionPhase = .idle,
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.projectName = projectName ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.pid = pid
        self.tty = tty
        self.isInTmux = isInTmux
        self.phase = phase
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    // MARK: - Derived Properties

    var needsAttention: Bool {
        phase.needsAttention
    }

    var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    var stableId: String {
        if let pid = pid {
            return "\(pid)-\(sessionId)"
        }
        return sessionId
    }
}
