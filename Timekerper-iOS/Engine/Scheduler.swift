import Foundation

// The scheduling engine. All functions are pure and stateless.
// Direct port of scheduler.js — same algorithm, same behavior.

enum Scheduler {

    // MARK: - Available Time Computation

    /// Compute total available work minutes on a given day (gaps between blocking ranges).
    private static func computeAvailableTime(
        events: [EventItem],
        date: String,
        startMin: Int,
        endMin: Int,
        additionalBlocking: [(start: Int, end: Int)]
    ) -> Int {
        let dayEvents = events
            .filter { $0.date == date }
            .map { (
                start: max(DateTimeUtils.timeToMinutes($0.start), startMin),
                end: min(DateTimeUtils.timeToMinutes($0.end), endMin)
            )}
            .filter { $0.end > $0.start }

        let extra = additionalBlocking
            .map { (start: max($0.start, startMin), end: min($0.end, endMin)) }
            .filter { $0.end > $0.start }

        let allRanges = (dayEvents + extra).sorted { $0.start < $1.start }

        var available = 0
        var cursor = startMin
        for r in allRanges {
            if r.start > cursor {
                available += r.start - cursor
            }
            cursor = max(cursor, r.end)
        }
        if cursor < endMin {
            available += endMin - cursor
        }
        return available
    }

    // MARK: - Overlapping Event Columns

    /// Assign column positions to overlapping events (greedy algorithm).
    private static func assignEventColumns(_ eventBlocks: inout [Block]) {
        guard eventBlocks.count > 1 else { return }

        // Group overlapping events
        var groups: [[Int]] = []  // indices into eventBlocks

        for i in 0..<eventBlocks.count {
            var placed = false
            for g in 0..<groups.count {
                let groupEnd = groups[g].map { eventBlocks[$0].endMin }.max() ?? 0
                if eventBlocks[i].startMin < groupEnd {
                    groups[g].append(i)
                    placed = true
                    break
                }
            }
            if !placed {
                groups.append([i])
            }
        }

        for group in groups {
            guard group.count > 1 else { continue }
            let totalCols = group.count
            for (col, idx) in group.enumerated() {
                let b = eventBlocks[idx]
                eventBlocks[idx] = Block.eventBlock(
                    eventId: b.eventId ?? 0,
                    name: b.name,
                    start: b.start,
                    end: b.end,
                    startMin: b.startMin,
                    endMin: b.endMin,
                    isPast: b.isPast,
                    tagId: b.tagId,
                    column: col,
                    totalColumns: totalCols
                )
            }
        }
    }

    // MARK: - Main Scheduling Function

