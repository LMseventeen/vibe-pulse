//
//  TerminalAppRegistry.swift
//  VibePulse
//
//  Registry of known terminal applications (reused from Vibe Notch)
//

import Foundation

struct TerminalAppRegistry: Sendable {
    static let appNames: Set<String> = [
        "Terminal", "iTerm2", "iTerm", "Ghostty", "Alacritty", "kitty",
        "Hyper", "Warp", "WezTerm", "Tabby", "Rio", "Contour",
        "Code", "Code - Insiders", "Cursor", "Windsurf", "zed"
    ]

    static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "io.alacritty", "net.kovidgoyal.kitty", "co.zeit.hyper",
        "dev.warp.Warp-Stable", "com.github.wez.wezterm",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        "dev.zed.Zed"
    ]

    static func isTerminal(_ appNameOrCommand: String) -> Bool {
        let lower = appNameOrCommand.lowercased()
        for name in appNames {
            if lower.contains(name.lowercased()) {
                return true
            }
        }
        return lower.contains("terminal") || lower.contains("iterm")
    }

    static func isTerminalBundle(_ bundleId: String) -> Bool {
        bundleIdentifiers.contains(bundleId)
    }
}
