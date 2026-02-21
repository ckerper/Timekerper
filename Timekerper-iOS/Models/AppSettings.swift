import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var workdayStart: String = "09:00"
    var workdayEnd: String = "17:00"
    var useExtendedHours: Bool = true
    var extendedStart: String = "06:00"
    var extendedEnd: String = "23:59"
    var autoStartNext: Bool = false
    var darkMode: Bool = false
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
        "zoomLevel", "fitMode", "debugMode", "debugTimeOffset"
    ]

    /// Returns a copy with local-only keys reset to defaults for sync/export.
    func strippingLocalOnly() -> AppSettings {
        var copy = self
        copy.zoomLevel = 1.5
        copy.fitMode = true
        copy.debugMode = false
        copy.debugTimeOffset = 0
        return copy
    }

    /// Merges incoming settings, preserving local-only values from self.
    func merging(remote: AppSettings) -> AppSettings {
        var merged = remote
        merged.zoomLevel = self.zoomLevel
        merged.fitMode = self.fitMode
        merged.debugMode = self.debugMode
        merged.debugTimeOffset = self.debugTimeOffset
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
