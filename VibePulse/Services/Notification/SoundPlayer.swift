//
//  SoundPlayer.swift
//  VibePulse
//
//  Notification sound playback using system sounds
//

import AppKit

enum SoundPlayer {
    /// Play notification sound based on notification level
    @MainActor
    static func play(for level: NotificationLevel) {
        switch level {
        case .silent:
            break
        case .remind:
            NSSound(named: "Tink")?.play()
        case .alert:
            NSSound(named: "Sosumi")?.play()
        }
    }
}
