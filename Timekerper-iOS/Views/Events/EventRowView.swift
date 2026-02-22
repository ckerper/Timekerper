import SwiftUI

struct EventRowView: View {
    @Environment(AppState.self) private var appState
    let event: EventItem

    private var tag: Tag? {
        appState.tagForId(event.tagId)
    }

    private var isPast: Bool {
        let today = appState.todayStr
        if event.date < today { return true }
        if event.date == today {
            return DateTimeUtils.timeToMinutes(event.end) <= appState.currentTimeMinutes
        }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            // Tag dot
            if let tag = tag {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 8, height: 8)
            }

            // Name
            Text(event.name)
                .font(.subheadline)
                .foregroundStyle(isPast ? .secondary : .primary)
                .lineLimit(2)

            Spacer()

            // Time range
            Text(DateTimeUtils.formatBlockTimeRange(start: event.start, end: event.end, isTask: false))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Delete
            Button(action: { appState.deleteEvent(id: event.id) }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.editingEvent = event
            appState.showEventSheet = true
        }
    }
}
