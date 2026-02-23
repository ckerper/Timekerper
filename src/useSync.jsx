import { useState, useEffect, useCallback, useRef } from 'react'
import { findGist, createGist, pushToGist, pullFromGist, buildPayload, hasChanges, LOCAL_ONLY_SETTINGS } from './sync'
import { getCurrentTimeMinutes } from './scheduler'

function formatSyncTime(date) {
  const seconds = Math.round((Date.now() - date.getTime()) / 1000)
  if (seconds < 10) return 'just now'
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
}

export function useSync({
  tasks, setTasks,
  events, setEvents,
  tags, setTags,
  settings, setSettings,
  activeTaskId, setActiveTaskId,
  setTaskStartTime, setElapsedMinutes,
  tasksRef, eventsRef,
  timeOffset,
}) {
  // ── State ──────────────────────────────────────────────────────────────────

  const [syncEnabled, setSyncEnabled] = useState(() => localStorage.getItem('timekerper-sync-enabled') === 'true')
  const [syncPat, setSyncPat] = useState(() => localStorage.getItem('timekerper-sync-pat') || '')
  const [syncGistId, setSyncGistId] = useState(() => localStorage.getItem('timekerper-sync-gistId') || '')
  const [syncStatus, setSyncStatus] = useState('idle') // 'idle' | 'syncing' | 'error'
  const [syncError, setSyncError] = useState(null)
  const [lastSynced, setLastSynced] = useState(null)
  const [syncConflict, setSyncConflict] = useState(null) // { pat, gistId } when existing gist found during connect
  const syncingRef = useRef(false)
  const suppressPushRef = useRef(false)
  const dirtyRef = useRef(false)  // true when local has unpushed changes

  // ── Persistence ────────────────────────────────────────────────────────────

  useEffect(() => { localStorage.setItem('timekerper-sync-pat', syncPat) }, [syncPat])
  useEffect(() => { localStorage.setItem('timekerper-sync-gistId', syncGistId) }, [syncGistId])
  useEffect(() => { localStorage.setItem('timekerper-sync-enabled', syncEnabled) }, [syncEnabled])

  // ── Handlers ───────────────────────────────────────────────────────────────

  const applyRemoteData = useCallback((remote) => {
    suppressPushRef.current = true
    if (remote.tasks) setTasks(remote.tasks)
    if (remote.events) setEvents(remote.events)
    if (remote.tags) setTags(remote.tags)
    if (remote.settings) {
      const filtered = Object.fromEntries(
        Object.entries(remote.settings).filter(([k]) => !LOCAL_ONLY_SETTINGS.includes(k))
      )
      setSettings(prev => ({ ...prev, ...filtered }))
    }
    // Reconstruct active task timer from remote data
    if (remote.activeTaskId != null) {
      const task = (remote.tasks || []).find(t => t.id === remote.activeTaskId && !t.completed)
      if (task && task.startedAtMin != null) {
        const now = getCurrentTimeMinutes() + timeOffset
        const gap = (task.pauseEvents || []).reduce((sum, pe) => sum + ((pe.end ?? now) - pe.start), 0) || (task.pauseGapMinutes || 0)
        const elapsed = Math.max(0, now - task.startedAtMin - gap)
        setActiveTaskId(remote.activeTaskId)
        setTaskStartTime(Date.now() - (elapsed * 60000))
        setElapsedMinutes(elapsed)
      } else {
        setActiveTaskId(null)
        setTaskStartTime(null)
        setElapsedMinutes(0)
      }
    } else if (remote.activeTaskId === null) {
      setActiveTaskId(null)
      setTaskStartTime(null)
      setElapsedMinutes(0)
    }
    setTimeout(() => { suppressPushRef.current = false }, 0)
  }, [timeOffset])

  const doPush = useCallback(async () => {
    if (suppressPushRef.current || syncingRef.current || !syncEnabled || !syncGistId || !syncPat) return
    syncingRef.current = true
    setSyncStatus('syncing')
    try {
      const payload = buildPayload(tasksRef.current, eventsRef.current, tags, settings, activeTaskId)
      await pushToGist(syncPat, syncGistId, payload)
      dirtyRef.current = false
      setLastSynced(new Date())
      setSyncStatus('idle')
      setSyncError(null)
    } catch (err) {
      setSyncStatus('error')
      setSyncError(err.message)
    } finally {
      syncingRef.current = false
    }
  }, [syncEnabled, syncGistId, syncPat, tags, settings, activeTaskId])

  const doPull = useCallback(async () => {
    if (dirtyRef.current || syncingRef.current || !syncEnabled || !syncGistId || !syncPat) return
    syncingRef.current = true
    setSyncStatus('syncing')
    try {
      const remote = await pullFromGist(syncPat, syncGistId)
      const local = buildPayload(tasksRef.current, eventsRef.current, tags, settings, activeTaskId)
      if (hasChanges(local, remote)) {
        applyRemoteData(remote)
      }
      setLastSynced(new Date())
      setSyncStatus('idle')
      setSyncError(null)
    } catch (err) {
      setSyncStatus('error')
      setSyncError(err.message)
    } finally {
      syncingRef.current = false
    }
  }, [syncEnabled, syncGistId, syncPat, tags, settings, activeTaskId, applyRemoteData])

  const connectSync = async (pat) => {
    setSyncStatus('syncing')
    setSyncError(null)
    try {
      const existing = await findGist(pat)
      if (existing) {
        // Existing gist found — ask user which direction to sync
        setSyncStatus('idle')
        setSyncConflict({ pat, gistId: existing.gistId })
      } else {
        // No gist yet — create with this device's data
        const payload = buildPayload(tasksRef.current, eventsRef.current, tags, settings, activeTaskId)
        const gistId = await createGist(pat, payload)
        setSyncGistId(gistId)
        setSyncPat(pat)
        setSyncEnabled(true)
        setSyncStatus('idle')
        setLastSynced(new Date())
      }
    } catch (err) {
      setSyncStatus('error')
      setSyncError(err.message)
    }
  }

  const resolveSyncConflict = async (direction) => {
    const { pat, gistId } = syncConflict
    setSyncConflict(null)
    setSyncStatus('syncing')
    try {
      if (direction === 'pull') {
        // Use cloud data — overwrite this device
        const remote = await pullFromGist(pat, gistId)
        applyRemoteData(remote)
      } else {
        // Use this device — overwrite cloud
        const payload = buildPayload(tasksRef.current, eventsRef.current, tags, settings, activeTaskId)
        await pushToGist(pat, gistId, payload)
      }
      setSyncGistId(gistId)
      setSyncPat(pat)
      setSyncEnabled(true)
      setSyncStatus('idle')
      setLastSynced(new Date())
    } catch (err) {
      setSyncStatus('error')
      setSyncError(err.message)
    }
  }

  const disconnectSync = () => {
    setSyncEnabled(false)
    setSyncPat('')
    setSyncGistId('')
    setSyncStatus('idle')
    setSyncError(null)
    setLastSynced(null)
    localStorage.removeItem('timekerper-sync-pat')
    localStorage.removeItem('timekerper-sync-gistId')
    localStorage.removeItem('timekerper-sync-enabled')
  }

  // ── Effects ────────────────────────────────────────────────────────────────

  // Debounced push on state change
  useEffect(() => {
    if (!syncEnabled || suppressPushRef.current) return
    dirtyRef.current = true
    const timer = setTimeout(() => {
      if (!suppressPushRef.current) doPush()
    }, 2000)
    return () => clearTimeout(timer)
  }, [tasks, events, tags, settings, activeTaskId, syncEnabled, doPush])

  // Periodic pull every 60s
  useEffect(() => {
    if (!syncEnabled) return
    const interval = setInterval(doPull, 60000)
    return () => clearInterval(interval)
  }, [syncEnabled, doPull])

  // Pull on mount if sync is already enabled
  useEffect(() => {
    if (syncEnabled && syncGistId && syncPat) doPull()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // ── JSX ────────────────────────────────────────────────────────────────────

  const syncIndicator = syncEnabled ? (
    <span
      className={`sync-indicator ${syncStatus}`}
      title={syncStatus === 'error' ? syncError : syncStatus === 'syncing' ? 'Syncing...' : lastSynced ? `Last synced ${formatSyncTime(lastSynced)}` : 'Connected'}
    />
  ) : null

  const syncSettingsUI = (
    <div className="settings-section">
      <h4>Sync</h4>
      <p className="settings-hint">Sync your data across devices via a private GitHub Gist</p>
      {!syncEnabled ? (
        <>
          <div className="form-group">
            <label>GitHub Personal Access Token <span className="label-hint">— needs "gist" scope only</span></label>
            <details className="sync-help">
              <summary>How do I get one?</summary>
              <ol>
                <li>Go to <strong>github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)</strong></li>
                <li>Click <strong>Generate new token (classic)</strong></li>
                <li>Give it a name (e.g. "Timekerper sync")</li>
                <li>Check only the <strong>gist</strong> scope</li>
                <li>Click <strong>Generate token</strong> and copy it</li>
                <li>Paste the same token on each device you want to sync</li>
              </ol>
            </details>
            <input
              type="password"
              className="pat-input"
              value={syncPat}
              onChange={e => setSyncPat(e.target.value)}
              placeholder="ghp_xxxxxxxxxxxxxxxxxxxx"
            />
          </div>
          {syncConflict ? (
            <div className="sync-conflict">
              <p className="sync-conflict-msg">Existing sync data found. Which do you want to keep?</p>
              <div className="sync-conflict-btns">
                <button className="btn-primary" onClick={() => resolveSyncConflict('pull')}>Use cloud data</button>
                <button className="btn-secondary" onClick={() => resolveSyncConflict('push')}>Use this device</button>
                <button className="btn-secondary" onClick={() => { setSyncConflict(null); setSyncPat('') }}>Cancel</button>
              </div>
            </div>
          ) : (
            <button
              className="btn-primary"
              onClick={() => connectSync(syncPat)}
              disabled={!syncPat.trim() || syncStatus === 'syncing'}
            >
              {syncStatus === 'syncing' ? 'Connecting...' : 'Connect'}
            </button>
          )}
        </>
      ) : (
        <>
          <div className="sync-status-row">
            <span className={`sync-dot ${syncStatus}`} />
            <span>
              {syncStatus === 'syncing' && 'Syncing...'}
              {syncStatus === 'idle' && lastSynced && `Last synced ${formatSyncTime(lastSynced)}`}
              {syncStatus === 'idle' && !lastSynced && 'Connected'}
              {syncStatus === 'error' && 'Sync error'}
            </span>
            <button className="btn-secondary sync-now-btn" onClick={async () => { await doPush(); await doPull() }}>Sync Now</button>
          </div>
          {syncStatus === 'error' && syncError && (
            <p className="sync-error">{syncError}</p>
          )}
          <button className="btn-secondary" style={{ marginTop: '0.5rem' }} onClick={disconnectSync}>Disconnect</button>
        </>
      )}
    </div>
  )

  return { syncIndicator, syncSettingsUI }
}
