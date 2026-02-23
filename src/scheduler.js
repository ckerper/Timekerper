// Time helper functions

export function timeToMinutes(timeStr) {
  const [hours, minutes] = timeStr.split(':').map(Number)
  return hours * 60 + minutes
}

export function minutesToTime(minutes) {
  const hours = Math.floor(minutes / 60)
  const mins = minutes % 60
  return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`
}

export function formatTime(timeStr) {
  const [hours, minutes] = timeStr.split(':').map(Number)
  const period = hours >= 12 ? 'PM' : 'AM'
  const displayHours = hours > 12 ? hours - 12 : hours === 0 ? 12 : hours
  return `${displayHours}:${minutes.toString().padStart(2, '0')} ${period}`
}

export function formatElapsed(minutes) {
  if (minutes >= 60) {
    const h = Math.floor(minutes / 60)
    const m = minutes % 60
    return m > 0 ? `${h}h ${m}m` : `${h}h`
  }
  return `${minutes}m`
}

export function formatBlockTimeRange(startStr, endStr, isTask) {
  const [startH, startM] = startStr.split(':').map(Number)
  const [endH, endM] = endStr.split(':').map(Number)
  const startPeriod = startH >= 12 ? 'pm' : 'am'
  const endPeriod = endH >= 12 ? 'pm' : 'am'
  const startDisplay = startH > 12 ? startH - 12 : startH === 0 ? 12 : startH
  const endDisplay = endH > 12 ? endH - 12 : endH === 0 ? 12 : endH

  const startTime = `${startDisplay}:${startM.toString().padStart(2, '0')}`
  const endTime = `${endDisplay}:${endM.toString().padStart(2, '0')}${endPeriod}`

  const range = startPeriod === endPeriod
    ? `${startTime}\u2013${endTime}`
    : `${startTime}${startPeriod}\u2013${endTime}`

  return isTask ? `(${range})` : range
}

export function getCurrentTimeMinutes() {
  const now = new Date()
  return now.getHours() * 60 + now.getMinutes()
}

export function getTodayStr() {
  const d = new Date()
  return d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0')
}

export function addDays(dateStr, days) {
  const d = new Date(dateStr + 'T12:00:00')
  d.setDate(d.getDate() + days)
  return d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0')
}

export function formatDateHeader(dateStr) {
  const d = new Date(dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', {
    weekday: 'long', month: 'long', day: 'numeric'
  })
}

export function formatShortDateHeader(dateStr) {
  const d = new Date(dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', { weekday: 'short', day: 'numeric' })
}

export function formatDateHeaderCompact(dateStr) {
  const d = new Date(dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric'
  })
}

// ─── ICS Parser ──────────────────────────────────────────────────────────────

// Determine the "busy status" of an ICS event from its properties.
// Priority: X-MICROSOFT-CDO-BUSYSTATUS > TRANSP + PARTSTAT > default BUSY
function getIcsEventStatus(props) {
  // Microsoft-specific field is most reliable for Outlook exports
  const msStatus = props['X-MICROSOFT-CDO-BUSYSTATUS']
  if (msStatus) return msStatus.toUpperCase()

  // PARTSTAT on the attendee line (often embedded in the main props for single-user exports)
  const partstat = props['PARTSTAT']
  if (partstat === 'DECLINED') return 'FREE'
  if (partstat === 'TENTATIVE') return 'TENTATIVE'

  // TRANSP: TRANSPARENT = free, OPAQUE = busy (default)
  if (props['TRANSP'] === 'TRANSPARENT') return 'FREE'

  return null
}

// Windows timezone name → IANA timezone mapping (Outlook exports Windows names)
const WINDOWS_TO_IANA = {
  'Eastern Standard Time': 'America/New_York',
  'Central Standard Time': 'America/Chicago',
  'Mountain Standard Time': 'America/Denver',
  'Pacific Standard Time': 'America/Los_Angeles',
  'US Mountain Standard Time': 'America/Phoenix',
  'US Eastern Standard Time': 'America/Indianapolis',
  'Alaska Standard Time': 'America/Anchorage',
  'Hawaiian Standard Time': 'Pacific/Honolulu',
  'Atlantic Standard Time': 'America/Halifax',
  'Newfoundland Standard Time': 'America/St_Johns',
  'GMT Standard Time': 'Europe/London',
  'Greenwich Standard Time': 'Atlantic/Reykjavik',
  'W. Europe Standard Time': 'Europe/Berlin',
  'Central European Standard Time': 'Europe/Warsaw',
  'Romance Standard Time': 'Europe/Paris',
  'Central Europe Standard Time': 'Europe/Budapest',
  'E. Europe Standard Time': 'Europe/Chisinau',
  'FLE Standard Time': 'Europe/Kiev',
  'GTB Standard Time': 'Europe/Bucharest',
  'Russian Standard Time': 'Europe/Moscow',
  'Israel Standard Time': 'Asia/Jerusalem',
  'South Africa Standard Time': 'Africa/Johannesburg',
  'India Standard Time': 'Asia/Kolkata',
  'China Standard Time': 'Asia/Shanghai',
  'Tokyo Standard Time': 'Asia/Tokyo',
  'Korea Standard Time': 'Asia/Seoul',
  'AUS Eastern Standard Time': 'Australia/Sydney',
  'New Zealand Standard Time': 'Pacific/Auckland',
  'UTC': 'UTC',
}

// Interpret datetime components as being in a specific IANA timezone, return a Date
function dateInTimezone(y, mo, d, h, mi, s, timeZone) {
  const utcGuess = Date.UTC(y, mo - 1, d, h, mi, s)
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone, year: 'numeric', month: 'numeric', day: 'numeric',
    hour: 'numeric', minute: 'numeric', second: 'numeric', hour12: false,
  }).formatToParts(new Date(utcGuess))
  const p = (type) => { const v = parts.find(x => x.type === type); return v ? +v.value : 0 }
  const hr = p('hour') === 24 ? 0 : p('hour')
  const tzAsUtc = Date.UTC(p('year'), p('month') - 1, p('day'), hr, p('minute'), p('second'))
  return new Date(utcGuess - (tzAsUtc - utcGuess))
}

// Parse an ICS datetime string (e.g. "20260210T143000", "20260210T143000Z",
// or "TZID=Eastern Standard Time:20260210T143000")
// Returns a Date object. Handles UTC (Z suffix), explicit TZID, and naive (local time).
function parseIcsDatetime(dtStr) {
  if (!dtStr) return null
  // Extract TZID and bare datetime
  let tzid = null
  let bare = dtStr
  if (dtStr.startsWith('TZID=')) {
    const colonIdx = dtStr.indexOf(':', 5)
    if (colonIdx > 0) {
      tzid = dtStr.slice(5, colonIdx).replace(/^"|"$/g, '')
      bare = dtStr.slice(colonIdx + 1)
    }
  } else if (dtStr.includes(':')) {
    bare = dtStr.split(':').pop()
  }
  // Format: YYYYMMDDTHHMMSS or YYYYMMDD
  const match = bare.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?/)
  if (!match) return null
  const [, y, mo, d, h, mi, s] = match
  if (bare.endsWith('Z')) {
    return new Date(Date.UTC(+y, +mo - 1, +d, +(h || 0), +(mi || 0), +(s || 0)))
  }
  if (tzid) {
    const ianaZone = WINDOWS_TO_IANA[tzid] || tzid
    try {
      return dateInTimezone(+y, +mo, +d, +(h || 0), +(mi || 0), +(s || 0), ianaZone)
    } catch { /* unknown timezone — fall through to local time */ }
  }
  return new Date(+y, +mo - 1, +d, +(h || 0), +(mi || 0), +(s || 0))
}

// Parse an ICS file string and return an array of event objects:
// { name, date, start, end, status, isMeeting, categories }
export function parseIcsFile(icsText) {
  const results = []
  // Unfold continuation lines (RFC 5545: lines starting with space/tab are continuations)
  // Handle both \r\n and bare \n line endings
  const unfolded = icsText.replace(/\r?\n[ \t]/g, '').replace(/\r/g, '')
  const lines = unfolded.split('\n')

  let inEvent = false
  let props = {}
  let attendeeCount = 0
  let categories = []

  for (const line of lines) {
    const trimmed = line.trim()
    if (trimmed === 'BEGIN:VEVENT') {
      inEvent = true
      props = {}
      attendeeCount = 0
      categories = []
      continue
    }
    if (trimmed === 'END:VEVENT') {
      inEvent = false
      // Extract what we need
      const summary = props['SUMMARY'] || 'Imported Event'
      const dtStart = parseIcsDatetime(props['DTSTART'])
      const dtEnd = parseIcsDatetime(props['DTEND'])
      if (dtStart && dtEnd) {
        const status = getIcsEventStatus(props)
        const date = dtStart.getFullYear() + '-' +
          String(dtStart.getMonth() + 1).padStart(2, '0') + '-' +
          String(dtStart.getDate()).padStart(2, '0')
        const start = String(dtStart.getHours()).padStart(2, '0') + ':' +
          String(dtStart.getMinutes()).padStart(2, '0')
        const end = String(dtEnd.getHours()).padStart(2, '0') + ':' +
          String(dtEnd.getMinutes()).padStart(2, '0')
        const uid = props['UID'] || null
        const recurrenceId = props['RECURRENCE-ID'] || null
        // RECURRENCE-ID exceptions: compute the original date being replaced
        let replacesDate = null
        if (recurrenceId && uid) {
          const recDt = parseIcsDatetime(recurrenceId)
          if (recDt) {
            replacesDate = recDt.getFullYear() + '-' +
              String(recDt.getMonth() + 1).padStart(2, '0') + '-' +
              String(recDt.getDate()).padStart(2, '0')
          }
        }
        results.push({ name: summary, date, start, end, status, isMeeting: attendeeCount > 0, categories, uid, replacesDate })
      }
      continue
    }
    if (inEvent) {
      // Parse property: NAME;PARAMS:VALUE or NAME:VALUE
      const colonIdx = trimmed.indexOf(':')
      if (colonIdx === -1) continue
      const keyPart = trimmed.substring(0, colonIdx)
      const value = trimmed.substring(colonIdx + 1)
      // The key may have parameters like DTSTART;TZID=..., extract the base name
      const baseName = keyPart.split(';')[0]
      props[baseName] = value
      // Count ATTENDEE lines (meetings have 1+, appointments have 0)
      if (baseName === 'ATTENDEE') attendeeCount++
      // Collect CATEGORIES (can be comma-separated, can appear multiple times)
      if (baseName === 'CATEGORIES') {
        categories.push(...value.split(',').map(c => c.trim()).filter(Boolean))
      }
      // Also extract inline parameters (e.g. PARTSTAT from ATTENDEE lines)
      if (keyPart.includes('PARTSTAT=')) {
        const partMatch = keyPart.match(/PARTSTAT=([^;]+)/)
        if (partMatch) props['PARTSTAT'] = partMatch[1]
      }
      // Preserve DTSTART with TZID info for parsing
      if (baseName === 'DTSTART' || baseName === 'DTEND') {
        const tzMatch = keyPart.match(/TZID=([^;:]+)/)
        if (tzMatch) props[baseName] = `TZID=${tzMatch[1]}:${value}`
      }
    }
  }

  return results
}

// Filter parsed ICS events by user's status preferences, date range,
// meetings-only toggle, and category exclusion rules.
// Also handles RECURRENCE-ID exceptions: inherits properties from parent,
// suppresses replaced base occurrences.
export function filterIcsEvents(parsedEvents, statusSettings, minDate, maxDate) {
  const statusMap = {
    'BUSY': statusSettings.icsImportBusy,
    'OOF': statusSettings.icsImportOof,
    'TENTATIVE': statusSettings.icsImportTentative,
    'FREE': statusSettings.icsImportFree,
    'WORKING-ELSEWHERE': statusSettings.icsImportWorkingElsewhere,
  }
  const categoryRules = statusSettings.icsCategoryRules || []

  // Build lookup of parent (non-exception) events by UID for property inheritance
  const parentByUid = new Map()
  for (const ev of parsedEvents) {
    if (!ev.replacesDate && ev.uid) {
      parentByUid.set(ev.uid, ev)
    }
  }

  // For RECURRENCE-ID exceptions, inherit missing properties from parent
  for (const ev of parsedEvents) {
    if (ev.replacesDate && ev.uid) {
      const parent = parentByUid.get(ev.uid)
      if (parent) {
        if (ev.name === 'Imported Event') ev.name = parent.name
        if (!ev.categories || ev.categories.length === 0) ev.categories = parent.categories
        if (!ev.isMeeting) ev.isMeeting = parent.isMeeting
        if (!ev.status) ev.status = parent.status
      } else {
        // Orphaned exception with no parent and no name — useless, mark for skip
        if (ev.name === 'Imported Event') ev._orphaned = true
      }
    }
  }

  const filtered = parsedEvents.filter(ev => {
    // Skip orphaned exceptions with no useful info
    if (ev._orphaned) return false
    // Check status filter
    const allowed = statusMap[ev.status]
    if (allowed === undefined) {
      if (!statusSettings.icsImportBusy) return false
    } else if (!allowed) {
      return false
    }
    // Check date range
    if (ev.date < minDate || ev.date > maxDate) return false
    // Meetings-only filter: skip appointments (no attendees)
    if (statusSettings.icsImportMeetingsOnly && !ev.isMeeting) return false
    // Category exclusion rules (include: false means exclude)
    if (ev.categories && ev.categories.length > 0) {
      for (const cat of ev.categories) {
        const rule = categoryRules.find(r =>
          r.include === false && r.category.toLowerCase() === cat.toLowerCase()
        )
        if (rule) return false
      }
    }
    return true
  })

  // Suppress base occurrences that have been replaced by RECURRENCE-ID exceptions
  const replacedKeys = new Set()
  for (const ev of filtered) {
    if (ev.replacesDate && ev.uid) {
      replacedKeys.add(`${ev.uid}|${ev.replacesDate}`)
    }
  }
  if (replacedKeys.size === 0) return filtered
  return filtered.filter(ev => {
    if (ev.replacesDate) return true // keep the exception itself
    if (ev.uid && replacedKeys.has(`${ev.uid}|${ev.date}`)) return false // suppress replaced occurrence
    return true
  })
}

// Compute total available work minutes on a given day (gaps between blocking ranges)
// additionalBlocking: optional array of { start, end } minute ranges (completed segments, pauses)
function computeAvailableTime(events, date, startMin, endMin, additionalBlocking, minFrag = 0) {
  const dayEvents = events
    .filter(e => e.date === date)
    .map(e => ({
      start: Math.max(timeToMinutes(e.start), startMin),
      end: Math.min(timeToMinutes(e.end), endMin)
    }))
    .filter(e => e.end > e.start)

  const extra = (additionalBlocking || [])
    .map(r => ({
      start: Math.max(r.start, startMin),
      end: Math.min(r.end, endMin)
    }))
    .filter(r => r.end > r.start)

  const allRanges = [...dayEvents, ...extra].sort((a, b) => a.start - b.start)

  let available = 0
  let cursor = startMin
  for (const r of allRanges) {
    if (r.start > cursor) {
      const gap = r.start - cursor
      if (gap >= minFrag) available += gap
    }
    cursor = Math.max(cursor, r.end)
  }
  if (cursor < endMin) {
    const gap = endMin - cursor
    if (gap >= minFrag) available += gap
  }
  return available
}

// THE SCHEDULING ENGINE
// Takes tasks, events, and settings, returns an array of positioned blocks
// for display on the calendar.
//
// Key behaviors:
// - Events are ALWAYS shown at their fixed times (including past ones)
// - Tasks are scheduled into available gaps starting from startedAtMin or "now"
// - Tasks split around events AND pauses naturally
// - Pauses are blocking events: while paused, a growing "Paused" block pushes
//   remaining work forward; on resume, pauses become fixed gaps
// - Active task expands in real-time based on elapsed time
// - Past blocks are flagged for visual dimming
export function scheduleDay(tasks, events, settings, activeTaskId, totalElapsed, selectedDate) {
  const extStartMin = timeToMinutes(settings.extendedStart)
  const extEndMin = timeToMinutes(settings.extendedEnd)
  const workdayStartMin = timeToMinutes(settings.workdayStart)
  const workdayEndMin = timeToMinutes(settings.workdayEnd)
  const taskStartMin = settings.restrictTasksToWorkHours ? workdayStartMin : extStartMin
  const taskEndMin = settings.restrictTasksToWorkHours ? workdayEndMin : extEndMin
  const debugOffset = settings.debugMode ? (settings.debugTimeOffset || 0) : 0
  const currentTimeMin = getCurrentTimeMinutes() + debugOffset

  const todayStr = getTodayStr()
  const isToday = selectedDate === todayStr
  const isFuture = selectedDate > todayStr

  // Build event blocks for display (filtered by selected date)
  const allEventBlocks = events
    .filter(e => e.date === selectedDate)
    .map(e => ({
      ...e,
      startMin: timeToMinutes(e.start),
      endMin: timeToMinutes(e.end),
      type: 'event',
      isPast: isToday ? timeToMinutes(e.end) <= currentTimeMin : !isFuture,
    }))
    .filter(e => e.startMin < extEndMin && e.endMin > extStartMin)
    .sort((a, b) => a.startMin - b.startMin)

  const taskBlocks = []
  const pauseDisplayBlocks = []

  // Schedule incomplete tasks on today and future days
  if (isToday || isFuture) {
    const incompleteTasks = tasks.filter(t => !t.completed)
    const firstTask = incompleteTasks[0]
    const firstTaskIsPaused = isToday && (firstTask?.pauseEvents?.some(pe => pe.end == null) ?? false)

    // Collect pause events from the first started task as blocking ranges (today only)
    const pauseBlockingRanges = []
    if (isToday && firstTask?.startedAtMin != null && firstTask.pauseEvents?.length > 0) {
      for (const pe of firstTask.pauseEvents) {
        const peStart = pe.start
        const peEnd = pe.end ?? currentTimeMin  // null end = currently paused (growing)
        if (peEnd > peStart) {
          pauseBlockingRanges.push({ startMin: peStart, endMin: peEnd })
          // Create display block (clamped to visible range)
          if (peEnd > extStartMin && peStart < extEndMin) {
            const s = Math.max(peStart, extStartMin)
            const e = Math.min(peEnd, extEndMin)
            pauseDisplayBlocks.push({
              startMin: s,
              endMin: e,
              start: minutesToTime(s),
              end: minutesToTime(e),
              type: 'pause',
              name: 'Paused',
              isPast: peEnd <= currentTimeMin,
            })
          }
        }
      }
    }

    // Determine where task scheduling begins
    let scheduleStartMin
    if (isFuture) {
      scheduleStartMin = taskStartMin
    } else if (firstTask?.startedAtMin != null) {
      scheduleStartMin = Math.max(taskStartMin, firstTask.startedAtMin)
    } else if (activeTaskId) {
      scheduleStartMin = Math.max(taskStartMin, currentTimeMin - totalElapsed)
    } else {
      scheduleStartMin = Math.max(taskStartMin, Math.min(currentTimeMin, taskEndMin))
    }

    // For future days: compute how many task-minutes are absorbed by prior days
    let minutesToSkip = 0
    if (isFuture) {
      // Collect completed task segments and pauses as additional blocking ranges per date
      const getAdditionalBlocking = (date) => {
        const ranges = []
        for (const task of tasks) {
          if (!task.completed || !task.workSegments?.length) continue
          for (const seg of task.workSegments) {
            if (seg.date === date) ranges.push({ start: seg.start, end: seg.end })
          }
        }
        // Pauses only apply to today (from the first incomplete task)
        if (date === todayStr && firstTask?.startedAtMin != null && firstTask.pauseEvents?.length > 0) {
          for (const pe of firstTask.pauseEvents) {
            const peEnd = pe.end ?? currentTimeMin
            if (peEnd > pe.start) ranges.push({ start: pe.start, end: peEnd })
          }
        }
        return ranges
      }

      // Today's remaining capacity: from current time to end of task hours
      const minFrag = settings.minFragmentMinutes || 5
      const todayStart = Math.max(taskStartMin, Math.min(currentTimeMin, taskEndMin))
      if (todayStart < taskEndMin) {
        minutesToSkip += computeAvailableTime(events, todayStr, todayStart, taskEndMin, getAdditionalBlocking(todayStr), minFrag)
      }
      // Intermediate future days (between today+1 and selectedDate-1)
      for (let d = addDays(todayStr, 1); d < selectedDate; d = addDays(d, 1)) {
        minutesToSkip += computeAvailableTime(events, d, taskStartMin, taskEndMin, getAdditionalBlocking(d), minFrag)
      }
    }

    // Completed task segments as blocking ranges (so remaining tasks schedule around them)
    const completedSegmentRanges = []
    for (const task of tasks) {
      if (!task.completed || !task.workSegments?.length) continue
      for (const seg of task.workSegments) {
        if (seg.date !== selectedDate) continue
        const s = Math.max(seg.start, scheduleStartMin)
        const e = Math.min(seg.end, extEndMin)
        if (e > s) completedSegmentRanges.push({ startMin: s, endMin: e })
      }
    }

    // Combine all blocking ranges (events + pauses + completed tasks) for available slot computation
    const allBlocking = [
      ...allEventBlocks.filter(e => e.endMin > scheduleStartMin),
      ...pauseBlockingRanges.filter(p => p.endMin > scheduleStartMin),
      ...completedSegmentRanges.filter(c => c.endMin > scheduleStartMin),
    ].sort((a, b) => a.startMin - b.startMin)

    // Merge overlapping blocking ranges
    const mergedRanges = []
    for (const e of allBlocking) {
      const start = Math.max(e.startMin, scheduleStartMin)
      if (mergedRanges.length === 0 || start > mergedRanges[mergedRanges.length - 1].end) {
        mergedRanges.push({ start, end: e.endMin })
      } else {
        mergedRanges[mergedRanges.length - 1].end = Math.max(
          mergedRanges[mergedRanges.length - 1].end,
          e.endMin
        )
      }
    }

    // Build available time slots (gaps between blocking ranges)
    const availableSlots = []
    let cursor = scheduleStartMin
    for (const range of mergedRanges) {
      if (range.start > cursor) {
        availableSlots.push({ start: cursor, end: range.start })
      }
      cursor = Math.max(cursor, range.end)
    }
    if (cursor < taskEndMin) {
      availableSlots.push({ start: cursor, end: taskEndMin })
    }

    // Schedule incomplete tasks into available slots
    let slotIdx = 0
    let slotUsed = 0
    let skipRemaining = minutesToSkip

    for (const task of incompleteTasks) {
      const isActive = isToday && task.id === activeTaskId
      const plannedDuration = task.adjustedDuration ?? task.duration

      // For future days: skip tasks that fit entirely on prior days
      let taskDayDuration
      if (isFuture && skipRemaining > 0) {
        if (skipRemaining >= plannedDuration) {
          skipRemaining -= plannedDuration
          continue  // fully absorbed by prior days
        }
        taskDayDuration = plannedDuration - skipRemaining
        skipRemaining = 0
      } else {
        taskDayDuration = isActive
          ? Math.max(totalElapsed, plannedDuration)
          : plannedDuration
      }

      let remaining = taskDayDuration
      let blockIdx = 0
      const continuesFromPrior = isFuture && taskDayDuration < plannedDuration

      while (remaining > 0 && slotIdx < availableSlots.length) {
        const slot = availableSlots[slotIdx]
        const start = slot.start + slotUsed
        const slotRemaining = slot.end - start

        if (slotRemaining <= 0) {
          slotIdx++
          slotUsed = 0
          continue
        }

        const dur = Math.min(remaining, slotRemaining)

        const minFrag = settings.minFragmentMinutes || 5
        if (dur < minFrag && remaining > slotRemaining) {
          slotIdx++
          slotUsed = 0
          continue
        }

        const blockIsPast = isToday && (start + dur) <= currentTimeMin

        taskBlocks.push({
          taskId: task.id,
          taskName: task.name,
          tagId: task.tagId,
          start: minutesToTime(start),
          end: minutesToTime(start + dur),
          startMin: start,
          endMin: start + dur,
          duration: dur,
          isSplit: taskDayDuration > dur || blockIdx > 0 || continuesFromPrior,
          blockIndex: blockIdx,
          type: 'task',
          isActive,
          isPast: blockIsPast,
          isPausedRemaining: firstTaskIsPaused && task.id === firstTask?.id && !blockIsPast,
          continuesBefore: blockIdx > 0 || continuesFromPrior,
          continuesAfter: remaining - dur > 0,
        })

        remaining -= dur
        slotUsed += dur
        blockIdx++

        if (slotUsed >= slot.end - slot.start) {
          slotIdx++
          slotUsed = 0
        }
      }
    }
  }

  // Add completed tasks that were actually worked on (filtered by date)
  const completedTasks = tasks.filter(t => t.completed && t.startedAtMin != null && t.actualDuration >= 2)
  for (const task of completedTasks) {
    const segments = task.workSegments || []
    if (segments.length > 0) {
      const dateSegments = segments.filter(seg => seg.date === selectedDate)
      for (let i = 0; i < dateSegments.length; i++) {
        const seg = dateSegments[i]
        const segStart = Math.max(seg.start, extStartMin)
        const segEnd = Math.min(seg.end, extEndMin)
        if (segEnd > segStart) {
          taskBlocks.push({
            taskId: task.id,
            taskName: task.name,
            tagId: task.tagId,
            start: minutesToTime(segStart),
            end: minutesToTime(segEnd),
            startMin: segStart,
            endMin: segEnd,
            duration: segEnd - segStart,
            isSplit: dateSegments.length > 1,
            blockIndex: i,
            type: 'task',
            isActive: false,
            isPast: true,
            isCompleted: true,
            continuesBefore: i > 0,
            continuesAfter: i < dateSegments.length - 1,
          })
        }
      }
    } else if (isToday) {
      // Legacy fallback: single block (only on today since we don't know the date)
      const start = Math.max(task.startedAtMin, extStartMin)
      const end = Math.min(task.startedAtMin + task.actualDuration, extEndMin)
      if (end > start) {
        taskBlocks.push({
          taskId: task.id,
          taskName: task.name,
          tagId: task.tagId,
          start: minutesToTime(start),
          end: minutesToTime(end),
          startMin: start,
          endMin: end,
          duration: end - start,
          isSplit: false,
          blockIndex: 0,
          type: 'task',
          isActive: false,
          isPast: true,
          isCompleted: true,
          continuesBefore: false,
          continuesAfter: false,
        })
      }
    }
  }

  // Combine events, tasks, and pause display blocks, sorted by start time
  return [...allEventBlocks, ...taskBlocks, ...pauseDisplayBlocks].sort((a, b) => a.startMin - b.startMin)
}
