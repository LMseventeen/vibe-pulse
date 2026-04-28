//
//  NotchPanel.swift
//  VibePulse
//
//  Transparent overlay panel (reused from Vibe Notch)
//

import AppKit

class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        level = .mainMenu + 3
        allowsToolTipsWhenApplicationIsInactive = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = true
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp ||
           event.type == .rightMouseDown || event.type == .rightMouseUp {
            let locationInWindow = event.locationInWindow
            if let contentView = self.contentView,
               contentView.hitTest(locationInWindow) == nil {
                // Click in transparent area — pass through to the system.
                // Resign key first so we don't intercept the reposted event,
                // then restore key after so buttons keep working.
                let wasKey = isKeyWindow
                if wasKey {
                    resignKey()
                }
                let screenLocation = convertPoint(toScreen: locationInWindow)
                repostMouseEvent(event, at: screenLocation)
                if wasKey {
                    // Defer makeKey so the system has a chance to deliver the
                    // event to the target (e.g. menu bar) before we reclaim focus.
                    DispatchQueue.main.async { [weak self] in
                        self?.makeKey()
                    }
                }
                return
            }
        }
        super.sendEvent(event)
    }

    private func repostMouseEvent(_ event: NSEvent, at screenLocation: NSPoint) {
        // Convert NSScreen coords (bottom-left origin) to CG coords (top-left origin).
        // Use the panel's screen frame, not a global max, so multi-monitor
        // arrangements with different origins are handled correctly.
        let cgPoint = CGPoint(x: screenLocation.x, y: (self.screen?.frame.maxY ?? 0) - screenLocation.y)

        let mouseType: CGEventType
        switch event.type {
        case .leftMouseDown: mouseType = .leftMouseDown
        case .leftMouseUp: mouseType = .leftMouseUp
        case .rightMouseDown: mouseType = .rightMouseDown
        case .rightMouseUp: mouseType = .rightMouseUp
        default: return
        }

        let mouseButton: CGMouseButton = event.type == .rightMouseDown || event.type == .rightMouseUp ? .right : .left

        if let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: cgPoint,
            mouseButton: mouseButton
        ) {
            cgEvent.post(tap: .cghidEventTap)
        }
    }
}
