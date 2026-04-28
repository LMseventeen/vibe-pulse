//
//  NotificationCardView.swift
//  VibePulse
//
//  Notification card displayed in the notch area (F3)
//

import SwiftUI

struct NotificationCardView: View {
    let card: NotificationCard
    let onJump: () -> Void
    let onDismiss: () -> Void
    var onAllow: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil

    private var isPermission: Bool {
        card.event.type == .permissionRequest
    }

    var body: some View {
        VStack(spacing: 8) {
            // Main card content
            HStack(spacing: 10) {
                // Event icon
                EventIcon(card.event.type, size: 20)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(card.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PulseColors.textPrimary)

                        Spacer()

                        Text(relativeTime(card.event.timestamp))
                            .font(.system(size: 10))
                            .foregroundColor(PulseColors.textTertiary)
                    }

                    Text(displaySummary)
                        .font(.system(size: 11))
                        .foregroundColor(PulseColors.textSecondary)
                        .lineLimit(2)
                }
            }

            // Actions
            if isPermission {
                permissionActions
            } else {
                jumpAction
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PulseColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Action Views

    @ViewBuilder
    private var jumpAction: some View {
        HStack {
            Spacer()
            Button(action: onJump) {
                HStack(spacing: 4) {
                    Text("Go to Terminal")
                        .font(.system(size: 10))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12))
                }
                .foregroundColor(card.iconColor.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var permissionActions: some View {
        HStack(spacing: 8) {
            // Deny
            Button(action: { onDeny?() }) {
                Text("Deny")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Allow
            Button(action: { onAllow?() }) {
                Text("Allow")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.7))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Go to Terminal
            Button(action: onJump) {
                HStack(spacing: 4) {
                    Text("Go to Terminal")
                        .font(.system(size: 10))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12))
                }
                .foregroundColor(card.iconColor.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    private var borderColor: Color {
        PulseColors.cardBorder
    }

    private var borderWidth: CGFloat {
        0.5
    }

    private var displaySummary: String {
        var summary = card.event.summary
        if card.event.mergeCount > 1 {
            summary += " (x\(card.event.mergeCount))"
        }
        if !card.event.projectName.isEmpty {
            summary += " — \(card.event.projectName)"
        }
        return summary
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
