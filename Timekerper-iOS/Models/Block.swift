import Foundation

enum BlockType: String, Codable, Equatable, Sendable {
    case task
    case event
    case pause
}

struct Block: Identifiable, Equatable, Sendable {
    let id: String          // unique per block (e.g. "task-123-0" or "event-456")
    let type: BlockType
    let name: String
    let start: String       // "HH:MM"
    let end: String         // "HH:MM"
    let startMin: Int
    let endMin: Int
    let isPast: Bool
    let tagId: Int?

    // Task-specific
    let taskId: Int?
    let duration: Int?      // minutes for this specific block fragment
    let isSplit: Bool
    let blockIndex: Int
    let isActive: Bool
    let isCompleted: Bool
    let continuesBefore: Bool
    let continuesAfter: Bool
    let isPausedRemaining: Bool

    // Event-specific
    let eventId: Int?
    let column: Int         // for overlapping events (0-based)
    let totalColumns: Int   // total columns in this overlap group

    static func taskBlock(
        taskId: Int, name: String, start: String, end: String,
        startMin: Int, endMin: Int, isPast: Bool, tagId: Int?,
        duration: Int, isSplit: Bool, blockIndex: Int,
        isActive: Bool, isCompleted: Bool,
        continuesBefore: Bool, continuesAfter: Bool,
        isPausedRemaining: Bool
    ) -> Block {
        Block(
            id: "task-\(taskId)-\(blockIndex)",
            type: .task, name: name, start: start, end: end,
            startMin: startMin, endMin: endMin, isPast: isPast, tagId: tagId,
            taskId: taskId, duration: duration, isSplit: isSplit, blockIndex: blockIndex,
            isActive: isActive, isCompleted: isCompleted,
            continuesBefore: continuesBefore, continuesAfter: continuesAfter,
            isPausedRemaining: isPausedRemaining,
            eventId: nil, column: 0, totalColumns: 1
        )
    }

    static func eventBlock(
        eventId: Int, name: String, start: String, end: String,
        startMin: Int, endMin: Int, isPast: Bool, tagId: Int?,
        column: Int = 0, totalColumns: Int = 1
    ) -> Block {
        Block(
            id: "event-\(eventId)",
            type: .event, name: name, start: start, end: end,
            startMin: startMin, endMin: endMin, isPast: isPast, tagId: tagId,
            taskId: nil, duration: nil, isSplit: false, blockIndex: 0,
            isActive: false, isCompleted: false,
            continuesBefore: false, continuesAfter: false,
            isPausedRemaining: false,
            eventId: eventId, column: column, totalColumns: totalColumns
        )
    }

    static func pauseBlock(
        taskId: Int, start: String, end: String,
        startMin: Int, endMin: Int, isPast: Bool
    ) -> Block {
        Block(
            id: "pause-\(taskId)-\(startMin)",
            type: .pause, name: "Paused", start: start, end: end,
            startMin: startMin, endMin: endMin, isPast: isPast, tagId: nil,
            taskId: taskId, duration: nil, isSplit: false, blockIndex: 0,
            isActive: false, isCompleted: false,
            continuesBefore: false, continuesAfter: false,
            isPausedRemaining: false,
            eventId: nil, column: 0, totalColumns: 1
        )
    }
}
