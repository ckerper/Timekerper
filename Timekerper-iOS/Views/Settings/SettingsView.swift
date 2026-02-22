import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showImportPicker = false
    @State private var showSyncConnect = false
    @State private var syncPatInput = ""

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .fileImporter(
                    isPresented: $showImportPicker,
                    allowedContentTypes: [UTType.json],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        if url.startAccessingSecurityScopedResource() {
                            defer { url.stopAccessingSecurityScopedResource() }
                            if let data = try? Data(contentsOf: url) {
                                appState.importSettings(from: data)
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            // Working Hours
            workingHoursSection

            // Extended View Hours (only when specifying working hours)
            if appState.settings.specifyWorkingHours {
                extendedHoursSection
            }

            // Defaults
            defaultsSection

            // Calendar
            calendarSection

            // Behavior
            behaviorSection

            // Tags
            tagsSection

            // Sync
            syncSection

            // Debug
            debugSection

            // Transfer
            transferSection
        }
    }

    // MARK: - Working Hours

    private var workingHoursSection: some View {
        Section("Working Hours") {
            Toggle("Specify working hours", isOn: Binding(
                get: { appState.settings.specifyWorkingHours },
                set: { appState.settings.specifyWorkingHours = $0 }
            ))

            if appState.settings.specifyWorkingHours {
                timePicker(label: "Start", value: Binding(
                    get: { appState.settings.workdayStart },
                    set: { appState.settings.workdayStart = $0 }
                ))
                timePicker(label: "End", value: Binding(
                    get: { appState.settings.workdayEnd == "23:59" ? "00:00" : appState.settings.workdayEnd },
                    set: { appState.settings.workdayEnd = ($0 == "00:00") ? "23:59" : $0 }
                ))
            }
        }
    }

    // MARK: - Extended Hours

    private var extendedHoursSection: some View {
        Section("Extended View Hours") {
            Toggle("Show extended hours", isOn: Binding(
                get: { appState.settings.useExtendedHours },
                set: { appState.settings.useExtendedHours = $0 }
            ))

            if appState.settings.useExtendedHours {
                timePicker(label: "Extended Start", value: Binding(
                    get: { appState.settings.extendedStart },
                    set: { appState.settings.extendedStart = $0 }
                ))
                timePicker(label: "Extended End", value: Binding(
                    get: { appState.settings.extendedEnd == "23:59" ? "00:00" : appState.settings.extendedEnd },
                    set: { appState.settings.extendedEnd = ($0 == "00:00") ? "23:59" : $0 }
                ))
            }
        }
    }

    // MARK: - Defaults

    private var defaultsSection: some View {
        Section("Defaults") {
            Stepper("Task duration: \(appState.settings.defaultTaskDuration)m",
                    value: Binding(
                        get: { appState.settings.defaultTaskDuration },
                        set: { appState.settings.defaultTaskDuration = $0 }
                    ), in: 5...480, step: 5)

            Stepper("Event duration: \(appState.settings.defaultEventDuration)m",
                    value: Binding(
                        get: { appState.settings.defaultEventDuration },
                        set: { appState.settings.defaultEventDuration = $0 }
                    ), in: 5...480, step: 5)

            ColorPicker("Default task color",
                        selection: Binding(
                            get: { Color(hex: appState.settings.defaultTaskColor) },
                            set: { appState.settings.defaultTaskColor = $0.toHex() }
                        ))

            ColorPicker("Default event color",
                        selection: Binding(
                            get: { Color(hex: appState.settings.defaultEventColor) },
                            set: { appState.settings.defaultEventColor = $0.toHex() }
                        ))
        }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        Section("Calendar") {
            Stepper("Min fragment: \(appState.settings.minFragmentMinutes)m",
                    value: Binding(
                        get: { appState.settings.minFragmentMinutes },
                        set: { appState.settings.minFragmentMinutes = $0 }
                    ), in: 1...10)

            Picker("Font size", selection: Binding(
                get: { appState.settings.calendarFontSize },
                set: { appState.settings.calendarFontSize = $0 }
            )) {
                Text("Small").tag("small")
                Text("Medium").tag("medium")
                Text("Large").tag("large")
                Text("Extra Large").tag("xlarge")
            }

        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Auto-start next task", isOn: Binding(
                get: { appState.settings.autoStartNext },
                set: { appState.settings.autoStartNext = $0 }
            ))
            Toggle("Smart duration parsing", isOn: Binding(
                get: { appState.settings.smartDuration },
                set: { appState.settings.smartDuration = $0 }
            ))
            Toggle("Wrap names in list", isOn: Binding(
                get: { appState.settings.wrapListNames },
                set: { appState.settings.wrapListNames = $0 }
            ))
            if appState.settings.specifyWorkingHours {
                Toggle("Restrict tasks to work hours", isOn: Binding(
                    get: { appState.settings.restrictTasksToWorkHours },
                    set: { appState.settings.restrictTasksToWorkHours = $0 }
                ))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Dark Mode")
                Picker("Dark mode", selection: Binding(
                    get: { appState.settings.darkMode },
                    set: { appState.settings.darkMode = $0 }
                )) {
                    Text("Off").tag("off")
                    Text("System").tag("system")
                    Text("On").tag("on")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section("Tags") {
            TagEditorView()
        }
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("Sync") {
            if appState.syncEnabled {
                HStack {
                    Circle()
                        .fill(syncDotColor)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.subheadline)
                    Spacer()
                    if let lastSync = appState.lastSynced {
                        Text(lastSync, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = appState.syncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Sync Now") {
                    Task {
                        await appState.doPull()
                        await appState.doPush()
                    }
                }

                Button("Disconnect", role: .destructive) {
                    appState.syncEnabled = false
                    appState.syncPat = ""
                    appState.syncGistId = ""
                    KeychainService.delete(key: "pat")
                    PersistenceService.delete(key: "syncGistId")
                    PersistenceService.delete(key: "syncEnabled")
                }
            } else {
                TextField("GitHub Personal Access Token", text: $syncPatInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)

                if let error = appState.syncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if appState.syncStatus == .syncing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Connect") {
                        connectSync()
                    }
                    .disabled(syncPatInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var syncDotColor: Color {
        switch appState.syncStatus {
        case .idle: return .green
        case .syncing: return .orange
        case .error: return .red
        }
    }

    private func connectSync() {
        let pat = syncPatInput.trimmingCharacters(in: .whitespaces)
        guard !pat.isEmpty else { return }
        appState.syncStatus = .syncing
        appState.syncError = nil

        Task { @MainActor in
            do {
                if let existing = try await SyncService.findGist(pat: pat) {
                    // Found existing gist — pull data
                    appState.suppressingPush = true
                    appState.tasks = existing.data.tasks
                    appState.events = existing.data.events
                    appState.tags = existing.data.tags
                    appState.settings = appState.settings.merging(remote: existing.data.settings)
                    appState.suppressingPush = false
                    appState.syncGistId = existing.gistId
                } else {
                    // Create new gist
                    let payload = SyncPayload(
                        tasks: appState.tasks,
                        events: appState.events,
                        tags: appState.tags,
                        settings: appState.settings.strippingLocalOnly(),
                        activeTaskId: appState.activeTaskId,
                        pushedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    let gistId = try await SyncService.createGist(pat: pat, payload: payload)
                    appState.syncGistId = gistId
                }

                KeychainService.save(key: "pat", value: pat)
                PersistenceService.save(appState.syncGistId, key: "syncGistId")
                PersistenceService.save(true, key: "syncEnabled")
                appState.syncPat = pat
                appState.syncEnabled = true
                appState.syncStatus = .idle
                appState.lastSynced = Date()
                syncPatInput = ""
            } catch {
                appState.syncStatus = .error
                appState.syncError = error.localizedDescription
            }
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        Section("Debug") {
            Toggle("Debug mode", isOn: Binding(
                get: { appState.settings.debugMode },
                set: { appState.settings.debugMode = $0 }
            ))

            if appState.settings.debugMode {
                Stepper("Time offset: \(appState.settings.debugTimeOffset)m",
                        value: Binding(
                            get: { appState.settings.debugTimeOffset },
                            set: { appState.settings.debugTimeOffset = $0 }
                        ), in: -720...720, step: 15)

                let effectiveTime = DateTimeUtils.currentTimeMinutes() + appState.settings.debugTimeOffset
                Text("Effective time: \(DateTimeUtils.formatTime(DateTimeUtils.minutesToTime(effectiveTime)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Last build: \(Self.buildDateString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let buildDateString: String = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        // __DATE__ and __TIME__ aren't available in Swift; use executable modification date
        if let execURL = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
           let date = attrs[.modificationDate] as? Date {
            return formatter.string(from: date)
        }
        return "Unknown"
    }()

    // MARK: - Transfer

    private var transferSection: some View {
        Section("Transfer Settings") {
            if let data = appState.exportSettingsData() {
                ShareLink(item: data, preview: SharePreview("Timekerper Settings", image: Image(systemName: "gearshape"))) {
                    Label("Export Settings", systemImage: "square.and.arrow.up")
                }
            }

            Button(action: { showImportPicker = true }) {
                Label("Import Settings", systemImage: "square.and.arrow.down")
            }
        }
    }

    // MARK: - Time Picker Helper (hour + minute wheels, 15-min increments)

    private func timePicker(label: String, value: Binding<String>) -> some View {
        TimeWheelPicker(label: label, value: value)
    }
}

// MARK: - Time Wheel Picker

/// A time picker with three wheel columns: Hour (1-12), Minute (:00/:15/:30/:45), AM/PM.
/// Binds to an "HH:mm" 24-hour string (e.g. "09:00", "17:30").
private struct TimeWheelPicker: View {
    let label: String
    @Binding var value: String

    private static let minuteOptions = [0, 15, 30, 45]

    // Parse "HH:mm" → (hour12, minute, isAM)
    private var parsed: (hour12: Int, minute: Int, isAM: Bool) {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return (9, 0, true) }
        let h24 = parts[0]
        let m = (parts[1] / 15) * 15 // snap to nearest 15
        let isAM = h24 < 12
        let h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24)
        return (h12, m, isAM)
    }

    private func writeBack(hour12: Int, minute: Int, isAM: Bool) {
        var h24: Int
        if isAM {
            h24 = hour12 == 12 ? 0 : hour12
        } else {
            h24 = hour12 == 12 ? 12 : hour12 + 12
        }
        value = String(format: "%02d:%02d", h24, minute)
    }

    var body: some View {
        let p = parsed

        HStack {
            Text(label)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 0) {
                // Hour wheel (1-12)
                Picker("Hour", selection: Binding(
                    get: { p.hour12 },
                    set: { writeBack(hour12: $0, minute: p.minute, isAM: p.isAM) }
                )) {
                    ForEach(1...12, id: \.self) { h in
                        Text("\(h)").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 50)
                .clipped()

                // Minute wheel (:00, :15, :30, :45)
                Picker("Minute", selection: Binding(
                    get: { p.minute },
                    set: { writeBack(hour12: p.hour12, minute: $0, isAM: p.isAM) }
                )) {
                    ForEach(Self.minuteOptions, id: \.self) { m in
                        Text(String(format: ":%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)
                .clipped()

                // AM/PM wheel
                Picker("Period", selection: Binding(
                    get: { p.isAM },
                    set: { writeBack(hour12: p.hour12, minute: p.minute, isAM: $0) }
                )) {
                    Text("AM").tag(true)
                    Text("PM").tag(false)
                }
                .pickerStyle(.wheel)
                .frame(width: 50)
                .clipped()
            }
            .frame(height: 100)
        }
    }
}

// Make Data conform to Transferable for ShareLink
extension Data: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { data in
            data
        }
    }
}
