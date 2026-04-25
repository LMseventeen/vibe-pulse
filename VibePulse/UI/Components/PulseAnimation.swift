//
//  PulseAnimation.swift
//  VibePulse
//
//  Pulsing circle animation for the status indicator
//

import SwiftUI

struct PulseAnimation: View {
    let color: Color
    let isAnimating: Bool

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .fill(color.opacity(opacity))
            .scaleEffect(scale)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.6
                    opacity = 0.0
                }
            }
            .onChange(of: isAnimating) { _, animating in
                if animating {
                    withAnimation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                    ) {
                        scale = 1.6
                        opacity = 0.0
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scale = 1.0
                        opacity = 0.6
                    }
                }
            }
    }
}