    /// The core scheduling function. Takes the full app state and returns a flat sorted array
    /// of positioned blocks ready for calendar rendering.
    ///
    /// Direct port of scheduleDay() from scheduler.js.
    static func scheduleDay(
        tasks: [TaskItem],
        events: [EventItem],
        settings: AppSettings,
        activeTaskId: Int?,
        totalElapsed: Int,
        selectedDate: String
    ) -> [Block] {
        let extStartMin = DateTimeUtils.timeToMinutes(settings.extendedStart)
        let extEndMin = DateTimeUtils.timeToMinutes(settings.extendedEnd)
        let workdayStartMin = DateTimeUtils.timeToMinutes(settings.workdayStart)
        let workdayEndMin = DateTimeUtils.timeToMinutes(settings.workdayEnd)
        let taskStartMin = !settings.specifyWorkingHours ? 0
            : settings.restrictTasksToWorkHours ? workdayStartMin : extStartMin
        let taskEndMin = !settings.specifyWorkingHours ? 1439
            : settings.restrictTasksToWorkHours ? workdayEndMin : extEndMin
        let debugOffset = settings.debugMode ? settings.debugTimeOffset : 0
        let currentTimeMin = DateTimeUtils.currentTimeMinutes() + debugOffset

        let todayStr = DateTimeUtils.todayStr()
        let isToday = selectedDate == todayStr
        let isFuture = selectedDate > todayStr

        // Build event blocks for display (filtered by selected date)
        var allEventBlocks = events
            .filter { $0.date == selectedDate }
            .map { e -> Block in
                let sMin = DateTimeUtils.timeToMinutes(e.start)
                let eMin = DateTimeUtils.timeToMinutes(e.end)
                let isPast = isToday ? eMin <= currentTimeMin : !isFuture
                return Block.eventBlock(
                    eventId: e.id,
                    name: e.name,
                    start: e.start,
                    end: e.end,
                    startMin: sMin,
                    endMin: eMin,
                    isPast: isPast,
                    tagId: e.tagId
                )
            }
            .filter { $0.startMin < extEndMin && $0.endMin > extStartMin }
            .sorted { $0.startMin < $1.startMin }

        // Assign columns for overlapping events
        assignEventColumns(&allEventBlocks)

        var taskBlocks: [Block] = []
        var pauseDisplayBlocks: [Block] = []

        // Schedule incomplete tasks on today and future days
        if isToday || isFuture {
            let incompleteTasks = tasks.filter { !$0.completed }
            let firstTask = incompleteTasks.first
            let firstTaskIsPaused = isToday && (firstTask?.pauseEvents?.contains(where: { $0.end == nil }) ?? false)

            // Collect pause events from the first started task as blocking ranges (today only)
            struct MinRange {
                var startMin: Int
                var endMin: Int
            }
            var pauseBlockingRanges: [MinRange] = []

            if isToday, let ft = firstTask, ft.startedAtMin != nil, let pauseEvents = ft.pauseEvents, !pauseEvents.isEmpty {
                for pe in pauseEvents {
                    let peStart = pe.start
                    let peEnd = pe.end ?? currentTimeMin  // null end = currently paused (growing)
                    if peEnd > peStart {
                        pauseBlockingRanges.append(MinRange(startMin: peStart, endMin: peEnd))
                        // Create display block (clamped to visible range)
                        if peEnd > extStartMin && peStart < extEndMin {
                            let s = max(peStart, extStartMin)
                            let e = min(peEnd, extEndMin)
                            pauseDisplayBlocks.append(Block.pauseBlock(
                                taskId: ft.id,
                                start: DateTimeUtils.minutesToTime(s),
                                end: DateTimeUtils.minutesToTime(e),
                                startMin: s,
                                endMin: e,
                                isPast: peEnd <= currentTimeMin
                            ))
                        }
                    }
                }
            }

            // Determine where task scheduling begins
            let scheduleStartMin: Int
            if isFuture {
                scheduleStartMin = workdayStartMin
            } else if let ft = firstTask, ft.startedAtMin != nil {
                scheduleStartMin = max(taskStartMin, ft.startedAtMin!)
            } else if activeTaskId != nil {
                scheduleStartMin = max(taskStartMin, currentTimeMin - totalElapsed)
            } else {
                scheduleStartMin = max(workdayStartMin, min(currentTimeMin, taskEndMin))
            }

            // For future days: compute how many task-minutes are absorbed by prior days
            var minutesToSkip = 0
            if isFuture {
                // Helper: get additional blocking ranges for a date
                func getAdditionalBlocking(for date: String) -> [(start: Int, end: Int)] {
                    var ranges: [(start: Int, end: Int)] = []
                    for task in tasks {
                        guard task.completed, let segments = task.workSegments, !segments.isEmpty else { continue }
                        for seg in segments {
                            if seg.date == date {
                                ranges.append((start: seg.start, end: seg.end))
                            }
                        }
                    }
                    // Pauses only apply to today (from the first incomplete task)
                    if date == todayStr, let ft = firstTask, ft.startedAtMin != nil,
                       let pauseEvents = ft.pauseEvents, !pauseEvents.isEmpty {
                        for pe in pauseEvents {
                            let peEnd = pe.end ?? currentTimeMin
                            if peEnd > pe.start {
                                ranges.append((start: pe.start, end: peEnd))
                            }
                        }
                    }
                    return ranges
                }

                // Today's remaining capacity
                let todayStart = max(taskStartMin, min(currentTimeMin, taskEndMin))
                if todayStart < taskEndMin {
                    minutesToSkip += computeAvailableTime(
                        events: events, date: todayStr,
                        startMin: todayStart, endMin: taskEndMin,
                        additionalBlocking: getAdditionalBlocking(for: todayStr)
                    )
                }
                // Intermediate future days
                var d = DateTimeUtils.addDays(todayStr, days: 1)
                while d < selectedDate {
                    minutesToSkip += computeAvailableTime(
                        events: events, date: d,
                        startMin: workdayStartMin, endMin: taskEndMin,
                        additionalBlocking: getAdditionalBlocking(for: d)
                    )
                    d = DateTimeUtils.addDays(d, days: 1)
                }
            }

            // Completed task segments as blocking ranges
            var completedSegmentRanges: [MinRange] = []
            for task in tasks {
                guard task.completed, let segments = task.workSegments, !segments.isEmpty else { continue }
                for seg in segments {
                    guard seg.date == selectedDate else { continue }
                    let s = max(seg.start, scheduleStartMin)
                    let e = min(seg.end, extEndMin)
                    if e > s {
                        completedSegmentRanges.append(MinRange(startMin: s, endMin: e))
                    }
                }
            }

            // Combine all blocking ranges
            var allBlocking: [MinRange] = []
            allBlocking += allEventBlocks
                .filter { $0.endMin > scheduleStartMin }
                .map { MinRange(startMin: $0.startMin, endMin: $0.endMin) }
            allBlocking += pauseBlockingRanges.filter { $0.endMin > scheduleStartMin }
            allBlocking += completedSegmentRanges.filter { $0.endMin > scheduleStartMin }
            allBlocking.sort { $0.startMin < $1.startMin }

            // Merge overlapping blocking ranges
            var mergedRanges: [(start: Int, end: Int)] = []
            for e in allBlocking {
                let start = max(e.startMin, scheduleStartMin)
                if mergedRanges.isEmpty || start > mergedRanges[mergedRanges.count - 1].end {
                    mergedRanges.append((start: start, end: e.endMin))
                } else {
                    mergedRanges[mergedRanges.count - 1].end = max(
                        mergedRanges[mergedRanges.count - 1].end,
                        e.endMin
                    )
                }
            }

            // Build available time slots (gaps between blocking ranges)
            var availableSlots: [(start: Int, end: Int)] = []
            var cursor = scheduleStartMin
            for range in mergedRanges {
                if range.start > cursor {
                    availableSlots.append((start: cursor, end: range.start))
                }
                cursor = max(cursor, range.end)
            }
            if cursor < taskEndMin {
                availableSlots.append((start: cursor, end: taskEndMin))
            }

            // Schedule incomplete tasks into available slots
            var slotIdx = 0
            var slotUsed = 0
            var skipRemaining = minutesToSkip

            for task in incompleteTasks {
                let isActive = isToday && task.id == activeTaskId
                let plannedDuration = task.effectiveDuration

                // For future days: skip tasks that fit entirely on prior days
                var taskDayDuration: Int
                if isFuture && skipRemaining > 0 {
                    if skipRemaining >= plannedDuration {
                        skipRemaining -= plannedDuration
                        continue
                    }
                    taskDayDuration = plannedDuration - skipRemaining
                    skipRemaining = 0
                } else {
                    taskDayDuration = isActive
                        ? max(totalElapsed, plannedDuration)
                        : plannedDuration
                }

                var remaining = taskDayDuration
                var blockIdx = 0
                let continuesFromPrior = isFuture && taskDayDuration < plannedDuration

                while remaining > 0 && slotIdx < availableSlots.count {
                    let slot = availableSlots[slotIdx]
                    let start = slot.start + slotUsed
                    let slotRemaining = slot.end - start

                    if slotRemaining <= 0 {
                        slotIdx += 1
                        slotUsed = 0
                        continue
                    }

                    let dur = min(remaining, slotRemaining)
                    let minFrag = max(settings.minFragmentMinutes, 1)

                    if dur < minFrag && remaining > slotRemaining {
                        slotIdx += 1
                        slotUsed = 0
                        continue
                    }

                    let blockIsPast = isToday && (start + dur) <= currentTimeMin

                    taskBlocks.append(Block.taskBlock(
                        taskId: task.id,
                        name: task.name,
                        start: DateTimeUtils.minutesToTime(start),
                        end: DateTimeUtils.minutesToTime(start + dur),
                        startMin: start,
                        endMin: start + dur,
                        isPast: blockIsPast,
                        tagId: task.tagId,
                        duration: dur,
                        isSplit: taskDayDuration > dur || blockIdx > 0 || continuesFromPrior,
                        blockIndex: blockIdx,
                        isActive: isActive,
                        isCompleted: false,
                        continuesBefore: blockIdx > 0 || continuesFromPrior,
                        continuesAfter: remaining - dur > 0,
                        isPausedRemaining: firstTaskIsPaused && task.id == firstTask?.id && !blockIsPast
                    ))

                    remaining -= dur
                    slotUsed += dur
                    blockIdx += 1

                    if slotUsed >= slot.end - slot.start {
                        slotIdx += 1
                        slotUsed = 0
                    }
                }
            }
        }

        // Add completed tasks that were actually worked on (filtered by date)
        let completedTasks = tasks.filter { $0.completed && $0.startedAtMin != nil && ($0.actualDuration ?? 0) > 0 }
        for task in completedTasks {
            let segments = task.workSegments ?? []
            if !segments.isEmpty {
                let dateSegments = segments.filter { $0.date == selectedDate }
                for (i, seg) in dateSegments.enumerated() {
                    let segStart = max(seg.start, extStartMin)
                    let segEnd = min(seg.end, extEndMin)
                    if segEnd > segStart {
                        taskBlocks.append(Block.taskBlock(
                            taskId: task.id,
                            name: task.name,
                            start: DateTimeUtils.minutesToTime(segStart),
                            end: DateTimeUtils.minutesToTime(segEnd),
                            startMin: segStart,
                            endMin: segEnd,
                            isPast: true,
                            tagId: task.tagId,
                            duration: segEnd - segStart,
                            isSplit: dateSegments.count > 1,
                            blockIndex: i,
                            isActive: false,
                            isCompleted: true,
                            continuesBefore: i > 0,
                            continuesAfter: i < dateSegments.count - 1,
                            isPausedRemaining: false
                        ))
                    }
                }
            } else if isToday, let startedAt = task.startedAtMin, let actual = task.actualDuration {
                // Legacy fallback: single block (only on today)
                let start = max(startedAt, extStartMin)
                let end = min(startedAt + actual, extEndMin)
                if end > start {
                    taskBlocks.append(Block.taskBlock(
                        taskId: task.id,
                        name: task.name,
                        start: DateTimeUtils.minutesToTime(start),
                        end: DateTimeUtils.minutesToTime(end),
                        startMin: start,
                        endMin: end,
                        isPast: true,
                        tagId: task.tagId,
                        duration: end - start,
                        isSplit: false,
                        blockIndex: 0,
                        isActive: false,
                        isCompleted: true,
                        continuesBefore: false,
                        continuesAfter: false,
                        isPausedRemaining: false
                    ))
                }
            }
        }

        // Combine events, tasks, and pause display blocks, sorted by start time
        let isToday_ = isToday  // avoid capture ambiguity
        return (allEventBlocks + taskBlocks + pauseDisplayBlocks)
            .sorted { $0.startMin < $1.startMin }
    }
}
