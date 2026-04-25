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
    var onApprove: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil

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

            // Permission action buttons
            if card.event.type == .permissionRequest {
                HStack(spacing: 10) {
                    Button(action: { onApprove?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Allow")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: { onDeny?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Deny")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: onJump) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(PulseColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Regular card: jump button
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PulseColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    card.event.type == .permissionRequest
                        ? Color.orange.opacity(0.4)
                        : PulseColors.cardBorder,
                    lineWidth: card.event.type == .permissionRequest ? 1 : 0.5
                )
        )
        .contentShape(Rectangle())
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
