//
//  BashOutputAnalyzer.swift
//  VibePulse
//
//  Regex-based analysis of Bash tool stdout to extract test pass signals
//  Covers: pytest, Jest, XCTest, Go test, cargo test
//

import Foundation

actor BashOutputAnalyzer {
    static let shared = BashOutputAnalyzer()

    private init() {}

    /// Analyze bash output and return a structured signal (if any match)
    func analyze(stdout: String?, exitCode: Int?, toolName: String?) -> BashSignal? {
        guard let stdout = stdout, !stdout.isEmpty else {
            return nil
        }

        // Check test frameworks (order matters: most specific first)
        if let signal = matchPytest(stdout) { return signal }
        if let signal = matchJest(stdout) { return signal }
        if let signal = matchXCTest(stdout) { return signal }
        if let signal = matchGoTest(stdout) { return signal }
        if let signal = matchCargoTest(stdout) { return signal }

        return nil
    }

    // MARK: - pytest

    private func matchPytest(_ output: String) -> BashSignal? {
        let passPattern = #"(\d+)\s+passed"#
        let failPattern = #"([1-9]\d*)\s+failed"#

        let hasPassed = output.range(of: passPattern, options: .regularExpression) != nil
        let hasFailed = output.range(of: failPattern, options: .regularExpression) != nil

        if hasPassed && !hasFailed {
            let summary = extractLine(matching: #"=+.*passed.*=+"#, from: output)
                ?? extractLine(matching: passPattern, from: output)
                ?? "Tests passed"
            return .testPassed(summary: summary)
        }

        return nil
    }

    // MARK: - Jest

    private func matchJest(_ output: String) -> BashSignal? {
        let jestSummary = #"Tests:\s+(?:(\d+)\s+failed,\s*)?(\d+)\s+passed"#

        guard output.range(of: jestSummary, options: .regularExpression) != nil else {
            return nil
        }

        let failPattern = #"Tests:\s+(\d+)\s+failed"#
        if output.range(of: failPattern, options: .regularExpression) != nil {
            return nil  // Has failures, skip
        }

        let summary = extractLine(matching: #"Tests:.*passed.*"#, from: output) ?? "Tests passed"
        return .testPassed(summary: summary)
    }

    // MARK: - XCTest

    private func matchXCTest(_ output: String) -> BashSignal? {
        let passPattern = #"Test Suite '.*' passed"#
        let failPattern = #"Test Suite '.*' failed"#

        if output.range(of: failPattern, options: .regularExpression) != nil {
            return nil  // Has failures, skip
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
            return nil  // Has failures, skip
        }

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
            return nil  // Has failures, skip
        }

        if output.range(of: passPattern, options: .regularExpression) != nil {
            let summary = extractLine(matching: passPattern, from: output) ?? "Tests passed"
            return .testPassed(summary: summary)
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
