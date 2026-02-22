import SwiftUI

struct EventListView: View {
    @Environment(AppState.self) private var appState
    @State private var showBulkEntry = false
    @State private var bulkText = ""

    /// All events from today forward, grouped by date
    private var futureEventGroups: [(date: String, events: [EventItem])] {
        let today = appState.todayStr
        let now = appState.currentTimeMinutes

        let filtered = appState.events
            .filter { e in
                // Only today or future
                if e.date < today { return false }
                // On today, optionally hide events that have ended
                if appState.hidePastEvents && e.date == today {
                    return DateTimeUtils.timeToMinutes(e.end) > now
                }
                return true
            }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return DateTimeUtils.timeToMinutes($0.start) < DateTimeUtils.timeToMinutes($1.start)
            }

        // Group by date
        var grouped: [(date: String, events: [EventItem])] = []
        var currentDate = ""
        for event in filtered {
            if event.date != currentDate {
                grouped.append((date: event.date, events: [event]))
                currentDate = event.date
            } else {
                grouped[grouped.count - 1].events.append(event)
            }
        }
        return grouped
    }

    private var hasPastEvents: Bool {
        let today = appState.todayStr
        let now = appState.currentTimeMinutes
        return appState.events.contains { e in
            e.date < today ||
            (e.date == today && DateTimeUtils.timeToMinutes(e.end) <= now)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                let count = appState.events.filter { $0.date >= appState.todayStr }.count
                Text("\(count) upcoming event\(count == 1 ? "" : "s")")
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

            if futureEventGroups.isEmpty && !showBulkEntry {
                ContentUnavailableView {
                    Label("No Upcoming Events", systemImage: "clock")
                } description: {
                    Text("No events scheduled from today forward.")
                }
            } else {
                List {
                    ForEach(futureEventGroups, id: \.date) { group in
                        Section {
                            ForEach(group.events) { event in
                                EventRowView(event: event)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            }
                        } header: {
                            Text(DateTimeUtils.formatDateHeader(group.date))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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

                if hasPastEvents {
                    Button("Clear Past") {
                        appState.clearPastEvents()
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
