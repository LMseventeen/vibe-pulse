//
//  TimelineView.swift
//  VibePulse
//
//  Notification history timeline (F5)
//

import SwiftUI

struct PulseTimelineView: View {
    let history: [NotificationRecord]
    let onSelect: (NotificationRecord) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Timeline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PulseColors.textPrimary)

                Spacer()

                if !history.isEmpty {
                    Button(action: onClear) {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundColor(PulseColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(PulseColors.separator)

            // Timeline list
            if history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .font(.system(size: 24))
                        .foregroundColor(PulseColors.textTertiary)
                    Text("No notifications yet")
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(history) { record in
                            TimelineRowView(record: record)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(record)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct TimelineRowView: View {
    let record: NotificationRecord

    var body: some View {
        HStack(spacing: 8) {
            // Time
            Text(formattedTime(record.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(PulseColors.textTertiary)
                .frame(width: 42, alignment: .trailing)

            // Event icon
            EventIcon(record.eventType, size: 12)

            // Summary
            VStack(alignment: .leading, spacing: 1) {
                Text(record.summary)
                    .font(.system(size: 11))
                    .foregroundColor(record.acknowledged ? PulseColors.textTertiary : PulseColors.textPrimary)
                    .lineLimit(1)

                Text(record.projectName)
                    .font(.system(size: 10))
                    .foregroundColor(PulseColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Level indicator
            if record.level == .alert && !record.acknowledged {
                Circle()
                    .fill(PulseColors.alert)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(record.acknowledged ? Color.clear : PulseColors.cardBackground.opacity(0.3))
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
