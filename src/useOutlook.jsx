import { useState, useEffect, useCallback, useRef } from 'react'
import {
  getInitializedMsal, acquireTokenSilent, loginRedirect, logout,
  fetchCalendarEvents, graphEventToParsedFormat,
} from './outlook'
import { filterIcsEvents } from './scheduler'

export function useOutlook({ events, setEvents, settings, pushUndo, minDate, maxDate, tags }) {

  const [outlookConnected, setOutlookConnected] = useState(false)
  const [outlookStatus, setOutlookStatus] = useState('idle') // 'idle' | 'fetching' | 'error'
  const [outlookError, setOutlookError] = useState(null)
  const [lastFetched, setLastFetched] = useState(null)
  const msalRef = useRef(null)
  const fetchingRef = useRef(false)

  // ── Pick up the eagerly-initialized MSAL instance ──────────────────────────

  useEffect(() => {
    let cancelled = false
    getInitializedMsal().then(instance => {
      if (cancelled || !instance) return
      msalRef.current = instance
      if (instance.getAllAccounts().length > 0) {
        setOutlookConnected(true)
      }
    })
    return () => { cancelled = true }
  }, [])

  // ── Connect (redirect login) ──────────────────────────────────────────────

  const connectOutlook = useCallback(async () => {
    if (!msalRef.current) return
    // This navigates away from the page. When it comes back,
    // handleRedirectPromise (in outlook.js) processes the token,
    // and the useEffect above detects the cached account.
    loginRedirect(msalRef.current)
  }, [])

  // ── Disconnect ────────────────────────────────────────────────────────────

  const disconnectOutlook = useCallback(async () => {
    if (!msalRef.current) return
    pushUndo()
    setEvents(prev => prev.filter(e => !e.outlookSynced))
    try {
      await logout(msalRef.current)
    } catch { /* ignore logout errors */ }
    setOutlookConnected(false)
    setOutlookStatus('idle')
    setOutlookError(null)
    setLastFetched(null)
  }, [pushUndo, setEvents])

  // ── Fetch & merge events ──────────────────────────────────────────────────

  const refreshOutlookEvents = useCallback(async () => {
    if (!msalRef.current || fetchingRef.current) return
    fetchingRef.current = true
    setOutlookStatus('fetching')
    setOutlookError(null)
    try {
      // Get token silently (MSAL uses cached token)
      let token = await acquireTokenSilent(msalRef.current)
      if (!token) {
        // Token expired and can't refresh — need to re-authenticate
        loginRedirect(msalRef.current)
        return
      }

      const graphEvents = await fetchCalendarEvents(token, minDate, maxDate)

      // Transform and filter
      const parsed = graphEvents
        .filter(ge => !ge.isCancelled)
        .map(graphEventToParsedFormat)
        .filter(pe => !pe.isAllDay)
        .filter(pe => pe.start !== pe.end)

      const filtered = filterIcsEvents(parsed, settings, minDate, maxDate)

      // Map category → tag
      const catRules = settings.icsCategoryRules || []
      const newEvents = filtered.map((ev, i) => {
        let tagId = null
        if (ev.categories?.length > 0) {
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
          outlookSynced: true,
        }
      })

      // Replace existing outlookSynced events; deduplicate against manual events
      pushUndo()
      setEvents(prev => {
        const manual = prev.filter(e => !e.outlookSynced)
        const toAdd = []
        for (const ne of newEvents) {
          const isDupe = manual.some(ex =>
            ex.name === ne.name && ex.start === ne.start &&
            ex.end === ne.end && ex.date === ne.date
          )
          if (!isDupe) toAdd.push(ne)
        }
        return [...manual, ...toAdd]
      })

      setLastFetched(new Date())
      setOutlookStatus('idle')
    } catch (err) {
      if (err.message === 'outlook_token_expired') {
        setOutlookConnected(false)
      }
      setOutlookStatus('error')
      setOutlookError(err.message)
    } finally {
      fetchingRef.current = false
    }
  }, [minDate, maxDate, settings, pushUndo, setEvents])

  // ── Auto-refresh: on connect and on date range change ─────────────────────

  useEffect(() => {
    if (!outlookConnected) return
    refreshOutlookEvents()
  }, [outlookConnected, minDate, maxDate]) // eslint-disable-line react-hooks/exhaustive-deps

  // ── Auto-refresh: every 5 minutes ────────────────────────────────────────

  useEffect(() => {
    if (!outlookConnected) return
    const interval = setInterval(refreshOutlookEvents, 5 * 60 * 1000)
    return () => clearInterval(interval)
  }, [outlookConnected, refreshOutlookEvents])

  return {
    outlookAvailable: true,
    outlookConnected,
    outlookStatus,
    outlookError,
    lastFetched,
    connectOutlook,
    disconnectOutlook,
    refreshOutlookEvents,
  }
}
