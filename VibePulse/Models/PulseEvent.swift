//
//  PulseEvent.swift
//  VibePulse
//
//  Core event types and notification levels
//

import Foundation

/// The 7 event types Vibe Pulse tracks
enum PulseEventType: String, Codable, Sendable {
    case testPassed         // Tests passed
    case testFailed         // Tests failed
    case buildFailed        // Build/compilation failed
    case taskCompleted      // Claude finished (Stop event)
    case repeatedFailure    // Same failure >= 3 times in 60s
    case claudeAsking       // Claude asking user a question
    case permissionRequest  // Tool needs permission
}

/// Three-tier notification level
enum NotificationLevel: Int, Codable, Comparable, Sendable {
    case silent = 0   // Only record to timeline
    case remind = 1   // Notch card + soft sound
    case alert  = 2   // Notch card + strong sound + persistent

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A classified event ready for notification
struct PulseEvent: Identifiable, Sendable {
    let id: UUID
    let type: PulseEventType
    let sessionId: String
    let projectName: String
    let summary: String
    let detail: String?
    let level: NotificationLevel
    let timestamp: Date
    var mergeCount: Int
    let toolUseId: String?

    init(
        id: UUID = UUID(),
        type: PulseEventType,
        sessionId: String,
        projectName: String,
        summary: String,
        detail: String? = nil,
        level: NotificationLevel,
        timestamp: Date = Date(),
        mergeCount: Int = 1,
        toolUseId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.sessionId = sessionId
        self.projectName = projectName
        self.summary = summary
        self.detail = detail
        self.level = level
        self.timestamp = timestamp
        self.mergeCount = mergeCount
        self.toolUseId = toolUseId
    }

    /// Fingerprint for deduplication
    var fingerprint: String {
        "\(sessionId):\(type.rawValue):\(String(summary.prefix(64)))"
    }
}
