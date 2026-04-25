//
//  PulseColors.swift
//  VibePulse
//
//  Color constants for the notification system
//

import SwiftUI

enum PulseColors {
    // Status colors
    static let success = Color.green
    static let error = Color.red
    static let warning = Color.orange
    static let info = Color.blue
    static let inactive = Color.gray

    // Status indicator dot colors
    static let processing = Color.blue
    static let idle = Color.green
    static let waiting = Color.orange
    static let alert = Color.red

    // UI chrome
    static let cardBackground = Color.white.opacity(0.08)
    static let cardBorder = Color.white.opacity(0.12)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.35)
    static let separator = Color.white.opacity(0.1)
}
