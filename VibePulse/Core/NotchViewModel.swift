//
//  NotchViewModel.swift
//  VibePulse
//
//  UI state management for the notch (simplified from Vibe Notch)
//  Removed: chat/menu/instances logic
//  Added: notification card display, timeline panel
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case card       // Notification card (default when opened)
    case timeline   // History timeline
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .card
    @Published var isHovering: Bool = false

    // MARK: - Pulse State (from PulseStore)

    @Published var pulseState: PulseState = .empty

    // MARK: - Dependencies

    private let screenSelector = ScreenSelector.shared

    // MARK: - Geometry

    let geometry: NotchGeometry
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    var openedSize: CGSize {
        switch contentType {
        case .card:
            return CGSize(
                width: min(screenRect.width * 0.35, 420),
                height: 200
            )
        case .timeline:
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 420
            )
        }
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?
    private var autoCloseTimer: DispatchWorkItem?

    // MARK: - Initialization

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
        observePulseStore()
    }

    private func observePulseStore() {
        Task {
            let publisher = await PulseStore.shared.statePublisher
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.pulseState = state
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)
    }

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inNotch || inOpened

        guard newHovering != isHovering else { return }
        isHovering = newHovering

        hoverTimer?.cancel()
        hoverTimer = nil

        if isHovering && (status == .closed || status == .popping) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            if geometry.isPointOutsidePanel(location, size: openedSize) {
                // Don't auto-close for permission requests — user must interact
                let isPermissionCard = pulseState.currentCard?.event.type == .permissionRequest
                if !isPermissionCard {
                    notchClose()
                }
                repostClickAt(location)
            } else if geometry.notchScreenRect.contains(location) {
                // Toggle between card and timeline
                if contentType == .card {
                    contentType = .timeline
                } else {
                    notchClose()
                }
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    private func repostClickAt(_ location: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        openReason = reason
        status = .opened
        contentType = .card

        // Only try to pull cards when user manually opens (click/hover),
        // NOT when triggered by a notification — the caller already handles card display.
        guard reason == .click || reason == .hover else { return }

        if pulseState.currentCard == nil {
            Task {
                if let next = await PulseStore.shared.dequeueNextCard() {
                    await MainActor.run {
                        self.showNotification(card: next)
                    }
                } else if !self.pulseState.history.isEmpty {
                    // No pending card, but has history — show timeline
                    await MainActor.run {
                        self.contentType = .timeline
                    }
                }
            }
        }
    }

    func notchClose() {
        autoCloseTimer?.cancel()
        autoCloseTimer = nil
        status = .closed
        contentType = .card
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func showTimeline() {
        contentType = .timeline
    }

    func showCard() {
        contentType = .card
    }

    /// Show a notification card, auto-close after duration if specified
    func showNotification(card: NotificationCard) {
        // Always cancel any existing auto-close timer first
        autoCloseTimer?.cancel()
        autoCloseTimer = nil

        if status != .opened {
            notchOpen(reason: .notification)
        }
        contentType = .card

        // Auto-close only for remind-level notifications (not alert/permission)
        if let duration = card.displayDuration {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.openReason == .notification else { return }
                self.notchClose()
            }
            autoCloseTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    /// Perform boot animation
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}
