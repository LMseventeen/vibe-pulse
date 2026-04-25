//
//  EventCaptureService.swift
//  VibePulse
//
//  Aggregates Hook events and Bash analysis into a unified event stream
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.vibepulse", category: "Capture")

/// Raw event from Hook + optional Bash analysis
struct RawCapturedEvent: Sendable {
    let hookEvent: HookEvent
    let bashSignal: BashSignal?
    let timestamp: Date
}

/// Event capture aggregator -- bridges HookSocketServer and BashOutputAnalyzer
actor EventCaptureService {
    static let shared = EventCaptureService()

    private let bashAnalyzer = BashOutputAnalyzer.shared
    private var continuation: AsyncStream<RawCapturedEvent>.Continuation?

    /// Unified raw event stream for downstream processing
    lazy var eventStream: AsyncStream<RawCapturedEvent> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    private init() {}

    /// Start listening for hook events
    func start() {
        HookSocketServer.shared.start { [weak self] hookEvent in
            guard let self = self else { return }
            Task {
                await self.handleHookEvent(hookEvent)
            }
        }
    }

    /// Process a hook event, optionally analyzing bash output
    private func handleHookEvent(_ hookEvent: HookEvent) async {
        var bashSignal: BashSignal? = nil

        // For PostToolUse/PostToolUseFailure with bash output, analyze it
        let isBashEvent = hookEvent.event == "PostToolUse" || hookEvent.event == "PostToolUseFailure"
        let isBashTool = hookEvent.tool.map { ["Bash", "bash", "execute_command"].contains($0) } ?? false

        if isBashEvent && isBashTool {
            bashSignal = await bashAnalyzer.analyze(
                stdout: hookEvent.stdout,
                exitCode: hookEvent.exitCode,
                toolName: hookEvent.tool
            )
        }

        let rawEvent = RawCapturedEvent(
            hookEvent: hookEvent,
            bashSignal: bashSignal,
            timestamp: Date()
        )

        logger.debug("Captured event: \(hookEvent.event, privacy: .public) bash=\(bashSignal != nil ? "yes" : "no", privacy: .public)")

        continuation?.yield(rawEvent)
    }

    func stop() {
        continuation?.finish()
        HookSocketServer.shared.stop()
    }
}
