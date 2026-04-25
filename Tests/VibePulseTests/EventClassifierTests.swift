//
//  EventClassifierTests.swift
//  VibePulseTests
//
//  Tests for EventClassifier: event classification and notification levels
//

import Testing
import Foundation
@testable import VibePulse

@Suite("EventClassifier")
struct EventClassifierTests {

    // MARK: - Helpers

    private func makeHookEvent(
        sessionId: String = "test-session",
        cwd: String = "/tmp/project",
        event: String = "PostToolUse",
        status: String = "running_tool",
        tool: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        notificationType: String? = nil,
        message: String? = nil,
        stdout: String? = nil,
        stderr: String? = nil,
        exitCode: Int? = nil,
        bashCommand: String? = nil,
        toolError: String? = nil,
        stopError: String? = nil
    ) -> HookEvent {
        let json: [String: Any?] = [
            "session_id": sessionId,
            "cwd": cwd,
            "event": event,
            "status": status,
            "tool": tool,
            "notification_type": notificationType,
            "message": message,
            "stdout": stdout,
            "stderr": stderr,
            "exit_code": exitCode,
            "bash_command": bashCommand,
            "tool_error": toolError,
            "stop_error": stopError,
        ]
        let filtered = json.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: filtered)
        return try! JSONDecoder().decode(HookEvent.self, from: data)
    }

    private func makeSession(
        sessionId: String = "test-session",
        projectName: String = "TestProject"
    ) -> SessionState {
        SessionState(
            sessionId: sessionId,
            cwd: "/tmp/project",
            projectName: projectName
        )
    }

    private func makeRawEvent(
        hookEvent: HookEvent,
        bashSignal: BashSignal? = nil,
        timestamp: Date = Date()
    ) -> RawCapturedEvent {
        RawCapturedEvent(hookEvent: hookEvent, bashSignal: bashSignal, timestamp: timestamp)
    }

    // MARK: - Test Passed

    @Test("testPassed from bash signal has silent level")
    func test_testPassed_bashSignal_silentLevel() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(event: "PostToolUse", tool: "Bash")
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook, bashSignal: .testPassed(summary: "42 passed"))

        let result = await classifier.classify(raw, session: session)
        #expect(result != nil)
        #expect(result?.type == .testPassed)
        #expect(result?.level == .silent)
    }

    // MARK: - Task Completed (Stop)

    @Test("Stop event classified as taskCompleted with remind level")
    func test_stop_event_taskCompleted_remindLevel() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(event: "Stop", status: "ended")
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook)

        let result = await classifier.classify(raw, session: session)
        #expect(result != nil)
        #expect(result?.type == .taskCompleted)
        #expect(result?.level == .remind)
    }

    // MARK: - StopFailure

    @Test("StopFailure event classified as taskCompleted with remind level")
    func test_stopFailure_taskCompleted_remindLevel() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(event: "StopFailure", status: "ended", stopError: "API rate limit")
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook)

        let result = await classifier.classify(raw, session: session)
        #expect(result != nil)
        #expect(result?.type == .taskCompleted)
        #expect(result?.level == .remind)
        #expect(result?.summary.contains("API rate limit") == true)
    }

    // MARK: - Claude Asking

    @Test("Notification idle_prompt classified as claudeAsking with remind level")
    func test_notification_idlePrompt_claudeAsking_remindLevel() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(
            event: "Notification",
            status: "waiting_for_input",
            notificationType: "idle_prompt",
            message: "What would you like me to do next?"
        )
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook)

        let result = await classifier.classify(raw, session: session)
        #expect(result != nil)
        #expect(result?.type == .claudeAsking)
        #expect(result?.level == .remind)
    }

    // MARK: - Permission Request

    @Test("PermissionRequest classified as permissionRequest with alert level")
    func test_permissionRequest_alertLevel() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(
            event: "PermissionRequest",
            status: "waiting_for_approval",
            tool: "Bash"
        )
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook)

        let result = await classifier.classify(raw, session: session)
        #expect(result != nil)
        #expect(result?.type == .permissionRequest)
        #expect(result?.level == .alert)
    }

    // MARK: - Unhandled events

    @Test("SessionStart event returns nil")
    func test_sessionStart_returnsNil() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(event: "SessionStart", status: "starting")
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook)

        let result = await classifier.classify(raw, session: session)
        #expect(result == nil)
    }

    @Test("Unknown event type returns nil")
    func test_unknownEvent_returnsNil() async {
        let classifier = EventClassifier.shared
        let hook = makeHookEvent(event: "SomeRandomEvent", status: "unknown")
        let session = makeSession()
        let raw = makeRawEvent(hookEvent: hook)

        let result = await classifier.classify(raw, session: session)
        #expect(result == nil)
    }
}
