//
//  EventIcon.swift
//  VibePulse
//
//  SF Symbol icons for each event type with appropriate colors
//

import SwiftUI

struct EventIcon: View {
    let eventType: PulseEventType
    let size: CGFloat

    init(_ type: PulseEventType, size: CGFloat = 16) {
        self.eventType = type
        self.size = size
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size))
            .foregroundColor(iconColor)
    }

    private var iconName: String {
        switch eventType {
        case .testPassed:        return "checkmark.circle.fill"
        case .taskCompleted:     return "checkmark.seal.fill"
        case .claudeAsking:      return "questionmark.bubble.fill"
        case .permissionRequest: return "lock.shield.fill"
        }
    }

    private var iconColor: Color {
        switch eventType {
        case .testPassed:        return PulseColors.success
        case .taskCompleted:     return PulseColors.success
        case .claudeAsking:      return PulseColors.info
        case .permissionRequest: return PulseColors.warning
        }
    }
}
