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

    /// Jump to the terminal for a given session
    static func jumpToTerminal(session: SessionState) async {
        // 1. Try tmux jump
        if session.isInTmux, let pid = session.pid {
            if let target = await TmuxController.shared.findTmuxTarget(forClaudePid: pid) {
                let switched = await TmuxController.shared.switchToPane(target: target)
                if switched {
                    await activateTerminalApp()
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
                    app.activate()
                    logger.info("Activated terminal app for session \(session.sessionId.prefix(8), privacy: .public)")
                    return
                }
            }
        }

        // 3. Fallback: just activate any terminal
        await activateTerminalApp()
        logger.info("Fallback: activated generic terminal for session \(session.sessionId.prefix(8), privacy: .public)")
    }

    @MainActor
    private static func activateTerminalApp() {
        // Try common terminal apps in order of preference
        let terminalBundleIds = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        for bundleId in terminalBundleIds {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                app.activate()
                return
            }
        }
    }
}
