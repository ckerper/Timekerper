import Foundation

struct SyncPayload: Codable, Sendable {
    var version: Int = 1
    var tasks: [TaskItem]
    var events: [EventItem]
    var tags: [Tag]
    var settings: AppSettings
    var activeTaskId: Int?
    var pushedAt: String    // ISO 8601 timestamp
}
