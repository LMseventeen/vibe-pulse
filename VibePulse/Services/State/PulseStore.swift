//
//  PulseStore.swift
//  VibePulse
//
//  Central actor state manager -- coordinates capture, classification,
//  notification queue, and UI state publishing
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "PulseStore")

actor PulseStore {
    static let shared = PulseStore()

    // MARK: - Session State

    private var sessions: [String: SessionState] = [:]

    // MARK: - Notification State

    private var notificationHistory: [NotificationRecord] = []
    private let maxHistory = 100

    // MARK: - Dependencies

    private let capture = EventCaptureService.shared
    private let classifier = EventClassifier.shared
    private let notificationQueue = NotificationQueue.shared

    // MARK: - Publishing

    nonisolated(unsafe) private let stateSubject = CurrentValueSubject<PulseState, Never>(.empty)
    nonisolated var statePublisher: AnyPublisher<PulseState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// Current card being displayed
    private var currentCard: NotificationCard?

    /// Task for processing the event stream
    private var processingTask: Task<Void, Never>?

    /// Task for cycling through queued notifications
    private var displayTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func start() async {
        await capture.start()

        // Start consuming the event stream
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await self.capture.eventStream
            for await rawEvent in stream {
                await self.processRawEvent(rawEvent)
            }
        }

        // Start the notification display loop
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.cycleNotificationDisplay()
            }
        }

        logger.info("PulseStore started")
    }

    func stop() {
        processingTask?.cancel()
        displayTask?.cancel()
        Task {
            await capture.stop()
        }
    }

    // MARK: - Event Processing

    private func processRawEvent(_ raw: RawCapturedEvent) async {
        let hookEvent = raw.hookEvent

        // Update or create session
        let session = ensureSession(for: hookEvent)

        // Update session phase
        updateSessionPhase(hookEvent: hookEvent)

        // Handle session lifecycle events
        switch hookEvent.event {
        case "SessionEnd":
            sessions.removeValue(forKey: hookEvent.sessionId)
            publishState()
            return
        case "SessionStart":
            publishState()
            return
        default:
            break
        }

        // Classify the event
        guard let pulseEvent = await classifier.classify(raw, session: session) else {
            publishState()
            return
        }

        // Record to history
        let record = NotificationRecord(from: pulseEvent)
        notificationHistory.insert(record, at: 0)
        if notificationHistory.count > maxHistory {
            notificationHistory = Array(notificationHistory.prefix(maxHistory))
        }

        // Skip notification display when user is in the terminal
        let terminalFocused = await MainActor.run { TerminalFocusHelper.isTerminalFocused() }
        if terminalFocused {
            logger.debug("Terminal focused — suppressing notification for \(pulseEvent.type.rawValue, privacy: .public)")
            publishState()
            return
        }

        // Enqueue for display (if not silent)
        let card = await notificationQueue.enqueue(pulseEvent)

        if let card = card {
            logger.info("New notification: \(pulseEvent.type.rawValue, privacy: .public) level=\(pulseEvent.level.rawValue)")

            // Play sound
            if pulseEvent.level >= .remind {
                let level = pulseEvent.level
                await MainActor.run {
                    SoundPlayer.play(for: level)
                }
            }

            // If no card currently showing, display immediately
            if currentCard == nil {
                currentCard = card
                await notificationQueue.remove(id: card.id)

                // Expand the notch to show the card
                let cardToShow = card
                await MainActor.run {
                    AppDelegate.shared?.windowController?.viewModel.showNotification(card: cardToShow)
                }
            }
        }

        publishState()
    }

    // MARK: - Notification Display Cycle

    private func cycleNotificationDisplay() async {
        guard let current = currentCard else {
            // Try to show next queued card
            if let next = await notificationQueue.dequeue() {
                currentCard = next
                publishState()

                // Notify the view model
                let card = next
                await MainActor.run {
                    AppDelegate.shared?.windowController?.viewModel.showNotification(card: card)
                }
            }
            return
        }

        // Only auto-expire cards that have an explicit display duration.
        // Alert-level cards (displayDuration == nil) stay until user dismisses.
        guard let duration = current.displayDuration else { return }

        let elapsed = Date().timeIntervalSince(current.event.timestamp)
        if elapsed > duration {
            currentCard = nil
            publishState()

            // Close the notch on the main thread
            await MainActor.run {
                AppDelegate.shared?.windowController?.viewModel.notchClose()
            }
        }
    }

    // MARK: - Session Management

    private func ensureSession(for hookEvent: HookEvent) -> SessionState {
        if let existing = sessions[hookEvent.sessionId] {
            var updated = existing
            updated.lastActivity = Date()
            if let pid = hookEvent.pid { updated.pid = pid }
            if let tty = hookEvent.tty { updated.tty = tty }
            sessions[hookEvent.sessionId] = updated
            return updated
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        let isInTmux = hookEvent.pid.map { ProcessTreeBuilder.shared.isInTmux(pid: $0, tree: tree) } ?? false

        let session = SessionState(
            sessionId: hookEvent.sessionId,
            cwd: hookEvent.cwd,
            pid: hookEvent.pid,
            tty: hookEvent.tty,
            isInTmux: isInTmux,
            phase: hookEvent.sessionPhase
        )
        sessions[hookEvent.sessionId] = session
        return session
    }

    private func updateSessionPhase(hookEvent: HookEvent) {
        guard var session = sessions[hookEvent.sessionId] else { return }
        let newPhase = hookEvent.sessionPhase
        if session.phase.canTransition(to: newPhase) {
            session.phase = newPhase
            session.lastActivity = Date()
            sessions[hookEvent.sessionId] = session
        }
    }

    // MARK: - Public API

    func dismissCurrentCard() {
        currentCard = nil
        // Try to show next queued card
        Task {
            await cycleNotificationDisplay()
        }
        publishState()
    }

    func dequeueNextCard() async -> NotificationCard? {
        if currentCard != nil { return currentCard }
        if let next = await notificationQueue.dequeue() {
            currentCard = next
            publishState()
            return next
        }
        return nil
    }

    func acknowledgeRecord(id: UUID) {
        if let idx = notificationHistory.firstIndex(where: { $0.id == id }) {
            notificationHistory[idx].acknowledged = true
        }
        publishState()
    }

    func clearHistory() {
        notificationHistory.removeAll()
        publishState()
    }

    func getSession(id: String) -> SessionState? {
        sessions[id]
    }

    // MARK: - State Publishing

    private func publishState() {
        let activeSessions = Array(sessions.values).sorted { $0.lastActivity > $1.lastActivity }
        let status = computeAggregateStatus(sessions: activeSessions)
        let pendingCount = notificationHistory.filter { !$0.acknowledged }.count

        let state = PulseState(
            sessions: activeSessions,
            currentCard: currentCard,
            pendingCount: pendingCount,
            history: Array(notificationHistory.prefix(50)),
            aggregateStatus: status
        )

        stateSubject.send(state)
    }

    private func computeAggregateStatus(sessions: [SessionState]) -> AggregateStatus {
        // Current card takes priority for status dot color
        if let card = currentCard {
            if card.event.type == .permissionRequest {
                return .waiting   // orange
            }
        }

        guard !sessions.isEmpty else { return .inactive }

        // Check session phases
        let hasWaitingForApproval = sessions.contains { $0.phase.isWaitingForApproval }
        if hasWaitingForApproval { return .waiting }

        let hasProcessing = sessions.contains { $0.phase.isActive }
        if hasProcessing { return .processing }

        let hasWaitingForInput = sessions.contains { $0.phase == .waitingForInput }
        if hasWaitingForInput { return .idle }

        return .inactive
    }
}
