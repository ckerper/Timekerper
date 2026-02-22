import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var workdayStart: String = "09:00"
    var workdayEnd: String = "17:00"
    var useExtendedHours: Bool = true
    var extendedStart: String = "06:00"
    var extendedEnd: String = "23:59"
    var autoStartNext: Bool = false
    var darkMode: String = "system"  // "on", "off", "system"
    var zoomLevel: Double = 1.5
    var fitMode: Bool = true
    var smartDuration: Bool = true
    var defaultTaskDuration: Int = 30
    var defaultEventDuration: Int = 60
    var defaultTaskColor: String = "#94a3b8"
    var defaultEventColor: String = "#94a3b8"
    var minFragmentMinutes: Int = 5
    var calendarFontSize: String = "medium"
    var wrapListNames: Bool = true
    var restrictTasksToWorkHours: Bool = true
    var debugMode: Bool = false
    var debugTimeOffset: Int = 0

    static let localOnlyKeys: Set<String> = [
        "zoomLevel", "fitMode", "debugMode", "debugTimeOffset", "darkMode"
    ]

    // Custom decoder: provide defaults for any missing keys (especially local-only
    // keys stripped from the sync payload, and web-only keys like ics* settings)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workdayStart = try c.decodeIfPresent(String.self, forKey: .workdayStart) ?? "09:00"
        let rawWorkdayEnd = try c.decodeIfPresent(String.self, forKey: .workdayEnd) ?? "17:00"
        workdayEnd = rawWorkdayEnd == "00:00" ? "23:59" : rawWorkdayEnd
        useExtendedHours = try c.decodeIfPresent(Bool.self, forKey: .useExtendedHours) ?? true
        extendedStart = try c.decodeIfPresent(String.self, forKey: .extendedStart) ?? "06:00"
        let rawExtendedEnd = try c.decodeIfPresent(String.self, forKey: .extendedEnd) ?? "23:59"
        extendedEnd = rawExtendedEnd == "00:00" ? "23:59" : rawExtendedEnd
        autoStartNext = try c.decodeIfPresent(Bool.self, forKey: .autoStartNext) ?? false
        // Migration: old data stores Bool, new data stores String
        if let str = try? c.decodeIfPresent(String.self, forKey: .darkMode) {
            darkMode = str
        } else if let oldBool = try? c.decodeIfPresent(Bool.self, forKey: .darkMode) {
            darkMode = oldBool ? "on" : "system"
        } else {
            darkMode = "system"
        }
        zoomLevel = try c.decodeIfPresent(Double.self, forKey: .zoomLevel) ?? 1.5
        fitMode = try c.decodeIfPresent(Bool.self, forKey: .fitMode) ?? true
        smartDuration = try c.decodeIfPresent(Bool.self, forKey: .smartDuration) ?? true
        defaultTaskDuration = try c.decodeIfPresent(Int.self, forKey: .defaultTaskDuration) ?? 30
        defaultEventDuration = try c.decodeIfPresent(Int.self, forKey: .defaultEventDuration) ?? 60
        defaultTaskColor = try c.decodeIfPresent(String.self, forKey: .defaultTaskColor) ?? "#94a3b8"
        defaultEventColor = try c.decodeIfPresent(String.self, forKey: .defaultEventColor) ?? "#94a3b8"
        minFragmentMinutes = try c.decodeIfPresent(Int.self, forKey: .minFragmentMinutes) ?? 5
        calendarFontSize = try c.decodeIfPresent(String.self, forKey: .calendarFontSize) ?? "medium"
        wrapListNames = try c.decodeIfPresent(Bool.self, forKey: .wrapListNames) ?? true
        restrictTasksToWorkHours = try c.decodeIfPresent(Bool.self, forKey: .restrictTasksToWorkHours) ?? true
        debugMode = try c.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        debugTimeOffset = try c.decodeIfPresent(Int.self, forKey: .debugTimeOffset) ?? 0
    }

    init() {}

    /// Extended start clamped to always be at or before workday start.
    var effectiveExtendedStart: String {
        let ext = DateTimeUtils.timeToMinutes(extendedStart)
        let work = DateTimeUtils.timeToMinutes(workdayStart)
        return ext <= work ? extendedStart : workdayStart
    }

    /// Extended end clamped to always be at or after workday end.
    var effectiveExtendedEnd: String {
        let ext = DateTimeUtils.timeToMinutes(extendedEnd)
        let work = DateTimeUtils.timeToMinutes(workdayEnd)
        return ext >= work ? extendedEnd : workdayEnd
    }

    /// Returns a copy with local-only keys reset to defaults for sync/export.
    func strippingLocalOnly() -> AppSettings {
        var copy = self
        copy.zoomLevel = 1.5
        copy.fitMode = true
        copy.debugMode = false
        copy.debugTimeOffset = 0
        copy.darkMode = "system"
        return copy
    }

    /// Merges incoming settings, preserving local-only values from self.
    func merging(remote: AppSettings) -> AppSettings {
        var merged = remote
        merged.zoomLevel = self.zoomLevel
        merged.fitMode = self.fitMode
        merged.debugMode = self.debugMode
        merged.debugTimeOffset = self.debugTimeOffset
        merged.darkMode = self.darkMode
        return merged
    }
}

// MARK: - Defaults

let defaultSettings = AppSettings()

let defaultTags: [Tag] = [
    Tag(id: 1, name: "Epic Medical Center", color: "#ef4444"),
    Tag(id: 2, name: "Verona Hospital", color: "#667eea"),
    Tag(id: 3, name: "Fitchburg Health", color: "#10b981"),
    Tag(id: 4, name: "Internal", color: "#f59e0b"),
]

let defaultTasks: [TaskItem] = [
    TaskItem.blank(id: 1, name: "Tech note review", duration: 30, tagId: nil),
    TaskItem.blank(id: 2, name: "Sherlock #12345678", duration: 75, tagId: 3),
    TaskItem.blank(id: 3, name: "Firewatch investigation", duration: 60, tagId: 1),
]

let defaultEvents: [EventItem] = [
    EventItem(id: 1, name: "EMC check-in", start: "11:00", end: "11:30", date: DateTimeUtils.todayStr(), tagId: 1),
    EventItem(id: 2, name: "Workgroup meeting", start: "13:30", end: "14:30", date: DateTimeUtils.todayStr(), tagId: 4),
    EventItem(id: 3, name: "Verona Hospital office hours", start: "15:00", end: "16:00", date: DateTimeUtils.todayStr(), tagId: 2),
]
