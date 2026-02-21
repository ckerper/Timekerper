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

            // Extended View Hours
            extendedHoursSection

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
            timePicker(label: "Start", value: Binding(
                get: { appState.settings.workdayStart },
                set: { appState.settings.workdayStart = $0 }
            ))
            timePicker(label: "End", value: Binding(
                get: { appState.settings.workdayEnd },
                set: { appState.settings.workdayEnd = $0 }
            ))
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
                    get: { appState.settings.extendedEnd },
                    set: { appState.settings.extendedEnd = $0 }
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

            HStack {
                Text("Zoom")
                Spacer()
                Button(action: {
                    let levels: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]
                    if let idx = levels.firstIndex(of: appState.settings.zoomLevel), idx > 0 {
                        appState.settings.zoomLevel = levels[idx - 1]
                    }
                }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                Text("\(Int(appState.settings.zoomLevel * 100))%")
                    .frame(width: 44)
                    .font(.caption.monospacedDigit())
                Button(action: {
                    let levels: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]
                    if let idx = levels.firstIndex(of: appState.settings.zoomLevel), idx < levels.count - 1 {
                        appState.settings.zoomLevel = levels[idx + 1]
                    }
                }) {
                    Image(systemName: "plus.magnifyingglass")
                }
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
            Toggle("Restrict tasks to work hours", isOn: Binding(
                get: { appState.settings.restrictTasksToWorkHours },
                set: { appState.settings.restrictTasksToWorkHours = $0 }
            ))
            Toggle("Dark mode", isOn: Binding(
                get: { appState.settings.darkMode },
                set: { appState.settings.darkMode = $0 }
            ))
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section("Tags") {
            TagEditorView()
        }
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
        }
    }

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

    // MARK: - Time Picker Helper

    private func timePicker(label: String, value: Binding<String>) -> some View {
        DatePicker(
            label,
            selection: Binding(
                get: {
                    let parts = value.wrappedValue.split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 2 else { return Date() }
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                    components.hour = parts[0]
                    components.minute = parts[1]
                    return Calendar.current.date(from: components) ?? Date()
                },
                set: { date in
                    let h = Calendar.current.component(.hour, from: date)
                    let m = Calendar.current.component(.minute, from: date)
                    value.wrappedValue = String(format: "%02d:%02d", h, m)
                }
            ),
            displayedComponents: .hourAndMinute
        )
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
