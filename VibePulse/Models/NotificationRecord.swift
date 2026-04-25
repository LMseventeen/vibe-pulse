//
//  NotificationRecord.swift
//  VibePulse
//
//  Notification history record for the timeline
//

import Foundation

struct NotificationRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let eventType: PulseEventType
    let sessionId: String
    let projectName: String
    let summary: String
    let level: NotificationLevel
    let timestamp: Date
    var acknowledged: Bool

    init(from event: PulseEvent, acknowledged: Bool = false) {
        self.id = event.id
        self.eventType = event.type
        self.sessionId = event.sessionId
        self.projectName = event.projectName
        self.summary = event.summary
        self.level = event.level
        self.timestamp = event.timestamp
        self.acknowledged = acknowledged
    }
}
