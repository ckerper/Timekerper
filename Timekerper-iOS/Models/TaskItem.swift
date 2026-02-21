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

    // Custom decoder: provide defaults for fields that may be missing from web JSON
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        duration = try c.decode(Int.self, forKey: .duration)
        adjustedDuration = try c.decodeIfPresent(Int.self, forKey: .adjustedDuration)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        tagId = try c.decodeIfPresent(Int.self, forKey: .tagId)
        pausedElapsed = try c.decodeIfPresent(Int.self, forKey: .pausedElapsed) ?? 0
        startedAtMin = try c.decodeIfPresent(Int.self, forKey: .startedAtMin)
        startedAtDate = try c.decodeIfPresent(String.self, forKey: .startedAtDate)
        pausedAtMin = try c.decodeIfPresent(Int.self, forKey: .pausedAtMin)
        pauseGapMinutes = try c.decodeIfPresent(Int.self, forKey: .pauseGapMinutes)
        workSegments = try c.decodeIfPresent([WorkSegment].self, forKey: .workSegments)
        pauseEvents = try c.decodeIfPresent([PauseEvent].self, forKey: .pauseEvents)
        actualDuration = try c.decodeIfPresent(Int.self, forKey: .actualDuration)
    }

    init(
        id: Int, name: String, duration: Int, adjustedDuration: Int?,
        completed: Bool, tagId: Int?, pausedElapsed: Int,
        startedAtMin: Int?, startedAtDate: String?, pausedAtMin: Int?,
        pauseGapMinutes: Int?, workSegments: [WorkSegment]?,
        pauseEvents: [PauseEvent]?, actualDuration: Int?
    ) {
        self.id = id; self.name = name; self.duration = duration
        self.adjustedDuration = adjustedDuration; self.completed = completed
        self.tagId = tagId; self.pausedElapsed = pausedElapsed
        self.startedAtMin = startedAtMin; self.startedAtDate = startedAtDate
        self.pausedAtMin = pausedAtMin; self.pauseGapMinutes = pauseGapMinutes
        self.workSegments = workSegments; self.pauseEvents = pauseEvents
        self.actualDuration = actualDuration
    }

    static func blank(id: Int, name: String, duration: Int, tagId: Int?) -> TaskItem {
        TaskItem(
            id: id, name: name, duration: duration, adjustedDuration: nil,
            completed: false, tagId: tagId, pausedElapsed: 0,
            startedAtMin: nil, startedAtDate: nil, pausedAtMin: nil,
            pauseGapMinutes: nil, workSegments: nil, pauseEvents: nil,
            actualDuration: nil
        )
    }
}
