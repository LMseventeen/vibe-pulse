//
//  AppSettings.swift
//  VibePulse
//
//  User preferences
//

import Foundation

enum AppSettings {
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    private enum Keys {
        static let claudeDirectoryName = "claudeDirectoryName"
    }

    /// The Claude config directory name under the user's home folder.
    static var claudeDirectoryName: String {
        get {
            let value = defaults.string(forKey: Keys.claudeDirectoryName) ?? ""
            return value.isEmpty ? ".claude" : value
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Keys.claudeDirectoryName)
        }
    }
}
