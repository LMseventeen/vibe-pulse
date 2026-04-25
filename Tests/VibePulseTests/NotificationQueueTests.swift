//
//  NotificationQueueTests.swift
//  VibePulseTests
//
//  Tests for NotificationQueue: dedup, throttle, priority, limits
//

import Testing
import Foundation
@testable import VibePulse

@Suite("NotificationQueue")
struct NotificationQueueTests {

    // MARK: - Helpers

    /// Each test gets its own fresh queue to avoid shared-state interference
    private func freshQueue() -> VibePulse.NotificationQueue {
        VibePulse.NotificationQueue()
    }

    private func makeEvent(
        type: PulseEventType = .permissionRequest,
        sessionId: String = "session-1",
        summary: String = "Permission: Bash",
        level: NotificationLevel = .alert,
        timestamp: Date = Date()
    ) -> PulseEvent {
        PulseEvent(
            type: type,
            sessionId: sessionId,
            projectName: "TestProject",
            summary: summary,
            level: level,
            timestamp: timestamp
        )
    }

    // MARK: - Basic enqueue / dequeue

    @Test("Enqueue and dequeue a single event")
    func test_enqueueDequeue_singleEvent() async {
        let queue = freshQueue()

        let event = makeEvent(level: .alert)
        let card = await queue.enqueue(event)
        #expect(card != nil)

        let count = await queue.pendingCount
        #expect(count == 1)

        let dequeued = await queue.dequeue()
        #expect(dequeued != nil)
        #expect(dequeued?.event.type == .permissionRequest)

        let afterCount = await queue.pendingCount
        #expect(afterCount == 0)
    }

    // MARK: - Silent events are not enqueued

    @Test("Silent events are not enqueued")
    func test_enqueue_silentEvent_returnsNil() async {
        let queue = freshQueue()

        let event = makeEvent(type: .testPassed, level: .silent)
        let card = await queue.enqueue(event)
        #expect(card == nil)

        let count = await queue.pendingCount
        #expect(count == 0)
    }

    // MARK: - Deduplication

    @Test("Same fingerprint within 5s is merged, not enqueued twice")
    func test_dedup_sameFingerprint_merged() async {
        let queue = freshQueue()

        let event1 = makeEvent(summary: "3 tests failed", level: .alert)
        let card1 = await queue.enqueue(event1)
        #expect(card1 != nil)

        // Same fingerprint (same sessionId + type + summary prefix)
        let event2 = makeEvent(summary: "3 tests failed", level: .alert)
        let card2 = await queue.enqueue(event2)
        // Should be merged, returns nil
        #expect(card2 == nil)

        let count = await queue.pendingCount
        #expect(count == 1)
    }

    @Test("Different fingerprints are enqueued separately")
    func test_dedup_differentFingerprint_bothEnqueued() async {
        let queue = freshQueue()

        let event1 = makeEvent(summary: "3 tests failed", level: .alert)
        let event2 = makeEvent(type: .claudeAsking, summary: "What should I do next?", level: .remind)

        _ = await queue.enqueue(event1)
        _ = await queue.enqueue(event2)

        let count = await queue.pendingCount
        #expect(count == 2)
    }

    // MARK: - Priority ordering

    @Test("Alert events are dequeued before remind events")
    func test_priority_alertBeforeRemind() async {
        let queue = freshQueue()

        let now = Date()
        // Enqueue remind first
        let remindEvent = makeEvent(
            type: .taskCompleted,
            sessionId: "s-remind",
            summary: "Task done",
            level: .remind,
            timestamp: now
        )
        _ = await queue.enqueue(remindEvent)

        // Enqueue alert second
        let alertEvent = makeEvent(
            type: .permissionRequest,
            sessionId: "s-alert",
            summary: "Permission: Bash",
            level: .alert,
            timestamp: now.addingTimeInterval(1)
        )
        _ = await queue.enqueue(alertEvent)

        // Alert should come first despite being enqueued second
        let first = await queue.dequeue()
        #expect(first?.event.level == .alert)

        let second = await queue.dequeue()
        #expect(second?.event.level == .remind)
    }

    // MARK: - Queue capacity

    @Test("Queue trims to maxQueueSize (20)")
    func test_capacity_trimsToMax() async {
        let queue = freshQueue()

        // Enqueue 25 unique events
        for i in 0..<25 {
            let event = makeEvent(
                sessionId: "cap-session-\(i)",
                summary: "Failure \(i)",
                level: .alert,
                timestamp: Date().addingTimeInterval(Double(i))
            )
            _ = await queue.enqueue(event)
        }

        let count = await queue.pendingCount
        #expect(count <= 20)
    }

    // MARK: - Remove by ID

    @Test("Remove specific card by ID")
    func test_remove_byId() async {
        let queue = freshQueue()

        let event = makeEvent(level: .alert)
        let card = await queue.enqueue(event)
        #expect(card != nil)

        await queue.remove(id: card!.id)
        let count = await queue.pendingCount
        #expect(count == 0)
    }

    // MARK: - Clear

    @Test("Clear removes all pending notifications")
    func test_clear_removesAll() async {
        let queue = freshQueue()

        for i in 0..<5 {
            let event = makeEvent(
                sessionId: "clear-\(i)",
                summary: "Event \(i)",
                level: .remind,
                timestamp: Date().addingTimeInterval(Double(i))
            )
            _ = await queue.enqueue(event)
        }

        await queue.clear()
        let count = await queue.pendingCount
        #expect(count == 0)
    }

    // MARK: - Peek

    @Test("Peek returns first card without removing it")
    func test_peek_doesNotRemove() async {
        let queue = freshQueue()

        let event = makeEvent(level: .alert)
        _ = await queue.enqueue(event)

        let peeked = await queue.peek()
        #expect(peeked != nil)

        let count = await queue.pendingCount
        #expect(count == 1)
    }

    // MARK: - Empty queue

    @Test("Dequeue from empty queue returns nil")
    func test_dequeue_emptyQueue_returnsNil() async {
        let queue = freshQueue()

        let card = await queue.dequeue()
        #expect(card == nil)
    }
}
