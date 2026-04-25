//
//  NotificationQueue.swift
//  VibePulse
//
//  Notification queue with deduplication and throttling
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "NotificationQueue")

actor NotificationQueue {
    static let shared = NotificationQueue()

    /// Pending notifications sorted by priority
    private var queue: [NotificationCard] = []

    /// Dedup window: fingerprint -> last timestamp
    private var deduplicationWindow: [String: Date] = [:]

    /// Throttle interval: same-fingerprint events within this window are merged
    private let throttleInterval: TimeInterval = 5.0

    /// Maximum queue depth
    private let maxQueueSize = 20

    init() {}

    /// Enqueue a new event. Returns the card if it was actually enqueued (not deduped).
    func enqueue(_ event: PulseEvent) -> NotificationCard? {
        // Silent events don't queue for display
        guard event.level != .silent else { return nil }

        let fingerprint = event.fingerprint
        let now = Date()

        // Deduplication: merge if same fingerprint within throttle window
        if let lastTime = deduplicationWindow[fingerprint],
           now.timeIntervalSince(lastTime) < throttleInterval {
            // Find existing card with same fingerprint and bump its merge count
            if let idx = queue.firstIndex(where: { $0.event.fingerprint == fingerprint }) {
                var existingEvent = queue[idx].event
                existingEvent.mergeCount += 1
                queue[idx] = NotificationCard(event: existingEvent)
                deduplicationWindow[fingerprint] = now
                logger.debug("Merged event: \(fingerprint.prefix(40), privacy: .public) x\(existingEvent.mergeCount)")
                return nil
            }
        }

        deduplicationWindow[fingerprint] = now

        let card = NotificationCard(event: event)
        queue.append(card)

        // Sort: alert > remind, then by timestamp (oldest first)
        queue.sort { a, b in
            if a.event.level != b.event.level {
                return a.event.level > b.event.level
            }
            return a.event.timestamp < b.event.timestamp
        }

        // Trim excess
        if queue.count > maxQueueSize {
            queue = Array(queue.prefix(maxQueueSize))
        }

        // Clean old dedup entries
        cleanupDeduplicationWindow(now: now)

        logger.debug("Enqueued: \(event.type.rawValue, privacy: .public) level=\(event.level.rawValue) queue=\(self.queue.count)")

        return card
    }

    /// Dequeue the next notification card to display
    func dequeue() -> NotificationCard? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    /// Peek at the next card without removing
    func peek() -> NotificationCard? {
        queue.first
    }

    /// Current queue depth
    var pendingCount: Int {
        queue.count
    }

    /// Remove a specific card (when dismissed)
    func remove(id: UUID) {
        queue.removeAll { $0.id == id }
    }

    /// Clear all pending notifications
    func clear() {
        queue.removeAll()
        deduplicationWindow.removeAll()
    }

    private func cleanupDeduplicationWindow(now: Date) {
        let cutoff = now.addingTimeInterval(-throttleInterval * 2)
        deduplicationWindow = deduplicationWindow.filter { $0.value > cutoff }
    }
}
