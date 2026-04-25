//
//  TmuxTargetFinder.swift
//  VibePulse
//
//  Finds tmux targets for Claude processes (reused from Vibe Notch)
//

import Foundation

actor TmuxTargetFinder {
    static let shared = TmuxTargetFinder()

    private init() {}

    func findTarget(forClaudePid claudePid: Int) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        guard let output = await runTmuxCommand(tmuxPath: tmuxPath, args: [
            "list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_pid}"
        ]) else {
            return nil
        }

        let tree = ProcessTreeBuilder.shared.buildTree()

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let panePid = Int(parts[1]) else { continue }

            let targetString = String(parts[0])

            if ProcessTreeBuilder.shared.isDescendant(targetPid: claudePid, ofAncestor: panePid, tree: tree) {
                return TmuxTarget(from: targetString)
            }
        }

        return nil
    }

    func isSessionPaneActive(claudePid: Int) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        guard let _ = await findTarget(forClaudePid: claudePid) else {
            return false
        }

        guard let output = await runTmuxCommand(tmuxPath: tmuxPath, args: [
            "display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"
        ]) else {
            return false
        }

        let target = await findTarget(forClaudePid: claudePid)
        let activeTarget = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return target?.targetString == activeTarget
    }

    private func runTmuxCommand(tmuxPath: String, args: [String]) async -> String? {
        do {
            return try await ProcessExecutor.shared.run(tmuxPath, arguments: args)
        } catch {
            return nil
        }
    }
}
