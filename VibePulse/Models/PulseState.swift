//
//  PulseState.swift
//  VibePulse
//
//  Aggregated UI state snapshot published by PulseStore
//

import Foundation

/// Aggregate status for the status indicator dot
enum AggregateStatus: Equatable, Sendable {
    case inactive      // No active sessions (gray)
    case processing    // At least one session processing (blue)
    case idle          // All sessions idle/waiting (green)
    case waiting       // Waiting for permission (orange)
    case error         // Recent alert-level failure (red)
}

struct PulseState: Equatable, Sendable {
    static func == (lhs: PulseState, rhs: PulseState) -> Bool {
        lhs.sessions == rhs.sessions &&
        lhs.currentCard == rhs.currentCard &&
        lhs.pendingCount == rhs.pendingCount &&
        lhs.aggregateStatus == rhs.aggregateStatus &&
        lhs.history.count == rhs.history.count
    }

    let sessions: [SessionState]
    let currentCard: NotificationCard?
    let pendingCount: Int
    let history: [NotificationRecord]
    let aggregateStatus: AggregateStatus

    static let empty = PulseState(
        sessions: [],
        currentCard: nil,
        pendingCount: 0,
        history: [],
        aggregateStatus: .inactive
    )
}
