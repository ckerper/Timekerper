import Foundation

struct SyncPayload: Codable, Sendable {
    var version: Int = 1
    var tasks: [TaskItem]
    var events: [EventItem]
    var tags: [Tag]
    var settings: AppSettings
    var activeTaskId: Int?
    var pushedAt: String    // ISO 8601 timestamp

    init(tasks: [TaskItem], events: [EventItem], tags: [Tag],
         settings: AppSettings, activeTaskId: Int?, pushedAt: String) {
        self.tasks = tasks
        self.events = events
        self.tags = tags
        self.settings = settings
        self.activeTaskId = activeTaskId
        self.pushedAt = pushedAt
    }

    // Custom decoder: handle missing/optional fields from web payload
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        events = try c.decodeIfPresent([EventItem].self, forKey: .events) ?? []
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        activeTaskId = try c.decodeIfPresent(Int.self, forKey: .activeTaskId)
        pushedAt = try c.decodeIfPresent(String.self, forKey: .pushedAt) ?? ""
    }
}
