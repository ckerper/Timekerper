import { useState, useMemo, useEffect, useCallback, useRef } from 'react'
import {
  timeToMinutes, minutesToTime, formatTime, formatElapsed,
  formatBlockTimeRange, getCurrentTimeMinutes, scheduleDay,
  getTodayStr, addDays, formatDateHeader, formatShortDateHeader, formatDateHeaderCompact,
  parseIcsFile, filterIcsEvents
} from './scheduler'
import './App.css'

// ─── Last Updated Timestamp ─────────────────────────────────────────────────
// IMPORTANT: Update this timestamp every time you make changes to the code
const LAST_UPDATED = '2026-02-21 1:15 PM CT'

// ─── Color Helpers ──────────────────────────────────────────────────────────

function hexToRgb(hex) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex)
  return result
    ? { r: parseInt(result[1], 16), g: parseInt(result[2], 16), b: parseInt(result[3], 16) }
    : { r: 148, g: 163, b: 184 }
}

function hexToRgba(hex, alpha) {
  const { r, g, b } = hexToRgb(hex)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

function blendWithSurface(hex, alpha, isDarkMode) {
  const { r, g, b } = hexToRgb(hex)
  const bg = isDarkMode ? { r: 30, g: 41, b: 59 } : { r: 255, g: 255, b: 255 }
  const blend = (c, s) => Math.round(c * alpha + s * (1 - alpha))
  return `rgb(${blend(r, bg.r)}, ${blend(g, bg.g)}, ${blend(b, bg.b)})`
}

function getTextColor(hex, blockOpacity, isDarkMode) {
  const { r, g, b } = hexToRgb(hex)
  const bg = isDarkMode ? { r: 30, g: 41, b: 59 } : { r: 255, g: 255, b: 255 }
  const eff = {
    r: r * blockOpacity + bg.r * (1 - blockOpacity),
    g: g * blockOpacity + bg.g * (1 - blockOpacity),
    b: b * blockOpacity + bg.b * (1 - blockOpacity),
  }
  const brightness = (eff.r * 299 + eff.g * 587 + eff.b * 114) / 1000
  return brightness > 150 ? '#1a1a1a' : '#ffffff'
}

// ─── Smart Time Default ──────────────────────────────────────────────────────
// Work meetings don't happen at 11:30 PM or 3:00 AM. Auto-convert:
//   Hours 19–23 (7–11 PM) → snap to AM (subtract 12)
//   Hours 1–6  (1–6 AM)  → snap to PM (add 12)
// Override: if the user just toggled AM/PM from the corrected value, respect it.
function applySmartTime(newTimeStr, oldTimeStr) {
  const [newH] = newTimeStr.split(':').map(Number)
  const [oldH] = oldTimeStr.split(':').map(Number)
  const mins = newTimeStr.split(':')[1]
  // 7–11 PM → 7–11 AM (unless user explicitly toggled back from AM)
  if (newH >= 19 && newH <= 23 && oldH !== newH - 12) {
    return `${(newH - 12).toString().padStart(2, '0')}:${mins}`
  }
  // 1–6 AM → 1–6 PM (unless user explicitly toggled back from PM)
  if (newH >= 1 && newH <= 6 && oldH !== newH + 12) {
    return `${(newH + 12).toString().padStart(2, '0')}:${mins}`
  }
  return newTimeStr
}

// ─── Constants ──────────────────────────────────────────────────────────────

const ZOOM_LEVELS = [0.5, 0.75, 1, 1.5, 2, 3]

const FONT_SIZE_OPTIONS = {
  small:  { title: '0.7rem',  time: '0.55rem', label: 'Small' },
  medium: { title: '0.8rem',  time: '0.65rem', label: 'Medium' },
  large:  { title: '0.95rem', time: '0.75rem', label: 'Large' },
  xlarge: { title: '1.1rem',  time: '0.85rem', label: 'Extra Large' },
}

const defaultSettings = {
  workdayStart: '09:00',
  workdayEnd: '17:00',
  useExtendedHours: true,
  extendedStart: '06:00',
  extendedEnd: '23:59',
  autoStartNext: false,
  darkMode: false,
  zoomLevel: 1.5,
  fitMode: true,
  smartDuration: true,
  defaultTaskDuration: 30,
  defaultEventDuration: 60,
  defaultTaskColor: '#94a3b8',
  defaultEventColor: '#94a3b8',
  minFragmentMinutes: 5,
  calendarFontSize: 'medium',
  wrapListNames: true,
  restrictTasksToWorkHours: true,
  debugMode: false,
  debugTimeOffset: 0,
  icsImportBusy: true,
  icsImportOof: true,
  icsImportTentative: false,
  icsImportFree: false,
  icsImportWorkingElsewhere: false,
  icsImportMeetingsOnly: false,
  icsReplaceOnImport: 'no',
  icsCategoryRules: [],
}

const defaultTags = [
  { id: 1, name: 'Epic Medical Center', color: '#ef4444' },
  { id: 2, name: 'Verona Hospital', color: '#667eea' },
  { id: 3, name: 'Fitchburg Health', color: '#10b981' },
  { id: 4, name: 'Internal', color: '#f59e0b' },
]

const defaultTasks = [
  { id: 1, name: 'Tech note review', duration: 30, adjustedDuration: null, completed: false, tagId: null, pausedElapsed: 0 },
  { id: 2, name: 'Sherlock #12345678', duration: 75, adjustedDuration: null, completed: false, tagId: 3, pausedElapsed: 0 },
  { id: 3, name: 'Firewatch investigation', duration: 60, adjustedDuration: null, completed: false, tagId: 1, pausedElapsed: 0 },
]

const defaultEvents = [
  { id: 1, name: 'EMC check-in', start: '11:00', end: '11:30', tagId: 1 },
  { id: 2, name: 'Workgroup meeting', start: '13:30', end: '14:30', tagId: 4 },
  { id: 3, name: 'Verona Hospital office hours', start: '15:00', end: '16:00', tagId: 2 },
]

// ─── Active Task Restore ─────────────────────────────────────────────────────

function restoreActiveTaskState() {
  const savedId = localStorage.getItem('timekerper-activeTaskId')
  if (!savedId || savedId === 'null') return null
  const id = JSON.parse(savedId)
  const savedTasks = localStorage.getItem('timekerper-tasks')
  if (!savedTasks) return null
  const tasks = JSON.parse(savedTasks)
  const task = tasks.find(t => t.id === id && !t.completed)
  if (!task || task.startedAtMin == null) return null
  // Read debug offset from saved settings
  const savedSettings = localStorage.getItem('timekerper-settings')
  const s = savedSettings ? JSON.parse(savedSettings) : {}
  const offset = s.debugMode ? (s.debugTimeOffset || 0) : 0
  const now = getCurrentTimeMinutes() + offset
  // Compute total pause gap from pauseEvents (all should be finalized if task is active)
  const gap = (task.pauseEvents || []).reduce((sum, pe) => {
    return sum + ((pe.end ?? now) - pe.start)
  }, 0) || (task.pauseGapMinutes || 0)  // fallback for legacy data
  const elapsed = Math.max(0, now - task.startedAtMin - gap)
  return { id, taskStartTime: Date.now() - (elapsed * 60000), elapsedMinutes: elapsed }
}

// ─── Data Migration ──────────────────────────────────────────────────────────

function migrateDataWithDates(tasks, events) {
  const today = getTodayStr()
  const migratedTasks = tasks.map(t => {
    let task = t
    if (t.startedAtMin != null && !t.startedAtDate) {
      task = { ...task, startedAtDate: today }
    }
    if (t.workSegments?.some(seg => !seg.date)) {
      task = { ...task, workSegments: task.workSegments.map(seg => seg.date ? seg : { ...seg, date: today }) }
    }
    if (t.pauseEvents?.some(pe => !pe.date)) {
      task = { ...task, pauseEvents: task.pauseEvents.map(pe => pe.date ? pe : { ...pe, date: today }) }
    }
    return task
  })
  const migratedEvents = events.map(e => e.date ? e : { ...e, date: today })
  return { tasks: migratedTasks, events: migratedEvents }
}

function getInitialData() {
  const savedTasks = localStorage.getItem('timekerper-tasks')
  const savedEvents = localStorage.getItem('timekerper-events')
  const tasks = savedTasks ? JSON.parse(savedTasks) : defaultTasks
  const events = savedEvents ? JSON.parse(savedEvents) : defaultEvents
  const migrationVersion = parseInt(localStorage.getItem('timekerper-migrationVersion') || '0')
  if (migrationVersion < 1) {
    const result = migrateDataWithDates(tasks, events)
    localStorage.setItem('timekerper-tasks', JSON.stringify(result.tasks))
    localStorage.setItem('timekerper-events', JSON.stringify(result.events))
    localStorage.setItem('timekerper-migrationVersion', '1')
    return result
  }
  return { tasks, events }
}

const _initialData = getInitialData()

// ─── App Component ──────────────────────────────────────────────────────────

function App() {

  // ── State: Core Data ──────────────────────────────────────────────────────

  const [tasks, setTasks] = useState(_initialData.tasks)

  const [events, setEvents] = useState(_initialData.events)

  const [settings, setSettings] = useState(() => {
    const saved = localStorage.getItem('timekerper-settings')
    return saved ? { ...defaultSettings, ...JSON.parse(saved) } : defaultSettings
  })

  const [tags, setTags] = useState(() => {
    const saved = localStorage.getItem('timekerper-tags')
    return saved ? JSON.parse(saved) : defaultTags
  })

  // ── State: Active Task ────────────────────────────────────────────────────

  const [activeTaskId, setActiveTaskId] = useState(() => restoreActiveTaskState()?.id ?? null)
  const [taskStartTime, setTaskStartTime] = useState(() => restoreActiveTaskState()?.taskStartTime ?? null)
  const [elapsedMinutes, setElapsedMinutes] = useState(() => restoreActiveTaskState()?.elapsedMinutes ?? 0)
  const timeOffset = settings.debugMode ? (settings.debugTimeOffset || 0) : 0
  const [currentTime, setCurrentTime] = useState(getCurrentTimeMinutes() + timeOffset)

  // ── State: Date Navigation ───────────────────────────────────────────────

  const [selectedDate, setSelectedDate] = useState(getTodayStr())
  const [calendarView, setCalendarView] = useState(() =>
    localStorage.getItem('tk_calendarView') || '1day'
  )
  const windowStartRef = useRef(getTodayStr())

  // ── State: UI ─────────────────────────────────────────────────────────────

  const [showTaskModal, setShowTaskModal] = useState(false)
  const [showEventModal, setShowEventModal] = useState(false)
  const [showSettingsModal, setShowSettingsModal] = useState(false)
  const [showViewMenu, setShowViewMenu] = useState(false)
  const [editingTask, setEditingTask] = useState(null)
  const [editingEvent, setEditingEvent] = useState(null)
  const [hideCompleted, setHideCompleted] = useState(false)
  const [hidePastEvents, setHidePastEvents] = useState(false)
  const [eventSourceFilter, setEventSourceFilter] = useState('all') // 'all' | 'manual' | 'outlook'
  const [icsCategoryModal, setIcsCategoryModal] = useState(null)
  const [icsCategoryMappings, setIcsCategoryMappings] = useState([])
  const [icsReplaceConfirm, setIcsReplaceConfirm] = useState(null)

  // ── State: Forms ──────────────────────────────────────────────────────────

  const [taskName, setTaskName] = useState('')
  const [taskDuration, setTaskDuration] = useState(30)
  const [taskTag, setTaskTag] = useState(null)
  const [addTaskToTop, setAddTaskToTop] = useState(false)
  const [eventName, setEventName] = useState('')
  const [eventStart, setEventStart] = useState('09:00')
  const [eventEnd, setEventEnd] = useState('10:00')
  const [eventTag, setEventTag] = useState(null)
  const [eventDate, setEventDate] = useState(getTodayStr())
  const [showBulkEventEntry, setShowBulkEventEntry] = useState(false)
  const [bulkEventText, setBulkEventText] = useState('')
  const [copiedFeedback, setCopiedFeedback] = useState(null)
  const endTimeManualRef = useRef(false)
  const eventStartRef = useRef(null)
  const eventEndRef = useRef(null)
  const calendarContainerRef = useRef(null)
  const viewMenuRef = useRef(null)
  const importFileRef = useRef(null)
  const icsFileRef = useRef(null)

  // ── State: Panel Resize ──────────────────────────────────────────────────

  const [panelWidth, setPanelWidth] = useState(320)
  const [panelHeight, setPanelHeight] = useState(300)
  const resizingRef = useRef(false)
  const resizingVerticalRef = useRef(false)

  // ── State: Drag and Drop ──────────────────────────────────────────────────

  const [draggedTaskId, setDraggedTaskId] = useState(null)
  const [dragOverTaskId, setDragOverTaskId] = useState(null)
  const [draggedTagId, setDraggedTagId] = useState(null)
  const [dragOverTagId, setDragOverTagId] = useState(null)

  // ── Undo/Redo System ──────────────────────────────────────────────────────

  const undoStackRef = useRef([])
  const redoStackRef = useRef([])
  const tasksRef = useRef(tasks)
  const eventsRef = useRef(events)
  const [, forceRender] = useState(0)

  // Keep refs in sync
  useEffect(() => { tasksRef.current = tasks }, [tasks])
  useEffect(() => { eventsRef.current = events }, [events])

  const pushUndo = useCallback(() => {
    undoStackRef.current = [
      ...undoStackRef.current.slice(-49),
      { tasks: tasksRef.current, events: eventsRef.current }
    ]
    redoStackRef.current = []
    forceRender(n => n + 1)
  }, [])

  const undo = useCallback(() => {
    const stack = undoStackRef.current
    if (stack.length === 0) return
    const snapshot = stack[stack.length - 1]
    redoStackRef.current = [...redoStackRef.current, { tasks: tasksRef.current, events: eventsRef.current }]
    undoStackRef.current = stack.slice(0, -1)
    setTasks(snapshot.tasks)
    setEvents(snapshot.events)
    tasksRef.current = snapshot.tasks
    eventsRef.current = snapshot.events
    forceRender(n => n + 1)
  }, [])

  const redo = useCallback(() => {
    const stack = redoStackRef.current
    if (stack.length === 0) return
    const snapshot = stack[stack.length - 1]
    undoStackRef.current = [...undoStackRef.current, { tasks: tasksRef.current, events: eventsRef.current }]
    redoStackRef.current = stack.slice(0, -1)
    setTasks(snapshot.tasks)
    setEvents(snapshot.events)
    tasksRef.current = snapshot.tasks
    eventsRef.current = snapshot.events
    forceRender(n => n + 1)
  }, [])

  const canUndo = undoStackRef.current.length > 0
  const canRedo = redoStackRef.current.length > 0

  // ── Computed: Date Navigation ─────────────────────────────────────────────

  const todayStr = getTodayStr()
  const isToday = selectedDate === todayStr
  const dayOfWeek = new Date(todayStr + 'T12:00:00').getDay() // 0=Sun..6=Sat
  const daysSinceMonday = (dayOfWeek + 6) % 7 // Mon=0, Tue=1, ..., Sun=6
  const mostRecentMonday = addDays(todayStr, -daysSinceMonday)
  const yesterday = addDays(todayStr, -1)
  const minDate = mostRecentMonday < yesterday ? mostRecentMonday : yesterday
  const maxDate = addDays(todayStr, 7)
  const canGoBack = selectedDate > minDate
  const canGoForward = selectedDate < maxDate
  const numViewDays = calendarView === '1day' ? 1 : (parseInt(calendarView) || 1)

  const viewDates = useMemo(() => {
    if (numViewDays === 1) {
      windowStartRef.current = selectedDate
      return [selectedDate]
    }
    const last = numViewDays - 1
    let start = windowStartRef.current
    // Shift window minimally if selectedDate is outside
    if (selectedDate > addDays(start, last)) start = addDays(selectedDate, -last)
    else if (selectedDate < start) start = selectedDate
    // Clamp to bounds
    if (addDays(start, last) > maxDate) start = addDays(maxDate, -last)
    if (start < minDate) start = minDate
    windowStartRef.current = start
    return Array.from({ length: numViewDays }, (_, i) => addDays(start, i))
  }, [selectedDate, numViewDays, minDate, maxDate])

  const todayVisible = viewDates.includes(todayStr)

  // ── Handlers: Date Navigation ─────────────────────────────────────────────

  const goToPreviousDay = useCallback(() => {
    setSelectedDate(prev => {
      const newDate = addDays(prev, -1)
      return newDate >= minDate ? newDate : prev
    })
  }, [minDate])

  const goToNextDay = useCallback(() => {
    setSelectedDate(prev => {
      const newDate = addDays(prev, 1)
      return newDate <= maxDate ? newDate : prev
    })
  }, [maxDate])

  const goToToday = useCallback(() => {
    setSelectedDate(getTodayStr())
  }, [])

  const switchView = useCallback((view) => {
    setCalendarView(view)
    const n = view === '1day' ? 1 : (parseInt(view) || 1)
    if (n > 1) {
      setSelectedDate(prev => {
        if (addDays(prev, n - 1) > maxDate) return addDays(maxDate, -(n - 1))
        return prev < minDate ? minDate : prev
      })
    }
  }, [maxDate, minDate])

  // Keyboard shortcuts for undo/redo + date navigation
  useEffect(() => {
    const handleKeyDown = (e) => {
      const tag = document.activeElement?.tagName?.toLowerCase()
      if (tag === 'input' || tag === 'textarea') return

      if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
        e.preventDefault()
        if (e.shiftKey) { redo() } else { undo() }
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 'y') {
        e.preventDefault()
        redo()
      }
      if (e.key === 'ArrowLeft' && !e.ctrlKey && !e.metaKey && !e.shiftKey) {
        goToPreviousDay()
      }
      if (e.key === 'ArrowRight' && !e.ctrlKey && !e.metaKey && !e.shiftKey) {
        goToNextDay()
      }
      if (e.key === 't' || e.key === 'T') {
        goToToday()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [undo, redo, goToPreviousDay, goToNextDay, goToToday])

  // ── Effects: Persistence ──────────────────────────────────────────────────

  useEffect(() => { localStorage.setItem('timekerper-tasks', JSON.stringify(tasks)) }, [tasks])
  useEffect(() => { localStorage.setItem('timekerper-events', JSON.stringify(events)) }, [events])
  useEffect(() => { localStorage.setItem('timekerper-settings', JSON.stringify(settings)) }, [settings])
  useEffect(() => { localStorage.setItem('timekerper-tags', JSON.stringify(tags)) }, [tags])
  useEffect(() => { localStorage.setItem('timekerper-activeTaskId', JSON.stringify(activeTaskId)) }, [activeTaskId])
  useEffect(() => { localStorage.setItem('tk_calendarView', calendarView) }, [calendarView])

  // ── Effects: Timer ────────────────────────────────────────────────────────

  useEffect(() => {
    if (!activeTaskId || !taskStartTime) return
    const interval = setInterval(() => {
      setElapsedMinutes(Math.floor((Date.now() - taskStartTime) / 60000))
      setCurrentTime(getCurrentTimeMinutes() + timeOffset)
    }, 1000)
    return () => clearInterval(interval)
  }, [activeTaskId, taskStartTime, timeOffset])

  useEffect(() => {
    if (activeTaskId) return
    const update = () => setCurrentTime(getCurrentTimeMinutes() + timeOffset)
    update()  // immediately apply offset changes
    const interval = setInterval(update, 15000)
    return () => clearInterval(interval)
  }, [activeTaskId, timeOffset])

  // ── Effects: Dark Mode ────────────────────────────────────────────────────

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', settings.darkMode ? 'dark' : 'light')
  }, [settings.darkMode])

  // ── Effects: View Menu click-outside ─────────────────────────────────────

  useEffect(() => {
    if (!showViewMenu) return
    const handleClickOutside = (e) => {
      if (viewMenuRef.current && !viewMenuRef.current.contains(e.target))
        setShowViewMenu(false)
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [showViewMenu])

  // ── Effects: Panel Resize ────────────────────────────────────────────────

  useEffect(() => {
    const handleMouseMove = (e) => {
      if (resizingRef.current) {
        const newWidth = Math.max(260, Math.min(e.clientX, window.innerWidth - 300))
        setPanelWidth(newWidth)
      } else if (resizingVerticalRef.current) {
        const headerHeight = document.querySelector('.header')?.offsetHeight || 0
        const y = e.clientY - headerHeight
        const available = window.innerHeight - headerHeight
        const newHeight = Math.max(120, Math.min(y, available - 200))
        setPanelHeight(newHeight)
      }
    }
    const handleMouseUp = () => {
      if (resizingRef.current) {
        resizingRef.current = false
        document.body.style.cursor = ''
        document.body.style.userSelect = ''
      }
      if (resizingVerticalRef.current) {
        resizingVerticalRef.current = false
        document.body.style.cursor = ''
        document.body.style.userSelect = ''
      }
    }
    window.addEventListener('mousemove', handleMouseMove)
    window.addEventListener('mouseup', handleMouseUp)
    return () => {
      window.removeEventListener('mousemove', handleMouseMove)
      window.removeEventListener('mouseup', handleMouseUp)
    }
  }, [])

  const startResize = useCallback(() => {
    resizingRef.current = true
    document.body.style.cursor = 'col-resize'
    document.body.style.userSelect = 'none'
  }, [])

  const startResizeVertical = useCallback(() => {
    resizingVerticalRef.current = true
    document.body.style.cursor = 'row-resize'
    document.body.style.userSelect = 'none'
  }, [])

  // ── Computed Values ───────────────────────────────────────────────────────

  // When extended hours are disabled, use working hours for the calendar view
  const effectiveSettings = useMemo(() => {
    if (settings.useExtendedHours) return settings
    return { ...settings, extendedStart: settings.workdayStart, extendedEnd: settings.workdayEnd }
  }, [settings])

  const schedules = useMemo(() =>
    viewDates.map(d => scheduleDay(tasks, events, effectiveSettings, activeTaskId, elapsedMinutes, d))
  , [viewDates, tasks, events, effectiveSettings, activeTaskId, elapsedMinutes, currentTime])

  // Pre-compute fragment counts per task for border-radius logic
  const taskFragCountsPerDay = useMemo(() => schedules.map(sched => {
    const counts = {}
    for (const block of sched) {
      if (block.type === 'task') {
        counts[block.taskId] = Math.max(counts[block.taskId] || 0, block.blockIndex + 1)
      }
    }
    return counts
  }), [schedules])

  // Pre-compute overlap layout for events (column index + total columns)
  const eventLayoutsPerDay = useMemo(() => schedules.map(sched => {
    const eventBlocks = sched
      .map((block, idx) => ({ ...block, _idx: idx }))
      .filter(b => b.type === 'event')
    if (eventBlocks.length === 0) return {}

    // Assign columns using a greedy interval graph approach
    const layout = {}
    const active = [] // { endMin, col }

    for (const ev of eventBlocks) {
      // Remove events that have ended
      const stillActive = active.filter(a => a.endMin > ev.startMin)
      active.length = 0
      active.push(...stillActive)

      // Find first free column
      const usedCols = new Set(active.map(a => a.col))
      let col = 0
      while (usedCols.has(col)) col++

      active.push({ endMin: ev.endMin, col })
      layout[ev._idx] = { col, total: 0 } // total filled in next pass
    }

    // Second pass: determine max overlapping group size for each event
    for (const ev of eventBlocks) {
      let maxCols = 1
      for (const other of eventBlocks) {
        if (other.startMin < ev.endMin && other.endMin > ev.startMin) {
          maxCols = Math.max(maxCols, layout[other._idx].col + 1)
        }
      }
      layout[ev._idx].total = maxCols
    }

    return layout
  }), [schedules])

  const firstIncompleteTask = tasks.find(t => !t.completed)
  const activeTask = tasks.find(t => t.id === activeTaskId)
  const isOverEstimate = activeTask && elapsedMinutes > (activeTask.adjustedDuration ?? activeTask.duration)

  const extStartMin = timeToMinutes(effectiveSettings.extendedStart)
  const extEndMin = timeToMinutes(effectiveSettings.extendedEnd)
  const workdayStartMin = timeToMinutes(settings.workdayStart)
  const workdayEndMin = timeToMinutes(settings.workdayEnd)
  const zoom = settings.zoomLevel
  const gridHeight = (extEndMin - extStartMin) * zoom

  const startHour = Math.floor(extStartMin / 60)
  const endHour = Math.ceil(extEndMin / 60)
  const calendarHours = Array.from({ length: endHour - startHour }, (_, i) => startHour + i)

  // ── Helpers ───────────────────────────────────────────────────────────────

  const getTagColor = useCallback((tagId) => {
    if (!tagId) return null
    return tags.find(t => t.id === tagId)?.color || null
  }, [tags])

  const getTagName = useCallback((tagId) => {
    if (!tagId) return null
    return tags.find(t => t.id === tagId)?.name || null
  }, [tags])

  const getBlockStyle = useCallback((block, index, dayEventLayout) => {
    const top = (block.startMin - extStartMin) * zoom
    const height = (block.endMin - block.startMin) * zoom
    const style = { top: `${top}px`, height: `${Math.max(height, 4)}px` }

    // Apply column layout for overlapping events
    const layout = dayEventLayout[index]
    if (layout && layout.total > 1) {
      const pad = 4   // outer padding (matches .calendar-block left/right)
      const gap = 2   // gap between adjacent columns
      // Available width = 100% - left pad - right pad - gaps between columns
      // Each column gets an equal share of that
      const totalGaps = layout.total - 1
      const colWidth = `(100% - ${pad * 2 + gap * totalGaps}px) / ${layout.total}`
      style.left = `calc(${pad}px + ${layout.col} * (${colWidth} + ${gap}px))`
      style.width = `calc(${colWidth})`
      style.right = 'auto'
    }

    return style
  }, [extStartMin, zoom])

  const getBlockHeightPx = useCallback((block) => {
    return (block.endMin - block.startMin) * zoom
  }, [zoom])

  const updateSetting = useCallback((key, value) => {
    // Snap 00:00 to 23:59 for end-of-day time settings
    if ((key === 'extendedEnd' || key === 'workdayEnd') && value === '00:00') {
      value = '23:59'
    }
    setSettings(prev => ({ ...prev, [key]: value }))
  }, [])

  // Parse smart duration and tag: "task name 30 [TagName]" → { name: "task name", duration: 30, tagId: 1 }
  const parseSmartDuration = useCallback((line, fallbackDuration) => {
    // First check for tag pattern [TagName] at the end
    const tagMatch = line.match(/^(.+?)\s+\[(.+?)\]$/)
    let tagId = null
    let lineWithoutTag = line

    if (tagMatch) {
      lineWithoutTag = tagMatch[1]
      const tagName = tagMatch[2]
      tagId = tags.find(t => t.name === tagName)?.id ?? null
    }

    // Then check for duration pattern if smartDuration is enabled
    if (settings.smartDuration) {
      const durationMatch = lineWithoutTag.match(/^(.+?)\s+(\d+)$/)
      if (durationMatch) {
        return { name: durationMatch[1], duration: parseInt(durationMatch[2], 10), tagId }
      }
    }

    return { name: lineWithoutTag, duration: fallbackDuration, tagId }
  }, [settings.smartDuration, tags])

  // ── Handlers: Active Task ─────────────────────────────────────────────────

  const startTask = useCallback(() => {
    if (!firstIncompleteTask) return
    const pausedMs = (firstIncompleteTask.pausedElapsed || 0) * 60000
    const now = getCurrentTimeMinutes() + timeOffset

    // Set startedAtMin on first start, finalize pause event on resume
    setTasks(prev => prev.map(t => {
      if (t.id !== firstIncompleteTask.id) return t
      const updates = {}
      if (t.startedAtMin == null) {
        updates.startedAtMin = now
        updates.startedAtDate = getTodayStr()
      }
      if (t.pausedAtMin != null) {
        updates.pauseGapMinutes = (t.pauseGapMinutes || 0) + Math.max(0, now - t.pausedAtMin)
        updates.pausedAtMin = null
        // Finalize the open pause event with the resume time
        const pauseEvents = [...(t.pauseEvents || [])]
        if (pauseEvents.length > 0 && pauseEvents[pauseEvents.length - 1].end == null) {
          pauseEvents[pauseEvents.length - 1] = { ...pauseEvents[pauseEvents.length - 1], end: now }
        }
        updates.pauseEvents = pauseEvents
      }
      return Object.keys(updates).length > 0 ? { ...t, ...updates } : t
    }))

    setActiveTaskId(firstIncompleteTask.id)
    setTaskStartTime(Date.now() - pausedMs)
    setElapsedMinutes(firstIncompleteTask.pausedElapsed || 0)
  }, [firstIncompleteTask, timeOffset])

  const completeActiveTask = useCallback(() => {
    if (!activeTaskId) return
    pushUndo()
    const finishedElapsed = elapsedMinutes
    const now = getCurrentTimeMinutes() + timeOffset
    setTasks(prev => {
      const updated = prev.map(t => {
        if (t.id !== activeTaskId) return t
        const segStart = t.startedAtMin + (t.pausedElapsed || 0) + (t.pauseGapMinutes || 0)
        return {
          ...t,
          completed: true,
          actualDuration: finishedElapsed,
          workSegments: [...(t.workSegments || []), { start: segStart, end: now, date: getTodayStr() }],
          pausedElapsed: 0,
          pausedAtMin: null,
          pauseEvents: [],
        }
      })
      if (settings.autoStartNext) {
        const next = updated.find(t => !t.completed)
        if (next) {
          const pausedMs = (next.pausedElapsed || 0) * 60000
          const now = getCurrentTimeMinutes() + timeOffset
          setTimeout(() => {
            setTasks(p => p.map(t => {
              if (t.id !== next.id) return t
              const updates = {}
              if (t.startedAtMin == null) {
                updates.startedAtMin = now
                updates.startedAtDate = getTodayStr()
              }
              if (t.pausedAtMin != null) {
                updates.pauseGapMinutes = (t.pauseGapMinutes || 0) + Math.max(0, now - t.pausedAtMin)
                updates.pausedAtMin = null
                // Finalize open pause event on auto-resume
                const pauseEvents = [...(t.pauseEvents || [])]
                if (pauseEvents.length > 0 && pauseEvents[pauseEvents.length - 1].end == null) {
                  pauseEvents[pauseEvents.length - 1] = { ...pauseEvents[pauseEvents.length - 1], end: now }
                }
                updates.pauseEvents = pauseEvents
              }
              return Object.keys(updates).length > 0 ? { ...t, ...updates } : t
            }))
            setActiveTaskId(next.id)
            setTaskStartTime(Date.now() - pausedMs)
            setElapsedMinutes(next.pausedElapsed || 0)
          }, 0)
        } else {
          setActiveTaskId(null)
          setTaskStartTime(null)
          setElapsedMinutes(0)
        }
      } else {
        setActiveTaskId(null)
        setTaskStartTime(null)
        setElapsedMinutes(0)
      }
      return updated
    })
  }, [activeTaskId, pushUndo, settings.autoStartNext, timeOffset])

  const pauseActiveTask = useCallback(() => {
    if (!activeTaskId) return
    pushUndo()
    const now = getCurrentTimeMinutes() + timeOffset
    setTasks(prev => prev.map(t => {
      if (t.id !== activeTaskId) return t
      // Record this work segment: starts where we resumed, ends now
      const segStart = t.startedAtMin + (t.pausedElapsed || 0) + (t.pauseGapMinutes || 0)
      return {
        ...t,
        pausedElapsed: elapsedMinutes,
        pausedAtMin: now,
        workSegments: [...(t.workSegments || []), { start: segStart, end: now, date: getTodayStr() }],
        // Add an open-ended pause event (end: null means growing)
        pauseEvents: [...(t.pauseEvents || []), { start: now, end: null, date: getTodayStr() }],
      }
    }))
    setActiveTaskId(null)
    setTaskStartTime(null)
    setElapsedMinutes(0)
  }, [activeTaskId, elapsedMinutes, pushUndo, timeOffset])

  const cancelActiveTask = useCallback(() => {
    if (activeTaskId) {
      setTasks(prev => prev.map(t =>
        t.id === activeTaskId
          ? { ...t, startedAtMin: null, startedAtDate: null, pausedAtMin: null, pauseGapMinutes: 0, pausedElapsed: 0, workSegments: [], pauseEvents: [] }
          : t
      ))
    }
    setActiveTaskId(null)
    setTaskStartTime(null)
    setElapsedMinutes(0)
  }, [activeTaskId])

  const adjustTaskTime = useCallback((minutes) => {
    if (!activeTaskId) return
    pushUndo()
    setTasks(prev => prev.map(t => {
      if (t.id !== activeTaskId) return t
      const current = t.adjustedDuration ?? t.duration
      return { ...t, adjustedDuration: Math.max(5, current + minutes) }
    }))
  }, [activeTaskId, pushUndo])

  // ── Handlers: Task CRUD ───────────────────────────────────────────────────

  const openAddTask = () => {
    setEditingTask(null)
    setTaskName('')
    setTaskDuration(settings.defaultTaskDuration)
    setTaskTag(null)
    setAddTaskToTop(false)
    setShowTaskModal(true)
  }

  const openEditTask = (task) => {
    setEditingTask(task)
    setTaskName(task.name)
    setTaskDuration(task.adjustedDuration ?? task.duration)
    setTaskTag(task.tagId)
    setShowTaskModal(true)
  }

  const saveTask = () => {
    if (!taskName.trim()) return
    pushUndo()

    if (editingTask) {
      // Single task edit
      setTasks(prev => prev.map(t =>
        t.id === editingTask.id
          ? { ...t, name: taskName, adjustedDuration: taskDuration, tagId: taskTag }
          : t
      ))
    } else {
      // Multi-line support: split by newlines
      const lines = taskName.split('\n').map(l => l.trim()).filter(l => l.length > 0)
      const newTasks = lines.map((line, idx) => {
        const parsed = parseSmartDuration(line, taskDuration)
        return {
          id: Date.now() + idx,
          name: parsed.name,
          duration: parsed.duration,
          adjustedDuration: null,
          completed: false,
          tagId: parsed.tagId !== null ? parsed.tagId : taskTag,
          pausedElapsed: 0,
        }
      })
      setTasks(prev => addTaskToTop ? [...newTasks, ...prev] : [...prev, ...newTasks])
    }
    setShowTaskModal(false)
  }

  const deleteTask = (taskId) => {
    pushUndo()
    if (taskId === activeTaskId) cancelActiveTask()
    setTasks(prev => prev.filter(t => t.id !== taskId))
  }

  const toggleTaskComplete = (taskId) => {
    pushUndo()
    const isActive = taskId === activeTaskId
    const finishedElapsed = isActive ? elapsedMinutes : 0
    const now = getCurrentTimeMinutes() + timeOffset

    if (isActive && !settings.autoStartNext) {
      // Clear active task UI state (auto-start case handled below)
      setActiveTaskId(null)
      setTaskStartTime(null)
      setElapsedMinutes(0)
    }

    setTasks(prev => {
      const updated = prev.map(t => {
        if (t.id !== taskId) return t
        if (!t.completed) {
          // Completing
          const result = { ...t, completed: true, pausedElapsed: 0, pausedAtMin: null, pauseEvents: [] }

          if (isActive) {
            // Currently active: capture final work segment ending now
            const segStart = t.startedAtMin + (t.pausedElapsed || 0) + (t.pauseGapMinutes || 0)
            result.workSegments = [...(t.workSegments || []), { start: segStart, end: now, date: getTodayStr() }]
            result.actualDuration = finishedElapsed
          } else if (t.workSegments?.length > 0) {
            // Was started and paused: keep existing segments
            result.actualDuration = t.workSegments.reduce((sum, s) => sum + (s.end - s.start), 0)
          } else {
            // Never started: no calendar presence — just mark complete
            result.actualDuration = 0
          }

          return result
        } else {
          // Uncompleting: clear timing so it gets rescheduled fresh
          return { ...t, completed: false, actualDuration: undefined, startedAtMin: null, startedAtDate: null, pausedAtMin: null, pauseGapMinutes: 0, pausedElapsed: 0, workSegments: [], pauseEvents: [] }
        }
      })

      // Auto-start next task when completing active task via checkbox
      if (isActive && settings.autoStartNext) {
        const next = updated.find(t => !t.completed)
        if (next) {
          const pausedMs = (next.pausedElapsed || 0) * 60000
          const now = getCurrentTimeMinutes() + timeOffset
          setTimeout(() => {
            setTasks(p => p.map(t => {
              if (t.id !== next.id) return t
              const updates = {}
              if (t.startedAtMin == null) {
                updates.startedAtMin = now
                updates.startedAtDate = getTodayStr()
              }
              if (t.pausedAtMin != null) {
                updates.pauseGapMinutes = (t.pauseGapMinutes || 0) + Math.max(0, now - t.pausedAtMin)
                updates.pausedAtMin = null
                const pauseEvents = [...(t.pauseEvents || [])]
                if (pauseEvents.length > 0 && pauseEvents[pauseEvents.length - 1].end == null) {
                  pauseEvents[pauseEvents.length - 1] = { ...pauseEvents[pauseEvents.length - 1], end: now }
                }
                updates.pauseEvents = pauseEvents
              }
              return Object.keys(updates).length > 0 ? { ...t, ...updates } : t
            }))
            setActiveTaskId(next.id)
            setTaskStartTime(Date.now() - pausedMs)
            setElapsedMinutes(next.pausedElapsed || 0)
          }, 0)
        } else {
          setActiveTaskId(null)
          setTaskStartTime(null)
          setElapsedMinutes(0)
        }
      }

      return updated
    })
  }

  const duplicateTask = (task) => {
    pushUndo()
    const idx = tasks.findIndex(t => t.id === task.id)
    const copy = {
      ...task,
      id: Date.now(),
      completed: false,
      pausedElapsed: 0,
      adjustedDuration: null,
      startedAtMin: null,
      startedAtDate: null,
      pausedAtMin: null,
      pauseGapMinutes: 0,
      workSegments: [],
      pauseEvents: [],
    }
    const newTasks = [...tasks]
    newTasks.splice(idx + 1, 0, copy)
    setTasks(newTasks)
  }

  // ── Handlers: Event CRUD ──────────────────────────────────────────────────

  const openAddEvent = () => {
    setEditingEvent(null)
    setEventName('')
    // Default start to next 30-minute increment from now
    const now = new Date()
    const nowMin = now.getHours() * 60 + now.getMinutes()
    const nextSlot = Math.ceil((nowMin + 1) / 30) * 30  // +1 so exact :00/:30 rounds to next
    const startMin = Math.min(nextSlot, timeToMinutes(effectiveSettings.extendedEnd) - settings.defaultEventDuration)
    setEventStart(minutesToTime(startMin))
    // End = start + default event duration
    const endMin = startMin + settings.defaultEventDuration
    setEventEnd(minutesToTime(endMin))
    setEventTag(null)
    setEventDate(selectedDate)
    endTimeManualRef.current = false
    setShowEventModal(true)
  }

  const openEditEvent = (event) => {
    setEditingEvent(event)
    setEventName(event.name)
    setEventStart(event.start)
    setEventEnd(event.end)
    setEventTag(event.tagId)
    setEventDate(event.date || getTodayStr())
    endTimeManualRef.current = true  // Existing event: treat end as manually set
    setShowEventModal(true)
  }

  const handleEventStartChange = (newStart) => {
    const adjusted = applySmartTime(newStart, eventStart)
    if (!endTimeManualRef.current) {
      // Maintain duration: shift end time by the same delta
      const oldStartMin = timeToMinutes(eventStart)
      const oldEndMin = timeToMinutes(eventEnd)
      const duration = oldEndMin - oldStartMin
      const newStartMin = timeToMinutes(adjusted)
      setEventEnd(minutesToTime(newStartMin + duration))
    }
    setEventStart(adjusted)
  }

  const handleEventEndChange = (newEnd) => {
    endTimeManualRef.current = true
    setEventEnd(newEnd)
  }

  const saveEvent = () => {
    const name = eventName.trim() || 'Event'
    pushUndo()
    if (editingEvent) {
      setEvents(prev => prev.map(e =>
        e.id === editingEvent.id
          ? { ...e, name, start: eventStart, end: eventEnd, tagId: eventTag, date: eventDate }
          : e
      ))
    } else {
      setEvents(prev => [...prev, {
        id: Date.now(),
        name,
        start: eventStart,
        end: eventEnd,
        tagId: eventTag,
        date: eventDate,
      }])
    }
    setShowEventModal(false)
  }

  const deleteEvent = (eventId) => {
    pushUndo()
    setEvents(prev => prev.filter(e => e.id !== eventId))
  }

  // ── Handlers: Clear All ──────────────────────────────────────────────────

  const clearAllTasks = useCallback(() => {
    pushUndo()
    if (activeTaskId) {
      setActiveTaskId(null)
      setTaskStartTime(null)
      setElapsedMinutes(0)
    }
    setTasks([])
  }, [pushUndo, activeTaskId])

  const clearAllEvents = useCallback(() => {
    pushUndo()
    setEvents(prev => prev.filter(e => e.date !== selectedDate))
  }, [pushUndo, selectedDate])

  const clearCompletedTasks = useCallback(() => {
    pushUndo()
    setTasks(prev => prev.filter(t => !t.completed))
  }, [pushUndo])

  const clearPastEvents = useCallback(() => {
    pushUndo()
    setEvents(prev => prev.filter(e => {
      if (e.date !== selectedDate) return true
      const isPast = isToday ? timeToMinutes(e.end) <= currentTime : selectedDate < todayStr
      return !isPast
    }))
  }, [pushUndo, selectedDate, isToday, currentTime, todayStr])

  // ── Handlers: Drag and Drop ───────────────────────────────────────────────

  const handleDragStart = (e, taskId) => {
    setDraggedTaskId(taskId)
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', taskId)
  }

  const handleDragOver = (e, taskId) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    if (taskId !== dragOverTaskId) setDragOverTaskId(taskId)
  }

  const handleDrop = (e, targetTaskId) => {
    e.preventDefault()
    if (draggedTaskId === null || draggedTaskId === targetTaskId) return
    pushUndo()
    setTasks(prev => {
      const newTasks = [...prev]
      const fromIdx = newTasks.findIndex(t => t.id === draggedTaskId)
      const toIdx = newTasks.findIndex(t => t.id === targetTaskId)
      const [moved] = newTasks.splice(fromIdx, 1)
      newTasks.splice(toIdx, 0, moved)
      return newTasks
    })
    setDraggedTaskId(null)
    setDragOverTaskId(null)
  }

  const handleDragEnd = () => {
    setDraggedTaskId(null)
    setDragOverTaskId(null)
  }

  // ── Handlers: Tags ────────────────────────────────────────────────────────

  const addTag = () => {
    setTags(prev => [...prev, { id: Date.now(), name: 'New Tag', color: '#94a3b8' }])
  }

  const updateTag = (tagId, updates) => {
    setTags(prev => prev.map(t => t.id === tagId ? { ...t, ...updates } : t))
  }

  const deleteTag = (tagId) => {
    pushUndo()
    setTags(prev => prev.filter(t => t.id !== tagId))
    setTasks(prev => prev.map(t => t.tagId === tagId ? { ...t, tagId: null } : t))
    setEvents(prev => prev.map(e => e.tagId === tagId ? { ...e, tagId: null } : e))
  }

  const LOCAL_ONLY_SETTINGS = ['zoomLevel', 'fitMode', 'debugMode', 'debugTimeOffset']

  const exportSettings = () => {
    const transferable = Object.fromEntries(
      Object.entries(settings).filter(([k]) => !LOCAL_ONLY_SETTINGS.includes(k))
    )
    const data = JSON.stringify({ settings: transferable, tags, version: 1 }, null, 2)
    const blob = new Blob([data], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'timekerper-settings.json'
    a.click()
    URL.revokeObjectURL(url)
  }

  const exportTasks = () => {
    const incompleteTasks = tasks.filter(t => !t.completed)
    const lines = incompleteTasks.map(task => {
      const duration = task.adjustedDuration ?? task.duration
      return `${task.name} ${duration}`
    }).join('\n')
    navigator.clipboard.writeText(lines)
    setCopiedFeedback('tasks')
    setTimeout(() => setCopiedFeedback(f => f === 'tasks' ? null : f), 1500)
  }

  const exportEvents = () => {
    const todayStr = getTodayStr()
    const futureEvents = events.filter(e => e.date >= todayStr)
    const lines = futureEvents
      .sort((a, b) => a.date < b.date ? -1 : a.date > b.date ? 1 : timeToMinutes(a.start) - timeToMinutes(b.start))
      .map(e => {
        const tagName = getTagName(e.tagId)
        const tagSuffix = tagName ? ` [${tagName}]` : ''
        return `${e.name} ${e.start}-${e.end} ${e.date}${tagSuffix}`
      })
      .join('\n')
    navigator.clipboard.writeText(lines)
    setCopiedFeedback('events')
    setTimeout(() => setCopiedFeedback(f => f === 'events' ? null : f), 1500)
  }

  const importBulkEvents = () => {
    const lines = bulkEventText.split('\n').map(l => l.trim()).filter(l => l.length > 0)
    if (lines.length === 0) return
    pushUndo()
    const parsed = []
    for (const line of lines) {
      const match = line.match(/^(.+?)\s+(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s+(\d{4}-\d{2}-\d{2})(?:\s+\[(.+?)\])?$/)
      if (match) {
        const tagName = match[5]
        const tagId = tagName ? (tags.find(t => t.name === tagName)?.id ?? null) : null
        parsed.push({
          id: Date.now() + parsed.length,
          name: match[1],
          start: match[2].padStart(5, '0'),
          end: match[3].padStart(5, '0'),
          date: match[4],
          tagId,
        })
      }
    }
    // Deduplicate: match on name, start, end, date (ignore tag). If new event has tag, apply it.
    let updatedExisting = [...events]
    const toAdd = []
    let skipped = 0
    for (const ne of parsed) {
      const existingIdx = updatedExisting.findIndex(ex =>
        ex.name === ne.name &&
        ex.start === ne.start &&
        ex.end === ne.end &&
        ex.date === ne.date
      )
      if (existingIdx >= 0) {
        // Duplicate found - apply tag if new event has one
        if (ne.tagId != null && updatedExisting[existingIdx].tagId == null) {
          updatedExisting[existingIdx] = { ...updatedExisting[existingIdx], tagId: ne.tagId }
        }
        skipped++
      } else {
        toAdd.push(ne)
      }
    }
    if (toAdd.length > 0 || updatedExisting !== events) {
      setEvents([...updatedExisting, ...toAdd])
    }
    if (skipped > 0 && toAdd.length === 0) {
      alert(`All ${skipped} event${skipped !== 1 ? 's' : ''} already exist. Nothing imported.`)
    } else if (skipped > 0) {
      alert(`Added ${toAdd.length} event${toAdd.length !== 1 ? 's' : ''}. Skipped ${skipped} duplicate${skipped !== 1 ? 's' : ''}.`)
    }
    setBulkEventText('')
    setShowBulkEventEntry(false)
  }

  const importSettings = (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      try {
        const data = JSON.parse(ev.target.result)
        if (data.settings) {
          const filtered = Object.fromEntries(
            Object.entries(data.settings).filter(([k]) => !LOCAL_ONLY_SETTINGS.includes(k))
          )
          setSettings(prev => ({ ...prev, ...filtered }))
        }
        if (data.tags && Array.isArray(data.tags)) setTags(data.tags)
      } catch { /* ignore invalid files */ }
    }
    reader.readAsText(file)
    e.target.value = ''
  }

  const finishIcsImport = (filteredEvents, catRules) => {
    // Apply category exclusion
    const included = filteredEvents.filter(ev => {
      if (!ev.categories || ev.categories.length === 0) return true
      return !ev.categories.some(cat =>
        catRules.some(r => r.include === false && r.category.toLowerCase() === cat.toLowerCase())
      )
    })
    if (included.length === 0) {
      alert('No events to import after applying category filters.')
      return
    }
    pushUndo()
    const newEvents = included.map((ev, i) => {
      // Apply category → tag mapping
      let tagId = null
      if (ev.categories && ev.categories.length > 0) {
        for (const cat of ev.categories) {
          const rule = catRules.find(r =>
            r.include !== false && r.tagId && r.category.toLowerCase() === cat.toLowerCase()
          )
          if (rule) { tagId = rule.tagId; break }
        }
      }
      return {
        id: Date.now() + i,
        name: ev.name,
        start: ev.start,
        end: ev.end,
        date: ev.date,
        tagId,
        icsImported: true,
      }
    })
    // Decide whether to clear previous imports
    const replacePref = settings.icsReplaceOnImport
    if (replacePref === 'ask') {
      setIcsReplaceConfirm({ newEvents })
      return
    }
    const shouldReplace = replacePref === 'yes' || replacePref === true
    applyIcsImport(newEvents, shouldReplace)
  }

  const applyIcsImport = (newEvents, shouldReplace) => {
    const baseEvents = shouldReplace
      ? events.filter(e => !e.icsImported)
      : events
    // Deduplicate: match on name, time, date (ignore tag). If new event has tag, apply it.
    let updatedBase = [...baseEvents]
    const toAdd = []
    let skipped = 0
    for (const ne of newEvents) {
      const existingIdx = updatedBase.findIndex(ex =>
        ex.name === ne.name &&
        ex.start === ne.start &&
        ex.end === ne.end &&
        ex.date === ne.date
      )
      if (existingIdx >= 0) {
        // Duplicate found - apply tag if new event has one
        if (ne.tagId != null && updatedBase[existingIdx].tagId == null) {
          updatedBase[existingIdx] = { ...updatedBase[existingIdx], tagId: ne.tagId }
        }
        skipped++
      } else {
        toAdd.push(ne)
      }
    }
    if (toAdd.length === 0 && updatedBase === baseEvents) {
      alert(`All ${skipped} event${skipped !== 1 ? 's' : ''} already exist. Nothing imported.`)
      if (shouldReplace) setEvents(baseEvents)
      return
    }
    setEvents([...updatedBase, ...toAdd])
    if (skipped > 0) {
      alert(`Imported ${toAdd.length} event${toAdd.length !== 1 ? 's' : ''}. Skipped ${skipped} duplicate${skipped !== 1 ? 's' : ''}.`)
    }
  }

  const importIcsFile = (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      try {
        const parsed = parseIcsFile(ev.target.result)
        // Filter by status + date + meetings-only, but defer category rules to dialog
        const settingsNoCat = { ...settings, icsCategoryRules: [] }
        const filtered = filterIcsEvents(parsed, settingsNoCat, minDate, maxDate)
        if (filtered.length === 0) {
          alert('No events to import. Check your status filter settings or date range.')
          return
        }

        // Collect unique categories and counts
        const catCounts = {}
        let uncategorized = 0
        for (const fev of filtered) {
          if (fev.categories && fev.categories.length > 0) {
            for (const cat of fev.categories) {
              catCounts[cat] = (catCounts[cat] || 0) + 1
            }
          } else {
            uncategorized++
          }
        }
        const categoryList = Object.keys(catCounts).sort()

        if (categoryList.length === 0) {
          // No categories — import directly
          finishIcsImport(filtered, [])
          return
        }

        // Check if all categories are covered by saved rules
        const savedRules = settings.icsCategoryRules || []
        const allCovered = categoryList.every(cat =>
          savedRules.some(r => r.category.toLowerCase() === cat.toLowerCase())
        )

        if (allCovered) {
          // All known — auto-apply saved rules
          finishIcsImport(filtered, savedRules)
          return
        }

        // New categories found — show dialog
        const mappings = categoryList.map(cat => {
          const existing = savedRules.find(r => r.category.toLowerCase() === cat.toLowerCase())
          return existing
            ? { category: cat, include: existing.include, tagId: existing.tagId }
            : { category: cat, include: true, tagId: null }
        })
        setIcsCategoryMappings(mappings)
        setIcsCategoryModal({ mode: 'import', filteredEvents: filtered, catCounts, uncategorized })
      } catch {
        alert('Could not parse the .ics file. Make sure it is a valid iCalendar file.')
      }
    }
    reader.readAsText(file)
    e.target.value = ''
  }

  const openCategoryMapping = () => {
    setIcsCategoryMappings([...(settings.icsCategoryRules || [])])
    setIcsCategoryModal({ mode: 'settings' })
  }

  const handleTagDragStart = (e, tagId) => {
    setDraggedTagId(tagId)
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', tagId)
  }

  const handleTagDragOver = (e, tagId) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    if (tagId !== dragOverTagId) setDragOverTagId(tagId)
  }

  const handleTagDrop = (e, targetTagId) => {
    e.preventDefault()
    if (draggedTagId === null || draggedTagId === targetTagId) return
    setTags(prev => {
      const newTags = [...prev]
      const fromIdx = newTags.findIndex(t => t.id === draggedTagId)
      const toIdx = newTags.findIndex(t => t.id === targetTagId)
      const [moved] = newTags.splice(fromIdx, 1)
      newTags.splice(toIdx, 0, moved)
      return newTags
    })
    setDraggedTagId(null)
    setDragOverTagId(null)
  }

  const handleTagDragEnd = () => {
    setDraggedTagId(null)
    setDragOverTagId(null)
  }

  // ── Handlers: Zoom ────────────────────────────────────────────────────────

  const zoomIn = () => {
    const next = ZOOM_LEVELS.find(z => z > settings.zoomLevel)
    if (next != null) {
      updateSetting('zoomLevel', next)
      updateSetting('fitMode', false)
    }
  }

  const zoomOut = () => {
    const prev = [...ZOOM_LEVELS].reverse().find(z => z < settings.zoomLevel)
    if (prev != null) {
      updateSetting('zoomLevel', prev)
      updateSetting('fitMode', false)
    }
  }

  const fitToHeight = useCallback(() => {
    if (!calendarContainerRef.current) return
    const containerHeight = calendarContainerRef.current.clientHeight
    const totalMinutes = extEndMin - extStartMin
    if (totalMinutes <= 0) return
    const fitZoom = Math.max(0.1, Math.min(5, containerHeight / totalMinutes))
    updateSetting('zoomLevel', Math.floor(fitZoom * 100) / 100)
    updateSetting('fitMode', true)
  }, [extEndMin, extStartMin, updateSetting])

  // ── Effects: Fit Mode Window Resize ──────────────────────────────────────

  useEffect(() => {
    if (!settings.fitMode) return
    const handleResize = () => {
      fitToHeight()
    }
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [settings.fitMode, fitToHeight])

  // ── Form Helpers ──────────────────────────────────────────────────────────

  const handleTaskKeyDown = (e) => {
    // For textarea: Ctrl+Enter or if single line, Enter
    if (e.key === 'Enter' && (e.ctrlKey || (!editingTask && !taskName.includes('\n') && e.target.tagName !== 'TEXTAREA'))) {
      saveTask()
    }
    if (e.key === 'Enter' && editingTask) {
      saveTask()
    }
  }
  const handleEventKeyDown = (e) => {
    if (e.key === 'Enter') { e.preventDefault(); eventStartRef.current?.focus() }
  }
  const handleEventStartKeyDown = (e) => {
    if (e.key === 'Enter') { e.preventDefault(); eventEndRef.current?.focus() }
  }
  const handleEventEndKeyDown = (e) => {
    if (e.key === 'Enter') { e.preventDefault(); saveEvent() }
  }

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="app">
      {/* ── Header (pinned) ────────────────────────────────────────────── */}
      <header className="header">
        <h1>Timekerper</h1>
        <div className="header-right">
          <div className="undo-redo">
            <button onClick={undo} disabled={!canUndo} title="Undo (Ctrl+Z)">↩</button>
            <button onClick={redo} disabled={!canRedo} title="Redo (Ctrl+Shift+Z)">↪</button>
          </div>
          <div className="zoom-controls">
            <button onClick={zoomOut} disabled={settings.zoomLevel <= ZOOM_LEVELS[0]}>−</button>
            <span className="zoom-label">{Math.round(zoom * 100)}%</span>
            <button onClick={zoomIn} disabled={settings.zoomLevel >= ZOOM_LEVELS[ZOOM_LEVELS.length - 1]}>+</button>
            <button onClick={fitToHeight} className="fit-btn" title="Fit calendar to window height">Fit</button>
          </div>
          <div className="view-toggle">
            <button className={calendarView === '1day' ? 'active' : ''} onClick={() => switchView('1day')}>Day</button>
            <button className={calendarView === '2day' ? 'active' : ''} onClick={() => switchView('2day')}>2</button>
            <button className={calendarView === '3day' ? 'active' : ''} onClick={() => switchView('3day')}>3</button>
            <button className={calendarView === '4day' ? 'active' : ''} onClick={() => switchView('4day')}>4</button>
            <button className={calendarView === '5day' ? 'active' : ''} onClick={() => switchView('5day')}>5</button>
          </div>
          <div className="view-menu-wrapper" ref={viewMenuRef}>
            <button
              className="view-menu-btn"
              onClick={() => setShowViewMenu(v => !v)}
              title="View options"
            >
              View &#9662;
            </button>
            {showViewMenu && (
              <div className="view-menu-dropdown">
                <div className="view-menu-section">
                  <span className="view-menu-label">Zoom</span>
                  <div className="view-menu-row">
                    <button onClick={zoomOut} disabled={settings.zoomLevel <= ZOOM_LEVELS[0]}>−</button>
                    <span className="view-menu-zoom-level">{Math.round(zoom * 100)}%</span>
                    <button onClick={zoomIn} disabled={settings.zoomLevel >= ZOOM_LEVELS[ZOOM_LEVELS.length - 1]}>+</button>
                    <button onClick={fitToHeight} className="fit-btn">Fit</button>
                  </div>
                </div>
                <div className="view-menu-section">
                  <span className="view-menu-label">Layout</span>
                  <div className="view-menu-row">
                    <button className={calendarView === '1day' ? 'active' : ''} onClick={() => { switchView('1day'); setShowViewMenu(false) }}>Day</button>
                    <button className={calendarView === '2day' ? 'active' : ''} onClick={() => { switchView('2day'); setShowViewMenu(false) }}>2</button>
                    <button className={calendarView === '3day' ? 'active' : ''} onClick={() => { switchView('3day'); setShowViewMenu(false) }}>3</button>
                    <button className={calendarView === '4day' ? 'active' : ''} onClick={() => { switchView('4day'); setShowViewMenu(false) }}>4</button>
                    <button className={calendarView === '5day' ? 'active' : ''} onClick={() => { switchView('5day'); setShowViewMenu(false) }}>5</button>
                  </div>
                </div>
              </div>
            )}
          </div>
          <div className="date-nav">
            <button className="date-nav-btn" onClick={goToPreviousDay} disabled={!canGoBack} title="Previous day (←)">&#8249;</button>
            <span className="date-nav-label">
              <span className="date-long">{formatDateHeader(selectedDate)}</span>
              <span className="date-short">{formatDateHeaderCompact(selectedDate)}</span>
            </span>
            <button className="date-nav-btn" onClick={goToNextDay} disabled={!canGoForward} title="Next day (→)">&#8250;</button>
            <button className="today-btn" onClick={goToToday} disabled={isToday} title="Go to today (T)">Today</button>
          </div>
          <button
            className="settings-btn"
            onClick={() => setShowSettingsModal(true)}
            title="Settings"
          >
            <span className="settings-label-long">Settings</span>
            <span className="settings-label-short">&#9881;</span>
          </button>
        </div>
      </header>

      <main className="main-content">
        {/* ── Left Panel ────────────────────────────────────────────────── */}
        <aside className="task-panel" style={{ width: `${panelWidth}px`, '--panel-height': `${panelHeight}px` }}>
          {/* Active Task Control (pinned) — visible when today is on screen */}
          {todayVisible ? (
            activeTaskId && activeTask ? (
              <div className="active-task-panel compact">
                <div className="active-task-header">
                  <h2>Working On</h2>
                  <div className="active-task-actions">
                    <button className="btn-done" onClick={completeActiveTask}>Done</button>
                    <button className="btn-pause" onClick={pauseActiveTask}>Pause</button>
                    <button className="btn-cancel" onClick={cancelActiveTask}>Cancel</button>
                  </div>
                </div>
                <span className="active-task-name">{activeTask.name}</span>
                <div className="active-task-row">
                  <div className={`timer ${isOverEstimate ? 'over' : ''}`}>
                    <span className="elapsed">{formatElapsed(elapsedMinutes)}</span>
                    <span className="estimate">
                      / {formatElapsed(activeTask.adjustedDuration ?? activeTask.duration)}
                    </span>
                    {activeTask.adjustedDuration && activeTask.adjustedDuration !== activeTask.duration && (
                      <span className="original-estimate">
                        (orig {formatElapsed(activeTask.duration)})
                      </span>
                    )}
                    {isOverEstimate && (
                      <span className="over-notice">
                        +{formatElapsed(elapsedMinutes - (activeTask.adjustedDuration ?? activeTask.duration))} over
                      </span>
                    )}
                  </div>
                  <div className="time-adjust-btns">
                    <button onClick={() => adjustTaskTime(-15)}>-15</button>
                    <button onClick={() => adjustTaskTime(-5)}>-5</button>
                    <button onClick={() => adjustTaskTime(5)}>+5</button>
                    <button onClick={() => adjustTaskTime(15)}>+15</button>
                  </div>
                </div>
              </div>
            ) : (
              <div className="start-task-panel compact">
                {firstIncompleteTask ? (
                  <div className="start-task-row">
                    <div className="start-task-info">
                      <span className="next-task-label">Next:</span>
                      <span className="next-task-name">{firstIncompleteTask.name}</span>
                      <span className="next-task-duration">
                        {formatElapsed(firstIncompleteTask.adjustedDuration ?? firstIncompleteTask.duration)}
                        {firstIncompleteTask.pausedElapsed > 0 && (
                          <span className="paused-time"> ({formatElapsed(firstIncompleteTask.pausedElapsed)} done)</span>
                        )}
                      </span>
                    </div>
                    <button className="btn-start" onClick={startTask}>
                      {firstIncompleteTask.pausedElapsed > 0 ? 'Resume' : 'Start'}
                    </button>
                  </div>
                ) : (
                  <p className="no-tasks">All tasks completed!</p>
                )}
              </div>
            )
          ) : (
            <div className="date-view-banner">
              <span className="date-view-label">
                {selectedDate < todayStr ? 'Viewing past days' : 'Viewing future days'}
              </span>
            </div>
          )}

          {/* Scrollable list section */}
          <div className="panel-scroll">
            {/* Task List */}
            <div className="panel-section">
              <div className="panel-section-header">
                <h2>Tasks</h2>
                <span className="task-summary">
                  {tasks.filter(t => !t.completed).length} tasks,{' '}
                  {tasks.filter(t => !t.completed).reduce((sum, t) => sum + (t.adjustedDuration ?? t.duration), 0)} min
                </span>
                {tasks.some(t => t.completed) && (
                  <button className="section-toggle" onClick={() => setHideCompleted(h => !h)}>
                    {hideCompleted ? `Show completed (${tasks.filter(t => t.completed).length})` : 'Hide completed'}
                  </button>
                )}
              </div>
              <ul className="task-list">
                {tasks.map((task, index) => {
                  if (hideCompleted && task.completed) return null
                  const isNext = isToday && !task.completed && index === tasks.findIndex(t => !t.completed)
                  const tagColor = getTagColor(task.tagId)
                  return (
                    <li
                      key={task.id}
                      draggable={!task.completed}
                      onDragStart={e => handleDragStart(e, task.id)}
                      onDragOver={e => handleDragOver(e, task.id)}
                      onDrop={e => handleDrop(e, task.id)}
                      onDragEnd={handleDragEnd}
                      className={[
                        'task-item',
                        task.completed && 'completed',
                        task.id === activeTaskId && 'active',
                        isNext && !task.completed && 'next-up',
                        dragOverTaskId === task.id && 'drag-over',
                        draggedTaskId === task.id && 'dragging',
                      ].filter(Boolean).join(' ')}
                      title={task.name}
                    >
                      <span className="drag-handle" title="Drag to reorder">⋮⋮</span>
                      <input
                        type="checkbox"
                        checked={task.completed}
                        onChange={() => toggleTaskComplete(task.id)}
                        className="task-checkbox"
                      />
                      {tagColor && (
                        <span className="tag-dot" style={{ backgroundColor: tagColor }} title={getTagName(task.tagId)} />
                      )}
                      <span className={`task-name${settings.wrapListNames ? ' wrap' : ''}`} onClick={() => openEditTask(task)}>
                        {task.name}
                      </span>
                      <span className="list-end">
                        <span className="task-duration" onClick={() => openEditTask(task)} style={{ cursor: 'pointer' }}>
                          {(task.adjustedDuration && task.adjustedDuration !== task.duration)
                            ? `${task.adjustedDuration}m`
                            : `${task.duration}m`
                          }
                        </span>
                        {task.pausedElapsed > 0 && !task.completed && (
                          <span className="paused-badge" title="Paused">||</span>
                        )}
                        <button className="action-btn" onClick={() => duplicateTask(task)} title="Duplicate">⧉</button>
                        <button className="action-btn delete" onClick={() => deleteTask(task.id)} title="Delete">×</button>
                      </span>
                    </li>
                  )
                })}
              </ul>
              <div className="panel-section-actions">
                <button className="add-btn" onClick={openAddTask}>+ Add Task</button>
                {tasks.some(t => !t.completed) && (
                  <button className="clear-btn" onClick={exportTasks}>{copiedFeedback === 'tasks' ? 'Copied!' : 'Export Tasks'}</button>
                )}
                {tasks.some(t => t.completed) && (
                  <button className="clear-btn" onClick={clearCompletedTasks}>Clear Completed</button>
                )}
                {tasks.length > 0 && (
                  <button className="clear-btn" onClick={clearAllTasks}>Clear All</button>
                )}
              </div>
            </div>

            {/* Event List */}
            <div className="panel-section">
              <div className="panel-section-header">
                <h2>{isToday ? 'Events' : `Events (${new Date(selectedDate + 'T12:00:00').toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })})`}</h2>
                {events.some(e => e.icsImported) && (() => {
                  const dayEvents = events.filter(e => e.date === selectedDate)
                  const visible = dayEvents.filter(e => {
                    if (hidePastEvents && isToday && timeToMinutes(e.end) <= currentTime) return false
                    return true
                  })
                  const hiddenBySource = eventSourceFilter === 'manual'
                    ? visible.filter(e => e.icsImported).length
                    : eventSourceFilter === 'outlook'
                      ? visible.filter(e => !e.icsImported).length
                      : 0
                  return (
                    <button className="source-filter-toggle" onClick={() => setEventSourceFilter(f => f === 'all' ? 'manual' : f === 'manual' ? 'outlook' : 'all')}>
                      {eventSourceFilter === 'all'
                        ? 'All sources'
                        : eventSourceFilter === 'manual'
                          ? `Manual only${hiddenBySource ? ` (${hiddenBySource} hidden)` : ''}`
                          : `Outlook only${hiddenBySource ? ` (${hiddenBySource} hidden)` : ''}`}
                    </button>
                  )
                })()}
                {isToday && events.filter(e => e.date === selectedDate).some(e => timeToMinutes(e.end) <= currentTime) && (
                  <button className="section-toggle" onClick={() => setHidePastEvents(h => !h)}>
                    {hidePastEvents ? `Show past (${events.filter(e => e.date === selectedDate && timeToMinutes(e.end) <= currentTime).length})` : 'Hide past'}
                  </button>
                )}
              </div>
              <ul className="event-list">
                {events.filter(e => e.date === selectedDate).sort((a, b) => timeToMinutes(a.start) - timeToMinutes(b.start)).map(event => {
                  if (eventSourceFilter === 'manual' && event.icsImported) return null
                  if (eventSourceFilter === 'outlook' && !event.icsImported) return null
                  const isPast = isToday ? timeToMinutes(event.end) <= currentTime : selectedDate < todayStr
                  if (hidePastEvents && isPast) return null
                  const tagColor = getTagColor(event.tagId)
                  return (
                    <li key={event.id} className={`event-item${isPast ? ' past-event' : ''}`} onClick={() => openEditEvent(event)} title={`${event.name} (${formatBlockTimeRange(event.start, event.end, false)})`}>
                      {tagColor && (
                        <span className="tag-dot" style={{ backgroundColor: tagColor }} title={getTagName(event.tagId)} />
                      )}
                      {event.icsImported && <span className="ics-icon" title="Imported from Outlook">✉</span>}
                      <span className={`event-name${settings.wrapListNames ? ' wrap' : ''}`}>{event.name}</span>
                      <span className="list-end">
                        <span className="event-time">{formatBlockTimeRange(event.start, event.end, false)}</span>
                        <button
                          className="action-btn delete"
                          onClick={(e) => { e.stopPropagation(); deleteEvent(event.id) }}
                          title="Delete"
                        >×</button>
                      </span>
                    </li>
                  )
                })}
              </ul>
              {showBulkEventEntry && (
                <div className="bulk-event-entry">
                  <textarea
                    value={bulkEventText}
                    onChange={e => setBulkEventText(e.target.value)}
                    placeholder={`Paste events (one per line):\nStaff Meeting 10:00-12:15 ${getTodayStr()} [Internal]\nTeam meeting 14:00-14:30 ${getTodayStr()}`}
                    rows={4}
                    autoFocus
                  />
                  <div className="bulk-event-actions">
                    <button className="btn-primary" onClick={importBulkEvents} disabled={!bulkEventText.trim()}>Add Events</button>
                    <button className="btn-secondary" onClick={() => { setShowBulkEventEntry(false); setBulkEventText('') }}>Cancel</button>
                  </div>
                </div>
              )}
              <div className="panel-section-actions">
                <button className="add-btn secondary" onClick={openAddEvent}>+ Add Event</button>
                <button className="clear-btn" onClick={() => setShowBulkEventEntry(s => !s)}>Bulk Add</button>
                <button className="clear-btn ics-import-btn" onClick={() => icsFileRef.current?.click()}>Import .ics</button>
                <input ref={icsFileRef} type="file" accept=".ics,.ical,.ifb,.icalendar" onChange={importIcsFile} style={{ display: 'none' }} />
                {events.length > 0 && (
                  <button className="clear-btn" onClick={exportEvents}>{copiedFeedback === 'events' ? 'Copied!' : 'Export Events'}</button>
                )}
                {events.filter(e => e.date === selectedDate).some(e => isToday ? timeToMinutes(e.end) <= currentTime : selectedDate < todayStr) && (
                  <button className="clear-btn" onClick={clearPastEvents}>Clear Past</button>
                )}
                {events.some(e => e.date === selectedDate) && (
                  <button className="clear-btn" onClick={clearAllEvents}>Clear All</button>
                )}
              </div>
            </div>
          </div>
        </aside>

        {/* ── Resize Handle ──────────────────────────────────────────────── */}
        <div className="resize-handle resize-handle-h" onMouseDown={startResize} />
        <div className="resize-handle resize-handle-v" onMouseDown={startResizeVertical} />

        {/* ── Calendar View ─────────────────────────────────────────────── */}
        <section className="calendar-panel">
          {/* Day column headers — multi-day view only */}
          {viewDates.length > 1 && (
            <div className="day-headers">
              <div className="day-header-spacer" />
              {viewDates.map(date => (
                <div key={date}
                     className={`day-header${date === todayStr ? ' today' : ''}${date === selectedDate ? ' focused' : ''}${date < todayStr ? ' past' : ''}`}
                     onClick={() => setSelectedDate(date)}>
                  {formatShortDateHeader(date)}
                </div>
              ))}
            </div>
          )}

          <div className="calendar-container" ref={calendarContainerRef}>
            <div className="time-labels" style={{ height: `${gridHeight}px` }}>
              {calendarHours.map(hour => (
                <div key={hour} className="time-label" style={{
                  position: 'absolute',
                  top: `${(hour * 60 - extStartMin) * zoom}px`,
                  height: `${60 * zoom}px`,
                }}>
                  {hour > 12 ? hour - 12 : hour === 0 ? 12 : hour}:00 {hour >= 12 ? 'PM' : 'AM'}
                </div>
              ))}
            </div>

            {viewDates.map((date, dayIndex) => {
              const daySchedule = schedules[dayIndex]
              const dayLayout = eventLayoutsPerDay[dayIndex]
              const dayFragCounts = taskFragCountsPerDay[dayIndex]
              const dayIsToday = date === todayStr

              return (
                <div key={date}
                     className={`calendar-grid day-column${dayIsToday ? ' today' : ''}${date === selectedDate && viewDates.length > 1 ? ' focused' : ''}${date < todayStr ? ' past' : ''}`}
                     style={{
                       height: `${gridHeight}px`,
                       '--block-title-size': FONT_SIZE_OPTIONS[settings.calendarFontSize]?.title || '0.8rem',
                       '--block-time-size': FONT_SIZE_OPTIONS[settings.calendarFontSize]?.time || '0.65rem',
                     }}
                     onClick={() => viewDates.length > 1 && setSelectedDate(date)}>
                  {calendarHours.map((hour, i) => (
                    <div key={i} className="hour-line" style={{ top: `${(hour * 60 - extStartMin) * zoom}px` }} />
                  ))}

                  {workdayStartMin > extStartMin && (
                    <div className="dim-zone" style={{ top: 0, height: `${(workdayStartMin - extStartMin) * zoom}px` }} />
                  )}
                  {workdayEndMin < extEndMin && (
                    <div className="dim-zone" style={{ top: `${(workdayEndMin - extStartMin) * zoom}px`, height: `${(extEndMin - workdayEndMin) * zoom}px` }} />
                  )}

                  {dayIsToday && currentTime >= extStartMin && currentTime <= extEndMin && (
                    <div className="current-time-line" style={{ top: `${(currentTime - extStartMin) * zoom}px` }}>
                      <span className="current-time-label">Now</span>
                    </div>
                  )}

                  {daySchedule.map((block, index) => {
                    const isPause = block.type === 'pause'
                    const isTask = block.type === 'task'
                    const tagColor = getTagColor(block.tagId)
                    const heightPx = getBlockHeightPx(block)
                    const isCompact = heightPx < 40
                    const isTiny = heightPx < 25
                    const baseColor = isPause ? '#f59e0b' : (tagColor || (isTask ? settings.defaultTaskColor : settings.defaultEventColor))
                    const blockAlpha = isPause ? 0.25 : (isTask ? 0.10 : 1)
                    const textColor = isPause
                      ? (settings.darkMode ? '#fbbf24' : '#92400e')
                      : getTextColor(baseColor, blockAlpha, settings.darkMode)
                    const blockName = isPause ? block.name : (isTask ? block.taskName : block.name)

                    return (
                      <div
                        key={`${block.type}-${block.taskId || block.id}-${index}`}
                        className={[
                          'calendar-block',
                          `${block.type}-block`,
                          block.isActive && 'active',
                          block.isPast && 'past',
                          block.isCompleted && 'completed-block',
                          block.isPausedRemaining && 'paused-remaining',
                          isCompact && 'compact',
                          isTiny && 'tiny',
                        ].filter(Boolean).join(' ')}
                        style={{
                          ...getBlockStyle(block, index, dayLayout),
                          ...(isPause ? { color: textColor } : {
                            backgroundColor: isTask ? blendWithSurface(baseColor, 0.10, settings.darkMode) : baseColor,
                            color: textColor,
                            ...(isTask ? {
                              borderLeft: `10px solid ${baseColor}`,
                              borderRadius: (() => {
                                const total = dayFragCounts[block.taskId] || 1
                                const isFirst = block.blockIndex === 0
                                const isLast = block.blockIndex === total - 1
                                const tl = isFirst ? '5px' : '0'
                                const bl = isLast ? '5px' : '0'
                                return `${tl} 5px 5px ${bl}`
                              })(),
                            } : {}),
                          }),
                        }}
                        title={`${blockName}\n${formatTime(block.start)} - ${formatTime(block.end)}`}
                        onClick={(e) => {
                          e.stopPropagation()
                          if (block.type === 'task') {
                            const task = tasks.find(t => t.id === block.taskId)
                            if (task) openEditTask(task)
                          } else if (block.type === 'event') {
                            const event = events.find(e => e.id === block.id)
                            if (event) openEditEvent(event)
                          }
                        }}
                      >
                        <div className="block-content">
                          <span className="block-name">
                            {block.icsImported && <span className="ics-icon">✉</span>}
                            {block.continuesBefore && '\u2192 '}
                            {blockName}
                            {block.continuesAfter && ' \u2192'}
                            {block.isActive && ' \u23F1'}
                          </span>
                          <span className="block-time">
                            {formatBlockTimeRange(block.start, block.end, isTask)}
                          </span>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )
            })}
          </div>
        </section>
      </main>

      {/* ── Task Modal ────────────────────────────────────────────────────── */}
      {showTaskModal && (
        <div className="modal-overlay" onMouseDown={() => {
          if (taskName.trim()) { saveTask() } else { setShowTaskModal(false) }
        }}>
          <div className="modal" onMouseDown={e => e.stopPropagation()}>
            <h3>{editingTask ? 'Edit Task' : 'Add Tasks'}</h3>
            <div className="form-group">
              <label>
                {editingTask ? 'Task Name' : 'Task Name(s)'}
                {!editingTask && <span className="label-hint"> — one per line for bulk add</span>}
              </label>
              {editingTask ? (
                <input
                  type="text"
                  value={taskName}
                  onChange={e => setTaskName(e.target.value)}
                  onKeyDown={handleTaskKeyDown}
                  placeholder="What do you need to do?"
                  autoFocus
                />
              ) : (
                <textarea
                  value={taskName}
                  onChange={e => setTaskName(e.target.value)}
                  onKeyDown={handleTaskKeyDown}
                  placeholder={settings.smartDuration
                    ? "Enter tasks (one per line):\nTech note review\nSherlock #12345678 75\nFirewatch investigation 60"
                    : "Enter tasks (one per line)"}
                  rows={4}
                  autoFocus
                />
              )}
              {!editingTask && settings.smartDuration && (
                <p className="form-hint">Numbers at the end of a line set the duration (e.g., "task name 30" = 30 min)</p>
              )}
            </div>
            <div className="form-group">
              <label>
                {editingTask ? 'Duration (minutes)' : 'Default Duration (minutes)'}
                {!editingTask && settings.smartDuration && (
                  <span className="label-hint"> — used when no number is specified</span>
                )}
              </label>
              <input
                type="number"
                value={taskDuration}
                onChange={e => setTaskDuration(Number(e.target.value))}
                onKeyDown={editingTask ? handleTaskKeyDown : undefined}
                min="5"
                max="480"
              />
            </div>
            <div className="form-group">
              <label>Tag</label>
              <div className="tag-selector">
                <button
                  className={`tag-option no-tag ${taskTag === null ? 'selected' : ''}`}
                  onClick={() => setTaskTag(null)}
                  title="No tag"
                >×</button>
                {tags.map(tag => (
                  <button
                    key={tag.id}
                    className={`tag-option ${taskTag === tag.id ? 'selected' : ''}`}
                    onClick={() => setTaskTag(tag.id)}
                    style={{ backgroundColor: tag.color }}
                    title={tag.name}
                  />
                ))}
              </div>
            </div>
            {!editingTask && (
              <label className="toggle-row">
                <input type="checkbox" checked={addTaskToTop} onChange={e => setAddTaskToTop(e.target.checked)} />
                <span>Add to top of list</span>
              </label>
            )}
            <div className="modal-actions">
              {editingTask && (
                <button className="btn-delete" onClick={() => { deleteTask(editingTask.id); setShowTaskModal(false) }}>Delete</button>
              )}
              <button className="btn-secondary" onClick={() => setShowTaskModal(false)}>Cancel</button>
              <button className="btn-primary" onClick={saveTask}>
                {editingTask ? 'Save Changes' : 'Add Task(s)'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Event Modal ───────────────────────────────────────────────────── */}
      {showEventModal && (
        <div className="modal-overlay" onMouseDown={() => saveEvent()}>
          <div className="modal" onMouseDown={e => e.stopPropagation()}>
            <h3>{editingEvent ? 'Edit Event' : 'Add Event'}</h3>
            <div className="form-group">
              <label>Event Name</label>
              <input
                type="text"
                value={eventName}
                onChange={e => setEventName(e.target.value)}
                onKeyDown={handleEventKeyDown}
                placeholder="Meeting name"
                autoFocus
              />
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Start</label>
                <input type="time" value={eventStart} onChange={e => handleEventStartChange(e.target.value)} ref={eventStartRef} onKeyDown={handleEventStartKeyDown} />
              </div>
              <div className="form-group">
                <label>End</label>
                <input type="time" value={eventEnd} onChange={e => handleEventEndChange(e.target.value)} ref={eventEndRef} onKeyDown={handleEventEndKeyDown} />
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Date</label>
                <input type="date" value={eventDate} onChange={e => setEventDate(e.target.value)} min={minDate} max={maxDate} />
              </div>
              <div className="form-group">
                <label>Duration</label>
                <div className="quick-duration-btns">
                  {[30, 60, 90].map(m => (
                    <button key={m} className="quick-dur-btn" onClick={() => {
                      endTimeManualRef.current = true
                      setEventEnd(minutesToTime(timeToMinutes(eventStart) + m))
                    }}>{m}m</button>
                  ))}
                </div>
              </div>
            </div>
            <div className="form-group">
              <label>Tag</label>
              <div className="tag-selector">
                <button
                  className={`tag-option no-tag ${eventTag === null ? 'selected' : ''}`}
                  onClick={() => setEventTag(null)}
                  title="No tag"
                >×</button>
                {tags.map(tag => (
                  <button
                    key={tag.id}
                    className={`tag-option ${eventTag === tag.id ? 'selected' : ''}`}
                    onClick={() => setEventTag(tag.id)}
                    style={{ backgroundColor: tag.color }}
                    title={tag.name}
                  />
                ))}
              </div>
            </div>
            <div className="modal-actions">
              {editingEvent && (
                <button className="btn-delete" onClick={() => { deleteEvent(editingEvent.id); setShowEventModal(false) }}>Delete</button>
              )}
              <button className="btn-secondary" onClick={() => setShowEventModal(false)}>Cancel</button>
              <button className="btn-primary" onClick={saveEvent}>
                {editingEvent ? 'Save Changes' : 'Add Event'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Settings Modal ────────────────────────────────────────────────── */}
      {showSettingsModal && (
        <div className="modal-overlay" onMouseDown={() => setShowSettingsModal(false)}>
          <div className="modal modal-wide" onMouseDown={e => e.stopPropagation()}>
            <h3>Settings</h3>

            <div className="settings-section">
              <h4>Working Hours</h4>
              <div className="form-row">
                <div className="form-group">
                  <label>Start</label>
                  <input type="time" value={settings.workdayStart} onChange={e => updateSetting('workdayStart', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>End</label>
                  <input type="time" value={settings.workdayEnd} onChange={e => updateSetting('workdayEnd', e.target.value)} />
                </div>
              </div>
            </div>

            <div className="settings-section">
              <h4>Extended View Hours</h4>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.useExtendedHours} onChange={e => updateSetting('useExtendedHours', e.target.checked)} />
                <span>Show hours outside working hours</span>
              </label>
              {settings.useExtendedHours && (
                <>
                  <p className="settings-hint">Calendar range — dimmed outside working hours</p>
                  <div className="form-row">
                    <div className="form-group">
                      <label>Start</label>
                      <input type="time" value={settings.extendedStart} onChange={e => updateSetting('extendedStart', e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label>End</label>
                      <input type="time" value={settings.extendedEnd} onChange={e => updateSetting('extendedEnd', e.target.value)} />
                    </div>
                  </div>
                </>
              )}
            </div>

            <div className="settings-section">
              <h4>Defaults</h4>
              <div className="form-row">
                <div className="form-group">
                  <label>Task Duration (min)</label>
                  <input
                    type="number"
                    value={settings.defaultTaskDuration}
                    onChange={e => updateSetting('defaultTaskDuration', Number(e.target.value))}
                    min="5" max="480"
                  />
                </div>
                <div className="form-group">
                  <label>Event Duration (min)</label>
                  <input
                    type="number"
                    value={settings.defaultEventDuration}
                    onChange={e => updateSetting('defaultEventDuration', Number(e.target.value))}
                    min="5" max="480"
                  />
                </div>
              </div>
              <div className="form-row">
                <div className="form-group">
                  <label>Task Color</label>
                  <input
                    type="color"
                    value={settings.defaultTaskColor}
                    onChange={e => updateSetting('defaultTaskColor', e.target.value)}
                    className="color-input"
                  />
                </div>
                <div className="form-group">
                  <label>Event Color</label>
                  <input
                    type="color"
                    value={settings.defaultEventColor}
                    onChange={e => updateSetting('defaultEventColor', e.target.value)}
                    className="color-input"
                  />
                </div>
              </div>
            </div>

            <div className="settings-section">
              <h4>Calendar</h4>
              <div className="form-row">
                <div className="form-group">
                  <label>Min Fragment (min)</label>
                  <input
                    type="number"
                    value={settings.minFragmentMinutes}
                    onChange={e => updateSetting('minFragmentMinutes', Math.max(1, Math.min(10, Number(e.target.value))))}
                    min="1" max="10"
                  />
                  <p className="form-hint">Smallest task fragment to show (1–10 min)</p>
                </div>
                <div className="form-group">
                  <label>Font Size</label>
                  <select
                    value={settings.calendarFontSize}
                    onChange={e => updateSetting('calendarFontSize', e.target.value)}
                    className="select-input"
                  >
                    {Object.entries(FONT_SIZE_OPTIONS).map(([key, opt]) => (
                      <option key={key} value={key}>{opt.label}</option>
                    ))}
                  </select>
                </div>
              </div>
            </div>

            <div className="settings-section">
              <h4>Behavior</h4>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.autoStartNext} onChange={e => updateSetting('autoStartNext', e.target.checked)} />
                <span>Auto-start next task on completion</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.smartDuration} onChange={e => updateSetting('smartDuration', e.target.checked)} />
                <span>Smart duration — numbers at end of task name set duration</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.wrapListNames} onChange={e => updateSetting('wrapListNames', e.target.checked)} />
                <span>Wrap names in list view</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.restrictTasksToWorkHours} onChange={e => updateSetting('restrictTasksToWorkHours', e.target.checked)} />
                <span>Restrict tasks to work hours only</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.darkMode} onChange={e => updateSetting('darkMode', e.target.checked)} />
                <span>Dark mode</span>
              </label>
            </div>

            <div className="settings-section">
              <h4>Tags</h4>
              <div className="tag-edit-list">
                {tags.map(tag => (
                  <div
                    key={tag.id}
                    className={`tag-edit-row${draggedTagId === tag.id ? ' dragging' : ''}${dragOverTagId === tag.id && draggedTagId !== tag.id ? ' drag-over' : ''}`}
                    draggable
                    onDragStart={e => handleTagDragStart(e, tag.id)}
                    onDragOver={e => handleTagDragOver(e, tag.id)}
                    onDrop={e => handleTagDrop(e, tag.id)}
                    onDragEnd={handleTagDragEnd}
                  >
                    <span className="drag-handle" title="Drag to reorder">⠿</span>
                    <input
                      type="color"
                      value={tag.color}
                      onChange={e => updateTag(tag.id, { color: e.target.value })}
                      className="color-input"
                    />
                    <input
                      type="text"
                      value={tag.name}
                      onChange={e => updateTag(tag.id, { name: e.target.value })}
                      className="tag-name-input"
                    />
                    <button className="action-btn delete" onClick={() => deleteTag(tag.id)}>×</button>
                  </div>
                ))}
              </div>
              <button className="add-btn small" onClick={addTag}>+ Add Tag</button>
            </div>

            <div className="settings-section">
              <h4>Calendar Import (.ics)</h4>
              <p className="settings-hint">Which event statuses to include when importing an Outlook .ics file</p>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.icsImportBusy} onChange={e => updateSetting('icsImportBusy', e.target.checked)} />
                <span>Busy</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.icsImportOof} onChange={e => updateSetting('icsImportOof', e.target.checked)} />
                <span>Out of Office</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.icsImportTentative} onChange={e => updateSetting('icsImportTentative', e.target.checked)} />
                <span>Tentative</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.icsImportWorkingElsewhere} onChange={e => updateSetting('icsImportWorkingElsewhere', e.target.checked)} />
                <span>Working Elsewhere</span>
              </label>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.icsImportFree} onChange={e => updateSetting('icsImportFree', e.target.checked)} />
                <span>Free</span>
              </label>

              <div style={{ marginTop: '0.75rem' }}>
                <label className="toggle-row">
                  <input type="checkbox" checked={settings.icsImportMeetingsOnly} onChange={e => updateSetting('icsImportMeetingsOnly', e.target.checked)} />
                  <span>Meetings only (skip appointments with no attendees)</span>
                </label>
                <label className="toggle-row">
                  <span>Previous imports:</span>
                  <select value={settings.icsReplaceOnImport === true ? 'yes' : settings.icsReplaceOnImport === false ? 'no' : settings.icsReplaceOnImport} onChange={e => updateSetting('icsReplaceOnImport', e.target.value)}>
                    <option value="no">Keep (deduplicate)</option>
                    <option value="yes">Clear before importing</option>
                    <option value="ask">Ask each time</option>
                  </select>
                </label>
              </div>

              <div style={{ marginTop: '0.5rem' }}>
                <button className="btn-secondary" onClick={openCategoryMapping}>
                  Category Mapping{(settings.icsCategoryRules || []).length > 0 ? ` (${settings.icsCategoryRules.length} saved)` : ''}
                </button>
                <p className="form-hint">Map Outlook categories to tags or exclude them during import</p>
              </div>
            </div>

            <div className="settings-section">
              <h4>Debug</h4>
              <label className="toggle-row">
                <input type="checkbox" checked={settings.debugMode} onChange={e => updateSetting('debugMode', e.target.checked)} />
                <span>Debug mode</span>
              </label>
              {settings.debugMode && (
                <div className="form-group" style={{ marginTop: '0.5rem' }}>
                  <label>Time offset (minutes)</label>
                  <input
                    type="number"
                    value={settings.debugTimeOffset}
                    onChange={e => updateSetting('debugTimeOffset', Number(e.target.value))}
                  />
                  <p className="form-hint">
                    Effective time: {formatTime(minutesToTime(getCurrentTimeMinutes() + (settings.debugTimeOffset || 0)))}
                    {' '}({settings.debugTimeOffset > 0 ? '+' : ''}{settings.debugTimeOffset || 0}m from real time)
                  </p>
                  <p className="settings-hint" style={{ marginTop: '1rem', fontSize: '0.85em', opacity: 0.7 }}>
                    Last pushed: {LAST_UPDATED}
                  </p>
                </div>
              )}
            </div>

            <div className="settings-section">
              <h4>Transfer Settings</h4>
              <p className="settings-hint">Export or import your settings and tags for use on another device</p>
              <div className="transfer-btns">
                <button className="btn-secondary" onClick={exportSettings}>Export Settings</button>
                <button className="btn-secondary" onClick={() => importFileRef.current?.click()}>Import Settings</button>
                <input ref={importFileRef} type="file" accept=".json" onChange={importSettings} style={{ display: 'none' }} />
              </div>
            </div>

            <div className="modal-actions">
              <button className="btn-primary" onClick={() => setShowSettingsModal(false)}>Done</button>
            </div>
          </div>
        </div>
      )}

      {/* ── ICS Replace Confirm Modal ────────────────────────────────────────── */}
      {icsReplaceConfirm && (
        <div className="modal-overlay" style={{ zIndex: 200 }} onMouseDown={() => setIcsReplaceConfirm(null)}>
          <div className="modal" onMouseDown={e => e.stopPropagation()}>
            <h3>Clear previously imported events before importing?</h3>
            <div className="modal-actions">
              <button onClick={() => {
                const { newEvents } = icsReplaceConfirm
                setIcsReplaceConfirm(null)
                applyIcsImport(newEvents, false)
              }}>Keep (deduplicate)</button>
              <button className="primary" onClick={() => {
                const { newEvents } = icsReplaceConfirm
                setIcsReplaceConfirm(null)
                applyIcsImport(newEvents, true)
              }}>Clear before importing</button>
            </div>
          </div>
        </div>
      )}

      {/* ── Category Mapping Modal ──────────────────────────────────────────── */}
      {icsCategoryModal && (
        <div className="modal-overlay" style={{ zIndex: 200 }} onMouseDown={() => {
          setIcsCategoryModal(null)
          setIcsCategoryMappings([])
        }}>
          <div className="modal modal-wide" onMouseDown={e => e.stopPropagation()}>
            <h3>{icsCategoryModal.mode === 'import' ? 'Map Categories' : 'Category Mapping'}</h3>

            {icsCategoryModal.mode === 'import' && icsCategoryModal.uncategorized > 0 && (
              <p className="form-hint" style={{ marginBottom: '0.75rem' }}>
                {icsCategoryModal.uncategorized} event{icsCategoryModal.uncategorized !== 1 ? 's' : ''} without a category will always be imported.
              </p>
            )}

            <div className="category-mapping-list">
              {icsCategoryMappings.map((mapping, idx) => (
                <div key={idx} className={`category-mapping-row${mapping.include === false ? ' excluded' : ''}`}>
                  {icsCategoryModal.mode === 'settings' ? (
                    <input
                      type="text"
                      className="category-rule-name"
                      value={mapping.category}
                      onChange={e => {
                        const updated = [...icsCategoryMappings]
                        updated[idx] = { ...updated[idx], category: e.target.value }
                        setIcsCategoryMappings(updated)
                      }}
                      placeholder="Category name"
                    />
                  ) : (
                    <span className="category-mapping-name">
                      {mapping.category}
                      {icsCategoryModal.catCounts?.[mapping.category] != null && (
                        <span className="category-mapping-count">({icsCategoryModal.catCounts[mapping.category]})</span>
                      )}
                    </span>
                  )}

                  <label className="category-mapping-toggle">
                    <input
                      type="checkbox"
                      checked={mapping.include !== false}
                      onChange={e => {
                        const updated = [...icsCategoryMappings]
                        updated[idx] = { ...updated[idx], include: e.target.checked }
                        if (!e.target.checked) updated[idx].tagId = null
                        setIcsCategoryMappings(updated)
                      }}
                    />
                    Include
                  </label>

                  {mapping.include !== false && (
                    <div className="tag-selector compact">
                      <button
                        className={`tag-option no-tag ${mapping.tagId === null ? 'selected' : ''}`}
                        onClick={() => {
                          const updated = [...icsCategoryMappings]
                          updated[idx] = { ...updated[idx], tagId: null }
                          setIcsCategoryMappings(updated)
                        }}
                        title="No tag"
                      >×</button>
                      {tags.map(tag => (
                        <button
                          key={tag.id}
                          className={`tag-option ${mapping.tagId === tag.id ? 'selected' : ''}`}
                          onClick={() => {
                            const updated = [...icsCategoryMappings]
                            updated[idx] = { ...updated[idx], tagId: tag.id }
                            setIcsCategoryMappings(updated)
                          }}
                          style={{ backgroundColor: tag.color }}
                          title={tag.name}
                        />
                      ))}
                    </div>
                  )}

                  {icsCategoryModal.mode === 'settings' && (
                    <button
                      className="action-btn delete"
                      onClick={() => setIcsCategoryMappings(prev => prev.filter((_, i) => i !== idx))}
                      title="Remove rule"
                    >🗑</button>
                  )}
                </div>
              ))}
            </div>

            {icsCategoryModal.mode === 'settings' && (
              <button
                className="btn-secondary"
                style={{ marginTop: '0.5rem' }}
                onClick={() => setIcsCategoryMappings(prev => [...prev, { category: '', include: true, tagId: null }])}
              >+ Add Category</button>
            )}

            <div className="modal-actions" style={{ marginTop: '1rem' }}>
              <button className="btn-secondary" onClick={() => {
                setIcsCategoryModal(null)
                setIcsCategoryMappings([])
              }}>Cancel</button>

              {icsCategoryModal.mode === 'import' ? (
                <>
                  <button className="btn-primary" onClick={() => {
                    const rules = icsCategoryMappings.filter(m => m.category.trim())
                    finishIcsImport(icsCategoryModal.filteredEvents, rules)
                    setIcsCategoryModal(null)
                    setIcsCategoryMappings([])
                  }}>Import</button>
                  <button className="btn-primary" onClick={() => {
                    const rules = icsCategoryMappings.filter(m => m.category.trim())
                    updateSetting('icsCategoryRules', rules)
                    finishIcsImport(icsCategoryModal.filteredEvents, rules)
                    setIcsCategoryModal(null)
                    setIcsCategoryMappings([])
                  }}>Remember &amp; Import</button>
                </>
              ) : (
                <button className="btn-primary" onClick={() => {
                  const rules = icsCategoryMappings.filter(m => m.category.trim())
                  updateSetting('icsCategoryRules', rules)
                  setIcsCategoryModal(null)
                  setIcsCategoryMappings([])
                }}>Save</button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default App
