import SwiftUI

struct EventFormSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var eventDate: Date = Date()
    @State private var tagId: Int?
    @State private var endManuallySet: Bool = false
    @State private var isAdjustingEnd: Bool = false

    private var isEditing: Bool { appState.editingEvent != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Name") {
                    TextField("Event name", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        .onChange(of: startTime) { oldValue, newValue in
                            if !endManuallySet {
                                // Maintain duration when start changes
                                isAdjustingEnd = true
                                let delta = newValue.timeIntervalSince(oldValue)
                                endTime = endTime.addingTimeInterval(delta)
                            }
                        }

                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        .onChange(of: endTime) { _, _ in
                            if isAdjustingEnd {
                                isAdjustingEnd = false
                            } else {
                                endManuallySet = true
                            }
                        }

                    // Quick duration buttons
                    HStack(spacing: 8) {
                        durationButton(15)
                        durationButton(30)
                        durationButton(45)
                        durationButton(60)
                        durationButton(90)
                        durationButton(120)
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                }

                Section("Tag") {
                    TagSelector(selectedTagId: $tagId)
                }
            }
            .navigationTitle(isEditing ? "Edit Event" : "Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let startStr = timeToString(startTime)
                        var endStr = timeToString(endTime)
                        // If end <= start, force end = start + default duration
                        let startMins = DateTimeUtils.timeToMinutes(startStr)
                        let endMins = DateTimeUtils.timeToMinutes(endStr)
                        if endMins <= startMins {
                            endStr = DateTimeUtils.minutesToTime(startMins + appState.settings.defaultEventDuration)
                        }
                        let dateStr = dateToString(eventDate)
                        appState.saveEvent(
                            name: name,
                            start: startStr,
                            end: endStr,
                            tagId: tagId,
                            date: dateStr,
                            editing: appState.editingEvent
                        )
                        appState.editingEvent = nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let event = appState.editingEvent {
                    name = event.name
                    startTime = timeFromString(event.start)
                    endTime = timeFromString(event.end)
                    eventDate = dateFromString(event.date) ?? Date()
                    tagId = event.tagId
                    endManuallySet = true
                } else {
                    name = ""
                    // Default: next 30-min slot
                    let now = Date()
                    let calendar = Calendar.current
                    let minutes = calendar.component(.minute, from: now)
                    let roundedUp = (minutes / 30 + 1) * 30
                    startTime = calendar.date(bySetting: .minute, value: roundedUp % 60, of: now) ?? now
                    if roundedUp >= 60 {
                        startTime = calendar.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
                        startTime = calendar.date(bySetting: .minute, value: 0, of: startTime) ?? startTime
                    }
                    endTime = startTime.addingTimeInterval(Double(appState.settings.defaultEventDuration) * 60)
                    eventDate = dateFromString(appState.selectedDate) ?? Date()
                    tagId = nil
                    endManuallySet = false
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Duration Button

    private func durationButton(_ minutes: Int) -> some View {
        Button(DateTimeUtils.formatElapsed(minutes)) {
            isAdjustingEnd = true
            endTime = startTime.addingTimeInterval(Double(minutes) * 60)
            endManuallySet = true
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func timeToString(_ date: Date) -> String {
        let calendar = Calendar.current
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    private func timeFromString(_ str: String) -> Date {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return Date() }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts[0]
        components.minute = parts[1]
        return Calendar.current.date(from: components) ?? Date()
    }

    private func dateToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dateFromString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: str + "T12:00:00")
    }
}
