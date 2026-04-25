//
//  BashOutputAnalyzerTests.swift
//  VibePulseTests
//
//  Tests for BashOutputAnalyzer: regex-based bash stdout analysis
//

import Testing
@testable import VibePulse

@Suite("BashOutputAnalyzer")
struct BashOutputAnalyzerTests {

    private let analyzer = BashOutputAnalyzer.shared

    // MARK: - pytest

    @Test("pytest passed output returns testPassed")
    func test_pytest_passedOutput_returnsTestPassed() async {
        let output = """
        ============================= test session starts =============================
        collected 42 items

        tests/test_core.py ..........                                       [100%]

        ============================== 42 passed in 3.21s ==============================
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        guard case .testPassed(let summary) = signal else {
            Issue.record("Expected testPassed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("passed"))
    }

    @Test("pytest with failures returns nil")
    func test_pytest_failedOutput_returnsNil() async {
        let output = """
        ============================== 3 failed, 2 passed in 1.50s ==============================
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        #expect(signal == nil)
    }

    // MARK: - Jest

    @Test("Jest passed output returns testPassed")
    func test_jest_passedOutput_returnsTestPassed() async {
        let output = """
        PASS src/__tests__/App.test.js
        Tests:  5 passed, 5 total
        Time:   1.234 s
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        guard case .testPassed(let summary) = signal else {
            Issue.record("Expected testPassed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("passed"))
    }

    @Test("Jest with failures returns nil")
    func test_jest_failedOutput_returnsNil() async {
        let output = """
        Tests:  1 failed, 5 passed, 6 total
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        #expect(signal == nil)
    }

    // MARK: - XCTest

    @Test("XCTest passed output returns testPassed")
    func test_xctest_passedOutput_returnsTestPassed() async {
        let output = """
        Test Suite 'All tests' started at 2024-01-15 10:00:00.
        Test Suite 'MyTests' started at 2024-01-15 10:00:00.
        Test Case '-[MyTests testExample]' passed (0.001 seconds).
        Test Suite 'MyTests' passed at 2024-01-15 10:00:01.
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        guard case .testPassed(let summary) = signal else {
            Issue.record("Expected testPassed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("passed"))
    }

    @Test("XCTest with failures returns nil")
    func test_xctest_failedOutput_returnsNil() async {
        let output = """
        Test Suite 'MyTests' failed at 2024-01-15 10:00:01.
             Executed 1 test, with 1 failure in 0.002 seconds
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        #expect(signal == nil)
    }

    // MARK: - Go test

    @Test("Go test passed output returns testPassed")
    func test_goTest_passedOutput_returnsTestPassed() async {
        let output = """
        === RUN   TestAdd
        --- PASS: TestAdd (0.00s)
        PASS
        ok      mypackage    0.003s
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        guard case .testPassed(let summary) = signal else {
            Issue.record("Expected testPassed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("ok") || summary.contains("passed") || summary.contains("PASS"))
    }

    @Test("Go test with failures returns nil")
    func test_goTest_failedOutput_returnsNil() async {
        let output = """
        --- FAIL: TestAdd (0.00s)
        FAIL    mypackage    0.003s
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        #expect(signal == nil)
    }

    // MARK: - cargo test

    @Test("cargo test passed output returns testPassed")
    func test_cargoTest_passedOutput_returnsTestPassed() async {
        let output = """
        running 3 tests
        test tests::test_add ... ok
        test tests::test_sub ... ok
        test tests::test_mul ... ok

        test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        guard case .testPassed(let summary) = signal else {
            Issue.record("Expected testPassed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("ok") || summary.contains("passed"))
    }

    @Test("cargo test with failures returns nil")
    func test_cargoTest_failedOutput_returnsNil() async {
        let output = """
        test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        #expect(signal == nil)
    }

    // MARK: - Irrelevant output

    @Test("Irrelevant output returns nil")
    func test_irrelevant_normalOutput_returnsNil() async {
        let output = """
        drwxr-xr-x  5 user  staff   160 Jan 15 10:00 src
        -rw-r--r--  1 user  staff  1234 Jan 15 10:00 README.md
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        #expect(signal == nil)
    }

    @Test("Git log output returns nil")
    func test_irrelevant_gitLog_returnsNil() async {
        let output = """
        commit abc123def456
        Author: John Doe <john@example.com>
        Date:   Mon Jan 15 10:00:00 2024

            Initial commit
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        #expect(signal == nil)
    }

    // MARK: - Edge cases

    @Test("Empty string returns nil")
    func test_edge_emptyString_returnsNil() async {
        let signal = await analyzer.analyze(stdout: "", exitCode: 0, toolName: "Bash")
        #expect(signal == nil)
    }

    @Test("Nil stdout returns nil")
    func test_edge_nilStdout_returnsNil() async {
        let signal = await analyzer.analyze(stdout: nil, exitCode: 0, toolName: "Bash")
        #expect(signal == nil)
    }

    @Test("Nil stdout with non-zero exit code returns nil")
    func test_edge_nilStdout_nonZeroExit_returnsNil() async {
        let signal = await analyzer.analyze(stdout: nil, exitCode: 1, toolName: "Bash")
        #expect(signal == nil)
    }

    @Test("Very long output still matches patterns")
    func test_edge_longOutput_stillMatches() async {
        let padding = String(repeating: "Line of irrelevant output\n", count: 500)
        let output = padding + "test result: ok. 10 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n"
        let signal = await analyzer.analyze(stdout: output, exitCode: 0, toolName: "Bash")
        guard case .testPassed = signal else {
            Issue.record("Expected testPassed, got \(String(describing: signal))")
            return
        }
    }
}
