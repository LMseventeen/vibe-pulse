//
//  NotchView.swift
//  VibePulse
//
//  Main notch view (simplified from Vibe Notch)
//  Removed: chat/instances/menu views
//  Added: notification card, timeline, status indicator
//

import AppKit
import SwiftUI

private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.deviceNotchRect.width,
            height: viewModel.deviceNotchRect.height
        )
    }

    private var hasActivity: Bool {
        viewModel.pulseState.aggregateStatus != .inactive
    }

    private var expansionWidth: CGFloat {
        // Expand closed notch when there are active sessions
        if hasActivity {
            return 2 * max(0, closedNotchSize.height - 12) + 20
        }
        return 0
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize)
                    .animation(.smooth, value: hasActivity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
        }
        .onChange(of: viewModel.status) { _, newStatus in
            handleStatusChange(newStatus)
        }
        .onChange(of: viewModel.pulseState.aggregateStatus) { _, _ in
            handleActivityChange()
        }
        .onChange(of: viewModel.pulseState.currentCard) { _, card in
            if card != nil {
                isVisible = true
            }
        }
    }

    // MARK: - Notch Layout

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: max(24, closedNotchSize.height))

            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 6) {
            // Status indicator dot (replaces ClaudeCrabIcon)
            if hasActivity || viewModel.status == .opened {
                StatusIndicatorView(
                    status: viewModel.pulseState.aggregateStatus,
                    size: 8
                )
                .frame(width: viewModel.status == .opened ? nil : sideWidth)
                .padding(.leading, viewModel.status == .opened ? 8 : 0)
            }

            if viewModel.status == .opened {
                // Opened header: show notification summary or title
                openedHeaderContent
            } else if !hasActivity {
                // Closed without activity: just black space
                Rectangle()
                    .fill(.clear)
                    .frame(width: closedNotchSize.width - 20)
            } else {
                // Closed with activity: spacer
                Rectangle()
                    .fill(.black)
                    .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top)
            }

            // Right side: pending count badge when closed
            if hasActivity && viewModel.status != .opened {
                if viewModel.pulseState.pendingCount > 0 {
                    Text("\(viewModel.pulseState.pendingCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(PulseColors.alert)
                        .clipShape(Capsule())
                        .frame(width: sideWidth)
                        .padding(.trailing, 4)
                } else {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: sideWidth)
                }
            }
        }
        .frame(height: closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchSize.height - 12) + 10
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 8) {
            if !hasActivity {
                StatusIndicatorView(status: .inactive, size: 8)
                    .padding(.leading, 8)
            }

            Spacer()

            // Timeline toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if viewModel.contentType == .timeline {
                        viewModel.showCard()
                    } else {
                        viewModel.showTimeline()
                    }
                }
            } label: {
                Image(systemName: viewModel.contentType == .timeline ? "xmark" : "list.bullet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .card:
                cardContentView
            case .timeline:
                PulseTimelineView(
                    history: viewModel.pulseState.history,
                    onSelect: { record in
                        Task {
                            if let session = await PulseStore.shared.getSession(id: record.sessionId) {
                                await TerminalFocusHelper.jumpToTerminal(session: session)
                            }
                            await PulseStore.shared.acknowledgeRecord(id: record.id)
                        }
                    },
                    onClear: {
                        Task {
                            await PulseStore.shared.clearHistory()
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var cardContentView: some View {
        VStack(spacing: 8) {
            if let card = viewModel.pulseState.currentCard {
                NotificationCardView(
                    card: card,
                    onJump: {
                        Task {
                            if let session = await PulseStore.shared.getSession(id: card.event.sessionId) {
                                await TerminalFocusHelper.jumpToTerminal(session: session)
                            }
                            // For permission cards, don't dismiss — user may still
                            // want to Allow/Deny after checking the terminal.
                            if card.event.type != .permissionRequest {
                                await PulseStore.shared.dismissCurrentCard()
                                await MainActor.run { viewModel.notchClose() }
                            }
                        }
                    },
                    onDismiss: {
                        Task {
                            await PulseStore.shared.dismissCurrentCard()
                        }
                    },
                    onAllow: card.event.type == .permissionRequest ? {
                        Task {
                            await PulseStore.shared.respondToPermission(
                                sessionId: card.event.sessionId,
                                toolUseId: card.event.toolUseId ?? "",
                                allow: true
                            )
                        }
                    } : nil,
                    onDeny: card.event.type == .permissionRequest ? {
                        Task {
                            await PulseStore.shared.respondToPermission(
                                sessionId: card.event.sessionId,
                                toolUseId: card.event.toolUseId ?? "",
                                allow: false
                            )
                        }
                    } : nil
                )
            } else {
                // Empty state: show session summary
                VStack(spacing: 8) {
                    let sessions = viewModel.pulseState.sessions
                    if sessions.isEmpty {
                        Text("No active sessions")
                            .font(.system(size: 12))
                            .foregroundColor(PulseColors.textTertiary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(sessions.prefix(3)) { session in
                            sessionRow(session)
                        }
                        if sessions.count > 3 {
                            Text("+\(sessions.count - 3) more")
                                .font(.system(size: 10))
                                .foregroundColor(PulseColors.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Pending count
            let pending = viewModel.pulseState.pendingCount
            if pending > 0 {
                HStack {
                    Spacer()
                    Text("\(pending) unacknowledged")
                        .font(.system(size: 10))
                        .foregroundColor(PulseColors.textTertiary)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionState) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phaseColor(session.phase))
                .frame(width: 6, height: 6)

            Text(session.projectName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PulseColors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(session.phase.description)
                .font(.system(size: 10))
                .foregroundColor(PulseColors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func phaseColor(_ phase: SessionPhase) -> Color {
        switch phase {
        case .processing, .compacting: return PulseColors.processing
        case .waitingForInput: return PulseColors.idle
        case .waitingForApproval: return PulseColors.waiting
        case .idle: return PulseColors.inactive
        case .ended: return PulseColors.inactive
        }
    }

    // MARK: - Event Handlers

    private func handleStatusChange(_ newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
        case .closed:
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !hasActivity {
                    isVisible = false
                }
            }
        }
    }

    private func handleActivityChange() {
        if hasActivity {
            isVisible = true
        } else if viewModel.status == .closed && viewModel.hasPhysicalNotch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if !hasActivity && viewModel.status == .closed {
                    isVisible = false
                }
            }
        }
    }
}
