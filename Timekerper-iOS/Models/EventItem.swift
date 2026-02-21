import Foundation

struct EventItem: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var start: String   // "HH:MM"
    var end: String     // "HH:MM"
    var date: String    // "YYYY-MM-DD"
    var tagId: Int?
}
