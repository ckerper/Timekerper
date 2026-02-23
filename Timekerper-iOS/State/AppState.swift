import SwiftUI
import Observation

struct UndoSnapshot: Sendable {
    let tasks: [TaskItem]
    let events: [EventItem]
}

@Observable
final class AppState {

    // MARK: - Core Data

    var tasks: [TaskItem] {
        didSet { PersistenceService.save(tasks, key: "tasks"); scheduleSyncPush() }
    }
    var events: [EventItem] {
        didSet { PersistenceService.save(events, key: "events"); scheduleSyncPush() }
    }
    var tags: [Tag] {
        didSet { PersistenceService.save(tags, key: "tags"); scheduleSyncPush() }
    }
    var settings: AppSettings {
        didSet {
            PersistenceService.save(settings, key: "settings")
            scheduleSyncPush()
        }
    }

    // MARK: - Active Task

    var activeTaskId: Int? {
        didSet { PersistenceService.save(activeTaskId, key: "activeTaskId"); scheduleSyncPush() }
    }
    var taskStartTime: Date?
    var elapsedMinutes: Int = 0
    var currentTimeMinutes: Int

    // MARK: - Navigation

    var selectedDate: String

    // MARK: - UI State

    var showTaskSheet = false
    var showEventSheet = false
    var showSettingsSheet = false
    var editingTask: TaskItem?
    var editingEvent: EventItem?
    var adjustIncrement: Int = 5 {
        didSet { PersistenceService.save(adjustIncrement, key: "adjustIncrement") }
    }
    var hideCompleted = true
    var hidePastEvents = false

    // MARK: - Undo/Redo

    private(set) var undoStack: [UndoSnapshot] = []
    private(set) var redoStack: [UndoSnapshot] = []
    private let maxUndoDepth = 50

    // MARK: - Sync

    var syncEnabled: Bool = false
    var syncPat: String = ""
    var syncGistId: String = ""
    var syncStatus: SyncStatus = .idle
    var syncError: String?
    var lastSynced: Date?
    var suppressingPush = false
    private var syncPushTask: Task<Void, Never>?

    enum SyncStatus: String {
        case idle, syncing, error
    }

    // MARK: - Timer

    private var timer: Timer?
    private var syncPullTimer: Timer?

    // MARK: - Computed

    var firstIncompleteTask: TaskItem? {
        tasks.first(where: { !$0.completed })
    }

    var todayStr: String {
        DateTimeUtils.todayStr()
    }

    var isToday: Bool {
        selectedDate == todayStr
    }

    var timeOffset: Int {
        settings.debugMode ? settings.debugTimeOffset : 0
    }

    var scheduledBlocks: [Block] {
        blocksForDate(selectedDate)
    }

    func blocksForDate(_ date: String) -> [Block] {
        // When extended hours are off, collapse extended boundaries to workday
        // boundaries so the scheduler doesn't place tasks in invisible hours.
        // Matches the web's effectiveSettings behavior.
        var effectiveSettings = settings
        if !settings.useExtendedHours {
            effectiveSettings.extendedStart = settings.workdayStart
            effectiveSettings.extendedEnd = settings.workdayEnd
        }
        return Scheduler.scheduleDay(
            tasks: tasks,
            events: events,
            settings: effectiveSettings,
            activeTaskId: activeTaskId,
            totalElapsed: elapsedMinutes,
            selectedDate: date
        )
    }

    var totalIncompleteDuration: Int {
        tasks.filter { !$0.completed }.reduce(0) { $0 + $1.effectiveDuration }
    }

    var incompleteTaskCount: Int {
        tasks.filter { !$0.completed }.count
    }

    // MARK: - Init

