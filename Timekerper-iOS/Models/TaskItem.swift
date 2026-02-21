import Foundation

struct WorkSegment: Codable, Equatable, Sendable {
    var start: Int
    var end: Int
    var date: String
}

struct PauseEvent: Codable, Equatable, Sendable {
    var start: Int
    var end: Int?
    var date: String
}

struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var duration: Int
    var adjustedDuration: Int?
    var completed: Bool
    var tagId: Int?
    var pausedElapsed: Int
    var startedAtMin: Int?
    var startedAtDate: String?
    var pausedAtMin: Int?
    var pauseGapMinutes: Int?
    var workSegments: [WorkSegment]?
    var pauseEvents: [PauseEvent]?
    var actualDuration: Int?

    var effectiveDuration: Int {
        adjustedDuration ?? duration
    }

    static func blank(id: Int, name: String, duration: Int, tagId: Int?) -> TaskItem {
        TaskItem(
            id: id,
            name: name,
            duration: duration,
            adjustedDuration: nil,
            completed: false,
            tagId: tagId,
            pausedElapsed: 0,
            startedAtMin: nil,
            startedAtDate: nil,
            pausedAtMin: nil,
            pauseGapMinutes: nil,
            workSegments: nil,
            pauseEvents: nil,
            actualDuration: nil
        )
    }
}
