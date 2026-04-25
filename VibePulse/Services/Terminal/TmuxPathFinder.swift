//
//  TmuxPathFinder.swift
//  VibePulse
//
//  Finds tmux executable path (reused from Vibe Notch)
//

import Foundation

actor TmuxPathFinder {
    static let shared = TmuxPathFinder()

    private var cachedPath: String?

    private init() {}

    func getTmuxPath() -> String? {
        if let cached = cachedPath {
            return cached
        }

        let possiblePaths = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
            "/bin/tmux"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedPath = path
                return path
            }
        }

        return nil
    }
}
