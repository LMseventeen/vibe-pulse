//
//  ClaudePaths.swift
//  VibePulse
//
//  Single source of truth for Claude config directory paths (adapted from Vibe Notch)
//

import Foundation

enum ClaudePaths {

    nonisolated(unsafe) private static var _cachedDir: URL?
    private static let cacheLock = NSLock()

    static var claudeDir: URL {
        cacheLock.lock()
        if let cached = _cachedDir {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let resolved = resolveClaudeDir()

        cacheLock.lock()
        if let existing = _cachedDir {
            cacheLock.unlock()
            return existing
        }
        _cachedDir = resolved
        cacheLock.unlock()
        return resolved
    }

    static var hooksDir: URL {
        claudeDir.appendingPathComponent("hooks")
    }

    static var settingsFile: URL {
        claudeDir.appendingPathComponent("settings.json")
    }

    static var projectsDir: URL {
        claudeDir.appendingPathComponent("projects")
    }

    /// Shell-safe absolute path for the hook script
    static var hookScriptShellPath: String {
        shellQuote(claudeDir.appendingPathComponent("hooks/claude-pulse-hook.py").path)
    }

    static func invalidateCache() {
        cacheLock.lock()
        _cachedDir = nil
        cacheLock.unlock()
    }

    private static func resolveClaudeDir() -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. CLAUDE_CONFIG_DIR env var
        if let envDir = Foundation.ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let expanded = (envDir as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        // 2. User override
        let settingsValue = AppSettings.claudeDirectoryName
        if !settingsValue.isEmpty && settingsValue != ".claude" {
            if settingsValue.hasPrefix("/") {
                return URL(fileURLWithPath: settingsValue)
            } else {
                return home.appendingPathComponent(settingsValue)
            }
        }

        // 3. New default ~/.config/claude/
        let newDefault = home.appendingPathComponent(".config/claude")
        if fm.fileExists(atPath: newDefault.appendingPathComponent("projects").path) {
            return newDefault
        }

        // 4. Legacy fallback
        return home.appendingPathComponent(".claude")
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
