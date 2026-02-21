import SwiftUI

struct EventListView: View {
    @Environment(AppState.self) private var appState
    @State private var showBulkEntry = false
    @State private var bulkText = ""

    private var dateEvents: [EventItem] {
        let now = appState.currentTimeMinutes
        return appState.events
            .filter { $0.date == appState.selectedDate }
            .filter { event in
                if appState.hidePastEvents {
                    let isPast = appState.isToday
                        ? DateTimeUtils.timeToMinutes(event.end) <= now
                        : appState.selectedDate < appState.todayStr
                    return !isPast
                }
                return true
            }
            .sorted { DateTimeUtils.timeToMinutes($0.start) < DateTimeUtils.timeToMinutes($1.start) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Text(DateTimeUtils.formatDateHeader(appState.selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(appState.hidePastEvents ? "Show past" : "Hide past") {
                    appState.hidePastEvents.toggle()
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if dateEvents.isEmpty && !showBulkEntry {
                ContentUnavailableView {
                    Label("No Events", systemImage: "clock")
                } description: {
                    Text("No events scheduled for this day.")
                }
            } else {
                List {
                    ForEach(dateEvents) { event in
                        EventRowView(event: event)
                    }
                }
                .listStyle(.plain)
            }

            // Bulk entry
            if showBulkEntry {
                VStack(spacing: 8) {
                    Text("Paste events (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Format: Name HH:MM-HH:MM YYYY-MM-DD [Tag]")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextEditor(text: $bulkText)
                        .frame(height: 100)
                        .font(.caption)
                        .border(Color.gray.opacity(0.3))
                        .padding(.horizontal)

                    HStack {
                        Button("Import") {
                            appState.importBulkEvents(text: bulkText)
                            bulkText = ""
                            showBulkEntry = false
                        }
                        .disabled(bulkText.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Cancel") {
                            bulkText = ""
                            showBulkEntry = false
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 8)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Bulk Add") {
                    showBulkEntry.toggle()
                }
                .font(.caption)

                Spacer()

                if dateEvents.contains(where: { event in
                    appState.isToday
                        ? DateTimeUtils.timeToMinutes(event.end) <= appState.currentTimeMinutes
                        : appState.selectedDate < appState.todayStr
                }) {
                    Button("Clear Past") {
                        appState.clearPastEvents()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                if !dateEvents.isEmpty {
                    Button("Clear All") {
                        appState.clearAllEvents()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
