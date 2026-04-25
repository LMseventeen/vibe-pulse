//
//  AppDelegate.swift
//  VibePulse
//
//  Application lifecycle and window management
//

import AppKit
import SwiftUI

@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?

    nonisolated(unsafe) static var shared: AppDelegate?

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        HookInstaller.installIfNeeded()
        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        // Start the hook socket server and event pipeline
        Task {
            await PulseStore.shared.start()
        }
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenObserver = nil
        HookSocketServer.shared.stop()
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vibepulse.app"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
