//
//  TerminalFocusHelper.swift
//  VibePulse
//
//  Focuses the terminal window for a given Claude session
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "TerminalFocus")

enum TerminalFocusHelper {

    /// Bundle IDs of known terminal apps
    static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
    ]

    /// Check if a terminal app is currently the frontmost (active) application
    @MainActor
    static func isTerminalFocused() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmost.bundleIdentifier else { return false }
        return terminalBundleIds.contains(bundleId)
    }

    /// Jump to the terminal for a given session
    static func jumpToTerminal(session: SessionState) async {
        // 1. Try tmux jump
        if session.isInTmux, let pid = session.pid {
            if let target = await TmuxController.shared.findTmuxTarget(forClaudePid: pid) {
                let switched = await TmuxController.shared.switchToPane(target: target)
                if switched {
                    // Only activate the terminal app if it's on the same screen.
                    // Activating a full-screen terminal on an external monitor triggers
                    // macOS Space switching, which can freeze mouse input on the built-in display.
                    // The tmux pane switch already happened — the user can see the result
                    // on the external monitor without us stealing focus.
                    if await !isTerminalOnDifferentScreen() {
                        await activateTerminalApp()
                    } else {
                        logger.info("Skipped terminal activation — terminal is on a different screen")
                    }
                    logger.info("Jumped to tmux pane for session \(session.sessionId.prefix(8), privacy: .public)")
                    return
                }
            }
        }

        // 2. Try to activate terminal by PID
        if let pid = session.pid {
            let tree = ProcessTreeBuilder.shared.buildTree()
            if let terminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: pid, tree: tree) {
                let apps = NSWorkspace.shared.runningApplications
                if let app = apps.first(where: { Int($0.processIdentifier) == terminalPid }) {
                    if await !isAppOnDifferentScreen(app) {
                        app.activate()
                    } else {
                        logger.info("Skipped terminal activation — terminal window is on external screen")
                    }
                    logger.info("Activated terminal app for session \(session.sessionId.prefix(8), privacy: .public)")
                    return
                }
            }
        }

        // 3. Fallback: just activate any terminal (only on same screen)
        if await !isTerminalOnDifferentScreen() {
            await activateTerminalApp()
        }
        logger.info("Fallback: activated generic terminal for session \(session.sessionId.prefix(8), privacy: .public)")
    }

    // MARK: - Multi-Monitor Helpers

    /// Check if any running terminal app has its windows exclusively on a different screen
    /// than the built-in display (where the notch lives).
    @MainActor
    private static func isTerminalOnDifferentScreen() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        for bundleId in terminalBundleIds {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                if isAppOnDifferentScreen(app) {
                    return true
                }
            }
        }
        return false
    }

    /// Check if a specific app's visible windows are all on a different screen
    /// than the built-in display.
    @MainActor
    private static func isAppOnDifferentScreen(_ app: NSRunningApplication) -> Bool {
        guard NSScreen.screens.count > 1 else { return false }
        let notchScreen = NSScreen.builtin ?? NSScreen.main
        guard let notchFrame = notchScreen?.frame else { return false }

        let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let appWindows = windowInfoList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
                && ($0[kCGWindowLayer as String] as? Int) == 0  // normal windows only
        }

        guard !appWindows.isEmpty else { return false }

        // If ALL of the app's windows are outside the notch screen, it's on a different screen
        let allOnOtherScreen = appWindows.allSatisfy { info in
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { return false }
            let windowCenter = CGPoint(x: x + w / 2, y: y + h / 2)
            // CGWindowList uses top-left origin; NSScreen uses bottom-left.
            // Convert notchFrame to top-left for comparison.
            let screenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? notchFrame.height
            let notchTopLeft = CGRect(
                x: notchFrame.origin.x,
                y: screenHeight - notchFrame.maxY,
                width: notchFrame.width,
                height: notchFrame.height
            )
            return !notchTopLeft.contains(windowCenter)
        }

        return allOnOtherScreen
    }

    @MainActor
    private static func activateTerminalApp() {
        let runningApps = NSWorkspace.shared.runningApplications
        for bundleId in terminalBundleIds {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                app.activate()
                return
            }
        }
    }
}
