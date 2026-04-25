//
//  NotificationCard.swift
//  VibePulse
//
//  Model for the notification card displayed in the notch
//

import SwiftUI

struct NotificationCard: Identifiable, Equatable, Sendable {
    static func == (lhs: NotificationCard, rhs: NotificationCard) -> Bool {
        lhs.id == rhs.id
    }

    let id: UUID
    let event: PulseEvent
    let displayDuration: TimeInterval?  // nil = persistent until dismissed
    let actions: [CardAction]

    init(event: PulseEvent) {
        self.id = event.id
        self.event = event

        switch event.level {
        case .silent:
            self.displayDuration = nil
            self.actions = []
        case .remind:
            self.displayDuration = 3.0
            self.actions = [.jumpToTerminal]
        case .alert:
            self.displayDuration = nil  // Persistent until user clicks
            self.actions = [.jumpToTerminal]
        }
    }

    var icon: String {
        switch event.type {
        case .testPassed:        return "checkmark.circle.fill"
        case .taskCompleted:     return "checkmark.seal.fill"
        case .claudeAsking:      return "questionmark.bubble.fill"
        case .permissionRequest: return "lock.shield.fill"
        }
    }

    var iconColor: Color {
        switch event.type {
        case .testPassed:        return .green
        case .taskCompleted:     return .green
        case .claudeAsking:      return .blue
        case .permissionRequest: return .orange
        }
    }

    var title: String {
        switch event.type {
        case .testPassed:        return "Tests Passed"
        case .taskCompleted:     return "Task Completed"
        case .claudeAsking:      return "Claude Asking"
        case .permissionRequest: return "Permission Required"
        }
    }
}

enum CardAction: Equatable, Sendable {
    case jumpToTerminal
    case dismiss
}
