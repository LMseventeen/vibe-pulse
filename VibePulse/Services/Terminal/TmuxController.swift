//
//  TmuxController.swift
//  VibePulse
//
//  High-level tmux operations (reused from Vibe Notch, simplified)
//

import Foundation

actor TmuxController {
    static let shared = TmuxController()

    private init() {}

    func findTmuxTarget(forClaudePid pid: Int) async -> TmuxTarget? {
        await TmuxTargetFinder.shared.findTarget(forClaudePid: pid)
    }

    func switchToPane(target: TmuxTarget) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        do {
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "select-window", "-t", "\(target.session):\(target.window)"
            ])
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "select-pane", "-t", target.targetString
            ])
            return true
        } catch {
            return false
        }
    }
}
