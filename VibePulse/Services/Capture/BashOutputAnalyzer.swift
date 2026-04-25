//
//  BashOutputAnalyzer.swift
//  VibePulse
//
//  Regex-based analysis of Bash tool stdout to extract test/build signals
//  Covers: pytest, Jest, XCTest, Go test, cargo test, and generic build errors
//

import Foundation

actor BashOutputAnalyzer {
    static let shared = BashOutputAnalyzer()

    private init() {}

    /// Analyze bash output and return a structured signal (if any match)
    func analyze(stdout: String?, exitCode: Int?, toolName: String?) -> BashSignal? {
        guard let stdout = stdout, !stdout.isEmpty else {
            // Only exit code available
            if let code = exitCode, code != 0 {
                return .buildFailed(summary: "Process exited with code \(code)")
            }
            return nil
        }

        // Check test frameworks first (order matters: most specific first)
        if let signal = matchPytest(stdout) { return signal }
        if let signal = matchJest(stdout) { return signal }
        if let signal = matchXCTest(stdout) { return signal }
        if let signal = matchGoTest(stdout) { return signal }
        if let signal = matchCargoTest(stdout) { return signal }
        if let signal = matchGenericBuild(stdout, exitCode: exitCode) { return signal }

        return nil
    }

    // MARK: - pytest

    private func matchPytest(_ output: String) -> BashSignal? {
        // pytest summary: "5 passed", "3 failed, 2 passed", "FAILED", "ERROR"
        let passPattern = #"(\d+)\s+passed"#
        let failPattern = #"([1-9]\d*)\s+failed"#
        let errorPattern = #"(?:^|\n)\s*(?:FAILED|ERROR)\s"#

        let hasPassed = output.range(of: passPattern, options: .regularExpression) != nil
        let failMatch = output.range(of: failPattern, options: .regularExpression)
        let hasError = output.range(of: errorPattern, options: .regularExpression) != nil

        if failMatch != nil || hasError {
            let summary = extractLine(matching: #"=+.*(?:FAILED|ERROR|failed).*=+"#, from: output)
                ?? extractLine(matching: failPattern, from: output)
                ?? "Tests failed"
            return .testFailed(summary: summary)
        }

        if hasPassed {
            let summary = extractLine(matching: #"=+.*passed.*=+"#, from: output)
                ?? extractLine(matching: passPattern, from: output)
                ?? "Tests passed"
            return .testPassed(summary: summary)
        }

        return nil
    }

    // MARK: - Jest

    private func matchJest(_ output: String) -> BashSignal? {
        // Jest summary: "Tests:  1 failed, 5 passed, 6 total"
        let jestSummary = #"Tests:\s+(?:(\d+)\s+failed,\s*)?(\d+)\s+passed"#

        guard output.range(of: jestSummary, options: .regularExpression) != nil else {
            return nil
        }

        let failPattern = #"Tests:\s+(\d+)\s+failed"#
        if output.range(of: failPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: #"Tests:.*failed.*"#, from: output) ?? "Tests failed"
            return .testFailed(summary: summary)
        }

        let summary = extractLine(matching: #"Tests:.*passed.*"#, from: output) ?? "Tests passed"
        return .testPassed(summary: summary)
    }

    // MARK: - XCTest

    private func matchXCTest(_ output: String) -> BashSignal? {
        let passPattern = #"Test Suite '.*' passed"#
        let failPattern = #"Test Suite '.*' failed"#

        if output.range(of: failPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: failPattern, from: output) ?? "Tests failed"
            return .testFailed(summary: summary)
        }

        if output.range(of: passPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: passPattern, from: output) ?? "Tests passed"
            return .testPassed(summary: summary)
        }

        return nil
    }

    // MARK: - Go test

    private func matchGoTest(_ output: String) -> BashSignal? {
        let passPattern = #"(?m)^ok\s+\S+"#
        let failPattern = #"(?m)^FAIL\s+\S+"#

        if output.range(of: failPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: failPattern, from: output) ?? "Tests failed"
            return .testFailed(summary: summary)
        }

        // "PASS" at end of output or "ok" lines
        if output.range(of: passPattern, options: .regularExpression) != nil
            || output.contains("PASS") {
            let summary = extractLine(matching: passPattern, from: output) ?? "Tests passed"
            return .testPassed(summary: summary)
        }

        return nil
    }

    // MARK: - cargo test

    private func matchCargoTest(_ output: String) -> BashSignal? {
        let passPattern = #"test result: ok\."#
        let failPattern = #"test result: FAILED\."#

        if output.range(of: failPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: failPattern, from: output) ?? "Tests failed"
            return .testFailed(summary: summary)
        }

        if output.range(of: passPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: passPattern, from: output) ?? "Tests passed"
            return .testPassed(summary: summary)
        }

        return nil
    }

    // MARK: - Generic build errors

    private func matchGenericBuild(_ output: String, exitCode: Int?) -> BashSignal? {
        let buildFailPatterns = [
            #"(?i)BUILD FAILED"#,
            #"(?i)compilation error"#,
            #"(?i)fatal error:"#,
            #"error\[E\d+\]:"#,  // Rust compiler errors
        ]

        for pattern in buildFailPatterns {
            if output.range(of: pattern, options: .regularExpression) != nil {
                let summary = extractLine(matching: pattern, from: output) ?? "Build failed"
                return .buildFailed(summary: summary)
            }
        }

        // Swift/Clang specific: "error:" at line start (common compiler pattern)
        let compilerErrorPattern = #"^\S+:\d+:\d+: error:"#
        if output.range(of: compilerErrorPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: compilerErrorPattern, from: output) ?? "Compilation error"
            return .buildFailed(summary: summary)
        }

        return nil
    }

    // MARK: - Helpers

    private func extractLine(matching pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        let line = String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.count > 120 ? String(line.prefix(120)) + "..." : line
    }
}