    init() {
        let loadedTasks = PersistenceService.load(key: "tasks", as: [TaskItem].self) ?? defaultTasks
        let loadedEvents = PersistenceService.load(key: "events", as: [EventItem].self) ?? defaultEvents
        let loadedTags = PersistenceService.load(key: "tags", as: [Tag].self) ?? defaultTags
        let loadedSettings = PersistenceService.load(key: "settings", as: AppSettings.self) ?? defaultSettings

        self.tasks = loadedTasks
        self.events = loadedEvents
        self.tags = loadedTags
        self.settings = loadedSettings
        self.selectedDate = DateTimeUtils.todayStr()

        let offset = loadedSettings.debugMode ? loadedSettings.debugTimeOffset : 0
        self.currentTimeMinutes = DateTimeUtils.currentTimeMinutes() + offset

        // Restore active task
        if let savedId = PersistenceService.load(key: "activeTaskId", as: Int?.self),
           let id = savedId {
            let task = loadedTasks.first(where: { $0.id == id && !$0.completed })
            if let task = task, task.startedAtMin != nil {
                let now = DateTimeUtils.currentTimeMinutes() + offset
                let gap = (task.pauseEvents ?? []).reduce(0) { sum, pe in
                    sum + ((pe.end ?? now) - pe.start)
                }
                let elapsed = max(0, now - (task.startedAtMin ?? 0) - gap)
                self.activeTaskId = id
                self.taskStartTime = Date().addingTimeInterval(-Double(elapsed) * 60)
                self.elapsedMinutes = elapsed
            }
        }

        // Restore adjust increment
        if let savedIncrement = PersistenceService.load(key: "adjustIncrement", as: Int.self) {
            self.adjustIncrement = savedIncrement
        }

        // Restore sync credentials
        if let pat = KeychainService.load(key: "pat"),
           let gistId = PersistenceService.load(key: "syncGistId", as: String.self),
           let enabled = PersistenceService.load(key: "syncEnabled", as: Bool.self),
           enabled, !pat.isEmpty, !gistId.isEmpty {
            self.syncPat = pat
            self.syncGistId = gistId
            self.syncEnabled = true
        }

        startTimer()
        startSyncPullTimer()
    }

    // MARK: - Timer Management

