//
//  WindowManager.swift
//  VibePulse
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "Window")

class WindowManager {
    private(set) var windowController: NotchWindowController?
    private var isInitialLaunch = true
    private var currentScreenFrame: NSRect?

    @MainActor func setupNotchWindow() -> NotchWindowController? {
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        if let existingController = windowController,
           let existingFrame = currentScreenFrame,
           existingFrame == screen.frame {
            return existingController
        }

        let shouldAnimate = isInitialLaunch
        isInitialLaunch = false

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        currentScreenFrame = screen.frame
        windowController = NotchWindowController(screen: screen, animateOnLaunch: shouldAnimate)
        windowController?.showWindow(nil)

        return windowController
    }
}
