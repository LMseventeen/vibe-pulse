//
//  PatternRules.swift
//  VibePulse
//
//  Test framework and build tool pattern matching rules
//

import Foundation

/// Collection of regex patterns for different test frameworks
enum PatternRules {

    /// Known test runner command patterns (for identifying test-related bash commands)
    static let testCommandPatterns: [String] = [
        #"pytest"#,
        #"py\.test"#,
        #"jest"#,
        #"vitest"#,
        #"mocha"#,
        #"xctest"#,
        #"swift test"#,
        #"xcodebuild test"#,
        #"go test"#,
        #"cargo test"#,
        #"npm test"#,
        #"yarn test"#,
        #"pnpm test"#,
        #"mix test"#,
        #"rspec"#,
        #"phpunit"#,
        #"gradle test"#,
        #"mvn test"#,
        #"dotnet test"#,
    ]

    /// Known build command patterns
    static let buildCommandPatterns: [String] = [
        #"make\b"#,
        #"cmake\b"#,
        #"cargo build"#,
        #"swift build"#,
        #"xcodebuild\b"#,
        #"gradle build"#,
        #"mvn compile"#,
        #"npm run build"#,
        #"yarn build"#,
        #"tsc\b"#,
        #"gcc\b"#,
        #"g\+\+"#,
        #"clang\b"#,
        #"rustc\b"#,
        #"go build"#,
        #"dotnet build"#,
    ]

    /// Check if a command looks like a test invocation
    static func isTestCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return testCommandPatterns.contains { pattern in
            lower.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Check if a command looks like a build invocation
    static func isBuildCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return buildCommandPatterns.contains { pattern in
            lower.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
