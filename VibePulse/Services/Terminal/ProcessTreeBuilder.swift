//
//  ProcessTreeBuilder.swift
//  VibePulse
//
//  Builds and queries process trees (reused from Vibe Notch)
//

import Foundation

struct ProcessInfo: Sendable {
    let pid: Int
    let ppid: Int
    let command: String
    let tty: String?
}

struct ProcessTreeBuilder: Sendable {
    nonisolated static let shared = ProcessTreeBuilder()

    private nonisolated init() {}

    nonisolated func buildTree() -> [Int: ProcessInfo] {
        guard let output = ProcessExecutor.shared.runSyncOrNil("/bin/ps", arguments: ["-eo", "pid,ppid,tty,comm"]) else {
            return [:]
        }

        var tree: [Int: ProcessInfo] = [:]

        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else { continue }

            let tty = parts[2] == "??" ? nil : parts[2]
            let command = parts[3...].joined(separator: " ")

            tree[pid] = ProcessInfo(pid: pid, ppid: ppid, command: command, tty: tty)
        }

        return tree
    }

    nonisolated func isInTmux(pid: Int, tree: [Int: ProcessInfo]) -> Bool {
        var current = pid
        var depth = 0

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }
            if info.command.lowercased().contains("tmux") {
                return true
            }
            current = info.ppid
            depth += 1
        }

        return false
    }

    nonisolated func findTerminalPid(forProcess pid: Int, tree: [Int: ProcessInfo]) -> Int? {
        var current = pid
        var depth = 0

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }
            if TerminalAppRegistry.isTerminal(info.command) {
                return current
            }
            current = info.ppid
            depth += 1
        }

        return nil
    }

    nonisolated func isDescendant(targetPid: Int, ofAncestor ancestorPid: Int, tree: [Int: ProcessInfo]) -> Bool {
        var current = targetPid
        var depth = 0

        while current > 1 && depth < 50 {
            if current == ancestorPid {
                return true
            }
            guard let info = tree[current] else { break }
            current = info.ppid
            depth += 1
        }

        return false
    }
}
