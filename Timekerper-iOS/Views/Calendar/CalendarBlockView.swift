import SwiftUI

struct CalendarBlockView: View {
    @Environment(AppState.self) private var appState
    let block: Block
    let contentWidth: CGFloat

    private var extStartMin: Int { DateTimeUtils.timeToMinutes(appState.settings.extendedStart) }
    private var pixelsPerMinute: CGFloat { CGFloat(appState.settings.zoomLevel) * 1.5 }

    private var blockHeight: CGFloat {
        CGFloat(block.endMin - block.startMin) * pixelsPerMinute
    }

    private var blockWidth: CGFloat {
        if block.type == .event && block.totalColumns > 1 {
            return (contentWidth / CGFloat(block.totalColumns)) - 2
        }
        return contentWidth - 4
    }

    private var isCompact: Bool { blockHeight < 40 }
    private var isTiny: Bool { blockHeight < 25 }

    private var tagColor: String {
        appState.colorForTag(block.tagId, defaultColor: block.type == .event
            ? appState.settings.defaultEventColor
            : appState.settings.defaultTaskColor)
    }

    private var isDark: Bool { appState.settings.darkMode }

    var body: some View {
        Group {
            switch block.type {
            case .task:
                taskBlockContent
            case .event:
                eventBlockContent
            case .pause:
                pauseBlockContent
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
    }

    // MARK: - Task Block

    private var taskBlockContent: some View {
        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorUtils.blendWithSurface(hex: tagColor, alpha: 0.1, isDarkMode: isDark))
                .overlay(alignment: .leading) {
                    // Thick left border
                    Rectangle()
                        .fill(Color(hex: tagColor))
                        .frame(width: 3)
                }

            // Active glow
            if block.isActive {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.green, lineWidth: 2)
                    .shadow(color: Color.green.opacity(0.4), radius: 4)
            }

            // Paused remaining pattern
            if block.isPausedRemaining {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
            }

            // Content
            VStack(alignment: .leading, spacing: 1) {
                if isCompact {
                    HStack(spacing: 4) {
                        Text(block.name)
                            .font(.system(size: fontSize(.title)))
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .strikethrough(block.isCompleted)
                        if !isTiny {
                            Text(DateTimeUtils.formatBlockTimeRange(
                                start: block.start, end: block.end, isTask: true))
                                .font(.system(size: fontSize(.time)))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(block.name)
                        .font(.system(size: fontSize(.title)))
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .strikethrough(block.isCompleted)
                    Text(DateTimeUtils.formatBlockTimeRange(
                        start: block.start, end: block.end, isTask: true))
                        .font(.system(size: fontSize(.time)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, isCompact ? 2 : 4)
            .padding(.leading, 3) // account for left border
        }
        .opacity(block.isPast ? 0.5 : 1)
    }

    // MARK: - Event Block

    private var eventBlockContent: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: tagColor))

            VStack(alignment: .leading, spacing: 1) {
                if isCompact {
                    HStack(spacing: 4) {
                        Text(block.name)
                            .font(.system(size: fontSize(.title)))
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if !isTiny {
                            Text(DateTimeUtils.formatBlockTimeRange(
                                start: block.start, end: block.end, isTask: false))
                                .font(.system(size: fontSize(.time)))
                        }
                    }
                } else {
                    Text(block.name)
                        .font(.system(size: fontSize(.title)))
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(DateTimeUtils.formatBlockTimeRange(
                        start: block.start, end: block.end, isTask: false))
                        .font(.system(size: fontSize(.time)))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, isCompact ? 2 : 4)
            .foregroundStyle(ColorUtils.blockTextColor(hex: tagColor, type: .event, isDarkMode: isDark))
        }
        .opacity(block.isPast ? 0.5 : 1)
    }

    // MARK: - Pause Block

    private var pauseBlockContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    // Diagonal amber stripes
                    Color.orange.opacity(0.2)
                )
                .overlay {
                    // Dashed border
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

            if !isTiny {
                Text("Paused")
                    .font(.system(size: fontSize(.time)))
                    .foregroundStyle(Color(hex: "#92400e"))
            }
        }
        .opacity(block.isPast ? 0.5 : 1)
    }

    // MARK: - Helpers

    private enum FontRole { case title, time }

    private func fontSize(_ role: FontRole) -> CGFloat {
        let sizes: [String: (title: CGFloat, time: CGFloat)] = [
            "small": (10, 8),
            "medium": (11.5, 9.5),
            "large": (13.5, 11),
            "xlarge": (15.5, 12.5),
        ]
        let pair = sizes[appState.settings.calendarFontSize] ?? sizes["medium"]!
        return role == .title ? pair.title : pair.time
    }

    private func handleTap() {
        switch block.type {
        case .task:
            if let taskId = block.taskId,
               let task = appState.tasks.first(where: { $0.id == taskId }) {
                appState.editingTask = task
                appState.showTaskSheet = true
            }
        case .event:
            if let eventId = block.eventId,
               let event = appState.events.first(where: { $0.id == eventId }) {
                appState.editingEvent = event
                appState.showEventSheet = true
            }
        case .pause:
            break
        }
    }
}
