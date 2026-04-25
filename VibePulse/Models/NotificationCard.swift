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
            self.displayDuration = 5.0
            self.actions = [.jumpToTerminal, .dismiss]
        case .alert:
            self.displayDuration = nil  // Persistent
            if event.type == .permissionRequest {
                self.actions = [.approve, .deny, .jumpToTerminal]
            } else {
                self.actions = [.jumpToTerminal, .dismiss]
            }
        }
    }

    var icon: String {
        switch event.type {
        case .testPassed:        return "checkmark.circle.fill"
        case .testFailed:        return "xmark.circle.fill"
        case .buildFailed:       return "hammer.circle.fill"
        case .taskCompleted:     return "checkmark.seal.fill"
        case .repeatedFailure:   return "exclamationmark.triangle.fill"
        case .claudeAsking:      return "questionmark.bubble.fill"
        case .permissionRequest: return "lock.shield.fill"
        }
    }

    var iconColor: Color {
        switch event.type {
        case .testPassed:        return .green
        case .testFailed:        return .red
        case .buildFailed:       return .red
        case .taskCompleted:     return .blue
        case .repeatedFailure:   return .orange
        case .claudeAsking:      return .blue
        case .permissionRequest: return .orange
        }
    }

    var title: String {
        switch event.type {
        case .testPassed:        return "Tests Passed"
        case .testFailed:        return "Tests Failed"
        case .buildFailed:       return "Build Failed"
        case .taskCompleted:     return "Task Completed"
        case .repeatedFailure:   return "Repeated Failure"
        case .claudeAsking:      return "Claude Asking"
        case .permissionRequest: return "Permission Required"
        }
    }
}

enum CardAction: Equatable, Sendable {
    case jumpToTerminal
    case dismiss
    case approve
    case deny
}