    func startTimer() {
        timer?.invalidate()
        let interval: TimeInterval = activeTaskId != nil ? 1 : 15
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    private func startSyncPullTimer() {
        syncPullTimer?.invalidate()
        guard syncEnabled else { return }
        syncPullTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.doPull()
            }
        }
        RunLoop.current.add(syncPullTimer!, forMode: .common)
    }

    private func tick() {
        let offset = settings.debugMode ? settings.debugTimeOffset : 0
        currentTimeMinutes = DateTimeUtils.currentTimeMinutes() + offset

        if let startTime = taskStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime) / 60)
            elapsedMinutes = max(0, elapsed)
        }
    }

    // MARK: - Undo / Redo

    func pushUndo() {
        undoStack.append(UndoSnapshot(tasks: tasks, events: events))
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(UndoSnapshot(tasks: tasks, events: events))
        tasks = snapshot.tasks
        events = snapshot.events
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(UndoSnapshot(tasks: tasks, events: events))
        tasks = snapshot.tasks
        events = snapshot.events
    }

    // MARK: - Active Task Handlers

    func startTask() {
        guard let first = firstIncompleteTask else { return }
        let pausedMs = Double(first.pausedElapsed) * 60
        let now = DateTimeUtils.currentTimeMinutes() + timeOffset

        // Update task fields
        if let idx = tasks.firstIndex(where: { $0.id == first.id }) {
            var t = tasks[idx]
            if t.startedAtMin == nil {
                t.startedAtMin = now
                t.startedAtDate = DateTimeUtils.todayStr()
            }
            if t.pausedAtMin != nil {
                t.pauseGapMinutes = (t.pauseGapMinutes ?? 0) + max(0, now - (t.pausedAtMin ?? 0))
                t.pausedAtMin = nil
                // Finalize open pause event
                if var pauseEvents = t.pauseEvents, !pauseEvents.isEmpty,
                   pauseEvents[pauseEvents.count - 1].end == nil {
                    pauseEvents[pauseEvents.count - 1].end = now
                    t.pauseEvents = pauseEvents
                }
            }
            tasks[idx] = t
        }

        activeTaskId = first.id
        taskStartTime = Date().addingTimeInterval(-pausedMs)
        elapsedMinutes = first.pausedElapsed
        startTimer() // Switch to 1s interval
    }

    func startSpecificTask(id: Int) {
        guard let taskIdx = tasks.firstIndex(where: { $0.id == id && !$0.completed }) else { return }

        // If a different task is already active, pause it first
        if activeTaskId != nil && activeTaskId != id {
            pauseActiveTask()
        }

        // If this task is already active, do nothing
        if activeTaskId == id { return }

        let task = tasks[taskIdx]
        let pausedMs = Double(task.pausedElapsed) * 60
        let now = DateTimeUtils.currentTimeMinutes() + timeOffset

        var t = tasks[taskIdx]
        if t.startedAtMin == nil {
            t.startedAtMin = now
            t.startedAtDate = DateTimeUtils.todayStr()
        }
        if t.pausedAtMin != nil {
            t.pauseGapMinutes = (t.pauseGapMinutes ?? 0) + max(0, now - (t.pausedAtMin ?? 0))
            t.pausedAtMin = nil
            if var pauseEvents = t.pauseEvents, !pauseEvents.isEmpty,
               pauseEvents[pauseEvents.count - 1].end == nil {
                pauseEvents[pauseEvents.count - 1].end = now
                t.pauseEvents = pauseEvents
            }
        }
        tasks[taskIdx] = t

        activeTaskId = id
        taskStartTime = Date().addingTimeInterval(-pausedMs)
        elapsedMinutes = task.pausedElapsed
        startTimer()
    }

    func completeActiveTask() {
        guard let activeId = activeTaskId else { return }
        pushUndo()
        let finishedElapsed = elapsedMinutes
        let now = DateTimeUtils.currentTimeMinutes() + timeOffset

        if let idx = tasks.firstIndex(where: { $0.id == activeId }) {
            var t = tasks[idx]
            let segStart = (t.startedAtMin ?? 0) + t.pausedElapsed + (t.pauseGapMinutes ?? 0)
            t.completed = true
            t.actualDuration = finishedElapsed
            var segs = t.workSegments ?? []
            segs.append(WorkSegment(start: segStart, end: now, date: DateTimeUtils.todayStr()))
            t.workSegments = segs
            t.pausedElapsed = 0
            t.pausedAtMin = nil
            t.pauseEvents = []
            tasks[idx] = t
        }

        if settings.autoStartNext {
            if let next = tasks.first(where: { !$0.completed }) {
                let pausedMs = Double(next.pausedElapsed) * 60
                // Update next task fields
                if let idx = tasks.firstIndex(where: { $0.id == next.id }) {
                    var t = tasks[idx]
                    if t.startedAtMin == nil {
                        t.startedAtMin = now
                        t.startedAtDate = DateTimeUtils.todayStr()
                    }
                    if t.pausedAtMin != nil {
                        t.pauseGapMinutes = (t.pauseGapMinutes ?? 0) + max(0, now - (t.pausedAtMin ?? 0))
                        t.pausedAtMin = nil
                        if var pauseEvents = t.pauseEvents, !pauseEvents.isEmpty,
                           pauseEvents[pauseEvents.count - 1].end == nil {
                            pauseEvents[pauseEvents.count - 1].end = now
                            t.pauseEvents = pauseEvents
                        }
                    }
                    tasks[idx] = t
                }
                activeTaskId = next.id
                taskStartTime = Date().addingTimeInterval(-pausedMs)
                elapsedMinutes = next.pausedElapsed
            } else {
                clearActiveState()
            }
        } else {
            clearActiveState()
        }
        startTimer()
    }

    func pauseActiveTask() {
        guard let activeId = activeTaskId else { return }
        pushUndo()
        let now = DateTimeUtils.currentTimeMinutes() + timeOffset

        if let idx = tasks.firstIndex(where: { $0.id == activeId }) {
            var t = tasks[idx]
            let segStart = (t.startedAtMin ?? 0) + t.pausedElapsed + (t.pauseGapMinutes ?? 0)
            t.pausedElapsed = elapsedMinutes
            t.pausedAtMin = now
            var segs = t.workSegments ?? []
            segs.append(WorkSegment(start: segStart, end: now, date: DateTimeUtils.todayStr()))
            t.workSegments = segs
            var pauses = t.pauseEvents ?? []
            pauses.append(PauseEvent(start: now, end: nil, date: DateTimeUtils.todayStr()))
            t.pauseEvents = pauses
            tasks[idx] = t
        }

        clearActiveState()
        startTimer() // Switch to 15s interval
    }

    func cancelActiveTask() {
        if let activeId = activeTaskId,
           let idx = tasks.firstIndex(where: { $0.id == activeId }) {
            var t = tasks[idx]
            t.startedAtMin = nil
            t.startedAtDate = nil
            t.pausedAtMin = nil
            t.pauseGapMinutes = 0
            t.pausedElapsed = 0
            t.workSegments = []
            t.pauseEvents = []
            tasks[idx] = t
        }
        clearActiveState()
        startTimer()
    }

    func adjustTaskTime(_ minutes: Int) {
        guard let activeId = activeTaskId else { return }
        pushUndo()
        if let idx = tasks.firstIndex(where: { $0.id == activeId }) {
            var t = tasks[idx]
            let current = t.adjustedDuration ?? t.duration
            t.adjustedDuration = max(5, current + minutes)
            tasks[idx] = t
        }
    }

    private func clearActiveState() {
        activeTaskId = nil
        taskStartTime = nil
        elapsedMinutes = 0
    }

    // MARK: - Task CRUD

    func saveTask(name: String, duration: Int, tagId: Int?, editing: TaskItem?, addToTop: Bool, smartParse: Bool = false) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pushUndo()

        if let editTask = editing {
            if let idx = tasks.firstIndex(where: { $0.id == editTask.id }) {
                var t = tasks[idx]
                t.name = name.trimmingCharacters(in: .whitespaces)
                t.adjustedDuration = duration
                t.tagId = tagId
                tasks[idx] = t
            }
        } else {
            // Multi-line: split by newlines
            let lines = name.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            var newTasks: [TaskItem] = []
            for (idx, line) in lines.enumerated() {
                let parsed = smartParse ? parseSmartDuration(line, defaultDuration: duration) : (name: line, duration: duration, tagId: tagId)
                newTasks.append(TaskItem.blank(
                    id: DateTimeUtils.generateId() + idx,
                    name: parsed.name,
                    duration: parsed.duration,
                    tagId: parsed.tagId ?? tagId
                ))
            }

            if addToTop {
                tasks = newTasks + tasks
            } else {
                tasks = tasks + newTasks
            }
        }
    }

    func deleteTask(id: Int) {
        pushUndo()
        if id == activeTaskId {
            cancelActiveTask()
        }
        tasks.removeAll { $0.id == id }
    }

    func toggleTaskComplete(id: Int) {
        pushUndo()
        let isActive = id == activeTaskId
        let finishedElapsed = isActive ? elapsedMinutes : 0
        let now = DateTimeUtils.currentTimeMinutes() + timeOffset

        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var t = tasks[idx]

        if !t.completed {
            // Completing
            t.completed = true
            t.pausedElapsed = 0
            t.pausedAtMin = nil
            t.pauseEvents = []

            if isActive {
                let segStart = (t.startedAtMin ?? 0) + (t.pausedElapsed) + (t.pauseGapMinutes ?? 0)
                var segs = t.workSegments ?? []
                segs.append(WorkSegment(start: segStart, end: now, date: DateTimeUtils.todayStr()))
                t.workSegments = segs
                t.actualDuration = finishedElapsed
            } else if let segs = t.workSegments, !segs.isEmpty {
                t.actualDuration = segs.reduce(0) { $0 + ($1.end - $1.start) }
            } else {
                t.actualDuration = 0
            }
            tasks[idx] = t

            // Handle auto-start next
            if isActive {
                if settings.autoStartNext, let next = tasks.first(where: { !$0.completed }) {
                    let pausedMs = Double(next.pausedElapsed) * 60
                    if let nIdx = tasks.firstIndex(where: { $0.id == next.id }) {
                        var nt = tasks[nIdx]
                        if nt.startedAtMin == nil {
                            nt.startedAtMin = now
                            nt.startedAtDate = DateTimeUtils.todayStr()
                        }
                        if nt.pausedAtMin != nil {
                            nt.pauseGapMinutes = (nt.pauseGapMinutes ?? 0) + max(0, now - (nt.pausedAtMin ?? 0))
                            nt.pausedAtMin = nil
                            if var pe = nt.pauseEvents, !pe.isEmpty, pe[pe.count - 1].end == nil {
                                pe[pe.count - 1].end = now
                                nt.pauseEvents = pe
                            }
                        }
                        tasks[nIdx] = nt
                    }
                    activeTaskId = next.id
                    taskStartTime = Date().addingTimeInterval(-pausedMs)
                    elapsedMinutes = next.pausedElapsed
                } else {
                    clearActiveState()
                }
                startTimer()
            }
        } else {
            // Uncompleting
            t.completed = false
            t.actualDuration = nil
            t.startedAtMin = nil
            t.startedAtDate = nil
            t.pausedAtMin = nil
            t.pauseGapMinutes = 0
            t.pausedElapsed = 0
            t.workSegments = []
            t.pauseEvents = []
            tasks[idx] = t
        }
    }

    func duplicateTask(_ task: TaskItem) {
        pushUndo()
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let copy = TaskItem.blank(
            id: DateTimeUtils.generateId(),
            name: task.name,
            duration: task.duration,
            tagId: task.tagId
        )
        tasks.insert(copy, at: idx + 1)
    }

    func moveTasks(from source: IndexSet, to destination: Int) {
        pushUndo()
        tasks.move(fromOffsets: source, toOffset: destination)
    }

    func clearCompletedTasks() {
        pushUndo()
        tasks.removeAll { $0.completed }
    }

    func clearAllTasks() {
        pushUndo()
        if activeTaskId != nil {
            clearActiveState()
        }
        tasks = []
    }

    // MARK: - Event CRUD

    func saveEvent(name: String, start: String, end: String, tagId: Int?, date: String, editing: EventItem?) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let eventName = trimmedName.isEmpty ? "Event" : trimmedName
        pushUndo()

        if let editEvent = editing {
            if let idx = events.firstIndex(where: { $0.id == editEvent.id }) {
                events[idx] = EventItem(id: editEvent.id, name: eventName, start: start, end: end, date: date, tagId: tagId)
            }
        } else {
            events.append(EventItem(
                id: DateTimeUtils.generateId(),
                name: eventName,
                start: start,
                end: end,
                date: date,
                tagId: tagId
            ))
        }
    }

    func deleteEvent(id: Int) {
        pushUndo()
        events.removeAll { $0.id == id }
    }

    func clearAllEvents() {
        pushUndo()
        events.removeAll { $0.date == selectedDate }
    }

    func clearPastEvents() {
        pushUndo()
        let today = todayStr
        let now = currentTimeMinutes
        events.removeAll { e in
            // Remove all events on days before the viewed day
            if e.date < selectedDate { return true }
            // On the viewed day: remove past events
            if e.date == selectedDate {
                if selectedDate < today { return true }
                if selectedDate == today {
                    return DateTimeUtils.timeToMinutes(e.end) <= now
                }
            }
            return false
        }
    }

    func importBulkEvents(text: String) {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        pushUndo()

        let pattern = /^(.+?)\s+(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s+(\d{4}-\d{2}-\d{2})(?:\s+\[(.+?)\])?$/
        var newEvents: [EventItem] = []

        for (i, line) in lines.enumerated() {
            if let match = try? pattern.firstMatch(in: line) {
                let name = String(match.1)
                let start = String(match.2).count == 4 ? "0" + String(match.2) : String(match.2)
                let end = String(match.3).count == 4 ? "0" + String(match.3) : String(match.3)
                let date = String(match.4)
                let tagName = match.5.map(String.init)
                let tagId = tagName.flatMap { name in tags.first(where: { $0.name == name })?.id }
                newEvents.append(EventItem(
                    id: DateTimeUtils.generateId() + i,
                    name: name,
                    start: start,
                    end: end,
                    date: date,
                    tagId: tagId
                ))
            }
        }

        events.append(contentsOf: newEvents)
    }

    // MARK: - Tag CRUD

    func addTag() {
        tags.append(Tag(id: DateTimeUtils.generateId(), name: "New Tag", color: "#94a3b8"))
    }

    func updateTag(id: Int, name: String? = nil, color: String? = nil) {
        guard let idx = tags.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { tags[idx].name = name }
        if let color = color { tags[idx].color = color }
    }

    func deleteTag(id: Int) {
        pushUndo()
        tags.removeAll { $0.id == id }
        tasks = tasks.map { t in
            var t = t
            if t.tagId == id { t.tagId = nil }
            return t
        }
        events = events.map { e in
            var e = e
            if e.tagId == id { e.tagId = nil }
            return e
        }
    }

    func moveTags(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Navigation

    func goToPreviousDay() {
        selectedDate = DateTimeUtils.addDays(selectedDate, days: -1)
    }

    func goToNextDay() {
        selectedDate = DateTimeUtils.addDays(selectedDate, days: 1)
    }

    func goToToday() {
        selectedDate = DateTimeUtils.todayStr()
    }

    // MARK: - Settings Transfer

    func exportSettingsData() -> Data? {
        let transferable = settings.strippingLocalOnly()
        let payload: [String: Any] = [
            "version": 1,
            "tags": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(tags))) ?? [],
            "settings": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(transferable))) ?? [:]
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
    }

    func importSettings(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let settingsJson = json["settings"] {
            let settingsData = try? JSONSerialization.data(withJSONObject: settingsJson)
            if let data = settingsData,
               let imported = try? JSONDecoder().decode(AppSettings.self, from: data) {
                settings = settings.merging(remote: imported)
            }
        }
        if let tagsJson = json["tags"] {
            let tagsData = try? JSONSerialization.data(withJSONObject: tagsJson)
            if let data = tagsData,
               let imported = try? JSONDecoder().decode([Tag].self, from: data) {
                tags = imported
            }
        }
    }

    // MARK: - Smart Duration Parsing

    /// Parses "task name 30" into (name: "task name", duration: 30, tagId: nil).
    /// Also supports tag suffix: "task name 30 [TagName]".
    private func parseSmartDuration(_ line: String, defaultDuration: Int) -> (name: String, duration: Int, tagId: Int?) {
        var text = line
        var tagId: Int?

        // Check for [TagName] suffix
        if let bracketRange = text.range(of: #"\[(.+?)\]$"#, options: .regularExpression) {
            let tagName = String(text[bracketRange]).dropFirst().dropLast()
            tagId = tags.first(where: { $0.name.caseInsensitiveCompare(String(tagName)) == .orderedSame })?.id
            text = String(text[text.startIndex..<bracketRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // Check for trailing number (duration)
        let parts = text.split(separator: " ")
        if parts.count > 1, let dur = Int(parts.last!) {
            let name = parts.dropLast().joined(separator: " ")
            return (name: name, duration: dur, tagId: tagId)
        }

        return (name: text, duration: defaultDuration, tagId: tagId)
    }

    // MARK: - Helpers

    func tagForId(_ id: Int?) -> Tag? {
        guard let id = id else { return nil }
        return tags.first(where: { $0.id == id })
    }

    func colorForTag(_ tagId: Int?, defaultColor: String) -> String {
        tagForId(tagId)?.color ?? defaultColor
    }

    // MARK: - Sync Push Scheduling

    private func scheduleSyncPush() {
        guard syncEnabled && !suppressingPush else { return }
        syncPushTask?.cancel()
        syncPushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.doPush()
        }
    }

    @MainActor
    func doPush() async {
        guard syncEnabled, !syncPat.isEmpty, !syncGistId.isEmpty else { return }
        syncStatus = .syncing
        do {
            let payload = SyncPayload(
                tasks: tasks,
                events: events,
                tags: tags,
                settings: settings.strippingLocalOnly(),
                activeTaskId: activeTaskId,
                pushedAt: ISO8601DateFormatter().string(from: Date())
            )
            try await SyncService.pushToGist(pat: syncPat, gistId: syncGistId, payload: payload)
            syncStatus = .idle
            lastSynced = Date()
            syncError = nil
        } catch {
            syncStatus = .error
            syncError = error.localizedDescription
        }
    }

    @MainActor
    func doPull() async {
        guard syncEnabled, !syncPat.isEmpty, !syncGistId.isEmpty else { return }
        syncStatus = .syncing
        do {
            let remote = try await SyncService.pullFromGist(pat: syncPat, gistId: syncGistId)
            // Apply remote data, suppressing push
            suppressingPush = true
            tasks = remote.tasks
            events = remote.events
            tags = remote.tags
            settings = settings.merging(remote: remote.settings)
            if let remoteActive = remote.activeTaskId,
               let task = remote.tasks.first(where: { $0.id == remoteActive && !$0.completed }),
               let startedAt = task.startedAtMin {
                let now = DateTimeUtils.currentTimeMinutes() + timeOffset
                let gap = (task.pauseEvents ?? []).reduce(0) { sum, pe in
                    sum + ((pe.end ?? now) - pe.start)
                }
                let elapsed = max(0, now - startedAt - gap)
                activeTaskId = remoteActive
                taskStartTime = Date().addingTimeInterval(-Double(elapsed) * 60)
                elapsedMinutes = elapsed
            } else {
                activeTaskId = nil
                taskStartTime = nil
                elapsedMinutes = 0
            }
            suppressingPush = false
            syncStatus = .idle
            lastSynced = Date()
            syncError = nil
        } catch {
            suppressingPush = false
            syncStatus = .error
            syncError = error.localizedDescription
        }
    }
}
