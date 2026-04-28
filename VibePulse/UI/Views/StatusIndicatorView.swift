//
//  StatusIndicatorView.swift
//  VibePulse
//
//  Small colored dot showing aggregate session status (F6)
//

import SwiftUI

struct StatusIndicatorView: View {
    let status: AggregateStatus
    let size: CGFloat

    init(status: AggregateStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    var body: some View {
        ZStack {
            // Pulse animation ring for active states
            if shouldAnimate {
                PulseAnimation(color: dotColor, isAnimating: true)
                    .frame(width: size * 2.5, height: size * 2.5)
                    .tag(status)  // Force recreation when status changes so color updates
            }

            // Solid dot
            Circle()
                .fill(dotColor)
                .frame(width: size, height: size)
        }
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    private var dotColor: Color {
        switch status {
        case .inactive:   return PulseColors.inactive
        case .processing: return PulseColors.processing
        case .idle:       return PulseColors.idle
        case .waiting:    return PulseColors.waiting
        }
    }

    private var shouldAnimate: Bool {
        switch status {
        case .processing, .waiting: return true
        case .inactive, .idle: return false
        }
    }
}
