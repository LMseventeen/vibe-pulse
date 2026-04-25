//
//  VibePulseApp.swift
//  VibePulse
//
//  Intelligent notification center for Claude Code CLI
//

import SwiftUI

@main
struct VibePulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
