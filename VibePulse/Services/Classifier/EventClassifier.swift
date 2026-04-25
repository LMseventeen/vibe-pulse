//
//  EventClassifier.swift
//  VibePulse
//
//  Core module: classifies raw events into PulseEvents with notification levels
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "Classifier")

actor EventClassifier {
    static let shared = EventClassifier()

    private init() {}

    /// Classify a raw captured event into a PulseEvent (or nil if not notifiable)
    func classify(_ raw: RawCapturedEvent, session: SessionState) -> PulseEvent? {
        let hookEvent = raw.hookEvent

        // 1. Check bash signals first (test pass from stdout analysis)
        if let bashSignal = raw.bashSignal {
            return classifyBashSignal(bashSignal, session: session)
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

        default:
            return nil
        }
    }

    // MARK: - Bash Signal Classification

    private func classifyBashSignal(_ signal: BashSignal, session: SessionState) -> PulseEvent {
        switch signal {
        case .testPassed(let summary):
            return PulseEvent(
                type: .testPassed,
                sessionId: session.sessionId,
                projectName: session.projectName,
                summary: summary,
                level: .silent
            )
        }
    }
}
