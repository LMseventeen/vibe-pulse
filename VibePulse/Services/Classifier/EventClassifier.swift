//
//  EventClassifier.swift
//  VibePulse
//
//  Core module: classifies raw events into PulseEvents with notification levels
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "Classifier")

/// Tracks recent events for repeated-failure detection
private struct RecentFailure: Sendable {
    let sessionId: String
    let type: PulseEventType
    let timestamp: Date
}

actor EventClassifier {
    static let shared = EventClassifier()

    /// Ring buffer of recent failures for repeated-failure detection
    private var recentFailures: [RecentFailure] = []
    private let maxRecentFailures = 50
    private let repeatedFailureWindow: TimeInterval = 60  // 60 seconds
    private let repeatedFailureThreshold = 3

    private init() {}

    /// Classify a raw captured event into a PulseEvent (or nil if not notifiable)
    func classify(_ raw: RawCapturedEvent, session: SessionState) -> PulseEvent? {
        let hookEvent = raw.hookEvent

        // 1. Check bash signals first (test/build results from stdout analysis)
        if let bashSignal = raw.bashSignal {
            return classifyBashSignal(bashSignal, hookEvent: hookEvent, session: session)
        }

        // 2. Check hook event types
        switch hookEvent.event {
        case "Stop":
            return PulseEvent(
                type: .taskCompleted,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: "Task completed",
                level: .remind,
                timestamp: raw.timestamp
            )

        case "StopFailure":
            let errorMsg = hookEvent.stopError ?? "API error"
            return PulseEvent(
                type: .taskCompleted,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: "Task stopped: \(String(errorMsg.prefix(80)))",
                level: .remind,
                timestamp: raw.timestamp
            )

        case "Notification":
            if hookEvent.notificationType == "idle_prompt" {
                let message = hookEvent.message ?? "Waiting for input"
                return PulseEvent(
                    type: .claudeAsking,
                    sessionId: session.sessionId,
                    projectName: session.projectName,
                    summary: String(message.prefix(100)),
                    detail: message,
                    level: .remind,
                    timestamp: raw.timestamp
                )
            }
            return nil

        case "PermissionRequest":
            let toolName = hookEvent.tool ?? "unknown"
            let input = hookEvent.toolInput?["command"]?.value as? String
            let summary = "Permission: \(toolName)"
            return PulseEvent(
                type: .permissionRequest,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: summary,
                detail: input.map { String($0.prefix(200)) },
                level: .alert,
                timestamp: raw.timestamp,
                toolUseId: hookEvent.toolUseId
            )

        case "PostToolUse", "PostToolUseFailure":
            // Non-bash tool events without a bash signal -- not directly notifiable
            // But check for exit code failures on bash tools
            if let exitCode = hookEvent.exitCode, exitCode != 0,
               hookEvent.stdout == nil || hookEvent.stdout?.isEmpty == true {
                // Build failure with no recognized test pattern
                let bashCmd = hookEvent.bashCommand ?? "command"
                if PatternRules.isBuildCommand(bashCmd) {
                    let event = PulseEvent(
                        type: .buildFailed,
                        sessionId: session.sessionId,
                        projectName: session.projectName,
                        summary: "Build failed (exit \(exitCode))",
                        detail: hookEvent.toolError,
                        level: .alert,
                        timestamp: raw.timestamp
                    )
                    trackFailure(event)
                    return checkForRepeatedFailure(session: session, timestamp: raw.timestamp) ?? event
                }
            }
            return nil

        case "SessionStart", "SessionEnd":
            // These are handled by PulseStore for session lifecycle, not notifications
            return nil

        default:
            return nil
        }
    }

    // MARK: - Bash Signal Classification

    private func classifyBashSignal(_ signal: BashSignal, hookEvent: HookEvent, session: SessionState) -> PulseEvent {
        switch signal {
        case .testPassed(let summary):
            return PulseEvent(
                type: .testPassed,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: summary,
                level: .silent
            )

        case .testFailed(let summary):
            let event = PulseEvent(
                type: .testFailed,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: summary,
                detail: hookEvent.stderr,
                level: .alert
            )
            trackFailure(event)
            return checkForRepeatedFailure(session: session, timestamp: event.timestamp) ?? event

        case .buildFailed(let summary):
            let event = PulseEvent(
                type: .buildFailed,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: summary,
                detail: hookEvent.stderr,
                level: .alert
            )
            trackFailure(event)
            return checkForRepeatedFailure(session: session, timestamp: event.timestamp) ?? event
        }
    }

    // MARK: - Repeated Failure Detection

    private func trackFailure(_ event: PulseEvent) {
        let failure = RecentFailure(
            sessionId: event.sessionId,
            type: event.type,
            timestamp: event.timestamp
        )
        recentFailures.append(failure)

        // Trim old entries
        if recentFailures.count > maxRecentFailures {
            recentFailures.removeFirst(recentFailures.count - maxRecentFailures)
        }
    }

    /// Check if recent failures for this session exceed the threshold
    private func checkForRepeatedFailure(session: SessionState, timestamp: Date) -> PulseEvent? {
        let cutoff = timestamp.addingTimeInterval(-repeatedFailureWindow)
        let recentForSession = recentFailures.filter {
            $0.sessionId == session.sessionId && $0.timestamp > cutoff
        }

        if recentForSession.count >= repeatedFailureThreshold {
            return PulseEvent(
                type: .repeatedFailure,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: "\(recentForSession.count) failures in the last minute",
                level: .alert,
                timestamp: timestamp
            )
        }

        return nil
    }
}
