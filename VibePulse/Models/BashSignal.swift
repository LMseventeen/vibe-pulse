//
//  BashSignal.swift
//  VibePulse
//
//  Signals extracted from Bash tool output analysis
//

import Foundation

enum BashSignal: Sendable {
    case testPassed(summary: String)      // e.g. "42 passed, 0 failed"
}
