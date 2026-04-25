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

    @Test("pytest failed output returns testFailed")
    func test_pytest_failedOutput_returnsTestFailed() async {
        let output = """
        ============================= test session starts =============================
        FAILED tests/test_core.py::test_login - AssertionError

        ============================== 3 failed, 2 passed in 1.50s ==============================
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .testFailed(let summary) = signal else {
            Issue.record("Expected testFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("failed") || summary.contains("FAILED"))
    }

    @Test("pytest ERROR line returns testFailed")
    func test_pytest_errorLine_returnsTestFailed() async {
        let output = """
        ============================= test session starts =============================
        ERROR tests/test_core.py - ModuleNotFoundError
        ============================== 1 error in 0.03s ==============================
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .testFailed = signal else {
            Issue.record("Expected testFailed, got \(String(describing: signal))")
            return
        }
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

    @Test("Jest failed output returns testFailed")
    func test_jest_failedOutput_returnsTestFailed() async {
        let output = """
        FAIL src/__tests__/App.test.js
        Tests:  1 failed, 5 passed, 6 total
        Time:   2.456 s
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .testFailed(let summary) = signal else {
            Issue.record("Expected testFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("failed"))
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

    @Test("XCTest failed output returns testFailed")
    func test_xctest_failedOutput_returnsTestFailed() async {
        let output = """
        Test Suite 'All tests' started at 2024-01-15 10:00:00.
        Test Case '-[MyTests testExample]' failed (0.002 seconds).
        Test Suite 'MyTests' failed at 2024-01-15 10:00:01.
             Executed 1 test, with 1 failure in 0.002 seconds
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .testFailed(let summary) = signal else {
            Issue.record("Expected testFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("failed"))
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

    @Test("Go test failed output returns testFailed")
    func test_goTest_failedOutput_returnsTestFailed() async {
        let output = """
        === RUN   TestAdd
        --- FAIL: TestAdd (0.00s)
            main_test.go:10: expected 4, got 3
        FAIL    mypackage    0.003s
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .testFailed(let summary) = signal else {
            Issue.record("Expected testFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("FAIL"))
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

    @Test("cargo test failed output returns testFailed")
    func test_cargoTest_failedOutput_returnsTestFailed() async {
        let output = """
        running 2 tests
        test tests::test_add ... ok
        test tests::test_sub ... FAILED

        test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .testFailed(let summary) = signal else {
            Issue.record("Expected testFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("FAILED") || summary.contains("failed"))
    }

    // MARK: - Build failures

    @Test("BUILD FAILED keyword returns buildFailed")
    func test_build_buildFailedKeyword_returnsBuildFailed() async {
        let output = """
        Compiling src/main.swift...
        BUILD FAILED
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .buildFailed(let summary) = signal else {
            Issue.record("Expected buildFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("BUILD FAILED"))
    }

    @Test("Compiler error pattern returns buildFailed")
    func test_build_compilerError_returnsBuildFailed() async {
        let output = """
        /Users/dev/main.swift:10:5: error: use of unresolved identifier 'foo'
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .buildFailed(let summary) = signal else {
            Issue.record("Expected buildFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("error:"))
    }

    @Test("fatal error returns buildFailed")
    func test_build_fatalError_returnsBuildFailed() async {
        let output = "fatal error: 'stdio.h' file not found"
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .buildFailed = signal else {
            Issue.record("Expected buildFailed, got \(String(describing: signal))")
            return
        }
    }

    @Test("Rust compiler error returns buildFailed")
    func test_build_rustError_returnsBuildFailed() async {
        let output = """
        error[E0308]: mismatched types
          --> src/main.rs:4:5
        """
        let signal = await analyzer.analyze(stdout: output, exitCode: 1, toolName: "Bash")
        guard case .buildFailed = signal else {
            Issue.record("Expected buildFailed, got \(String(describing: signal))")
            return
        }
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

    @Test("Nil stdout returns nil when exit code 0")
    func test_edge_nilStdout_exitZero_returnsNil() async {
        let signal = await analyzer.analyze(stdout: nil, exitCode: 0, toolName: "Bash")
        #expect(signal == nil)
    }

    @Test("Nil stdout with non-zero exit code returns buildFailed")
    func test_edge_nilStdout_nonZeroExit_returnsBuildFailed() async {
        let signal = await analyzer.analyze(stdout: nil, exitCode: 1, toolName: "Bash")
        guard case .buildFailed(let summary) = signal else {
            Issue.record("Expected buildFailed, got \(String(describing: signal))")
            return
        }
        #expect(summary.contains("code 1"))
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
