import { useState, useEffect, useCallback, useRef } from 'react'
import { graphEventToParsedFormat } from './outlook'
import { filterIcsEvents } from './scheduler'

// Detect Electron: the preload script exposes window.electronOutlook
const electron = typeof window !== 'undefined' && window.electronOutlook

// Only import browser MSAL if we're NOT in Electron
const browserOutlook = !electron
  ? import('./outlook').catch(() => null)
  : Promise.resolve(null)

export function useOutlook({ events, setEvents, settings, pushUndo, minDate, maxDate, tags }) {

  const [outlookConnected, setOutlookConnected] = useState(false)
  const [outlookStatus, setOutlookStatus] = useState('idle') // 'idle' | 'fetching' | 'error'
  const [outlookError, setOutlookError] = useState(null)
  const [lastFetched, setLastFetched] = useState(null)
  const msalRef = useRef(null) // only used in browser mode
  const fetchingRef = useRef(false)

  // ── Initialize: check for existing account ────────────────────────────────

  useEffect(() => {
    let cancelled = false

    if (electron) {
      // Electron: check if we have a cached account
      electron.checkAccount().then(hasAccount => {
        if (!cancelled && hasAccount) setOutlookConnected(true)
      })
    } else {
      // Browser: try MSAL browser init
      browserOutlook.then(mod => {
        if (cancelled || !mod) return
        return mod.getInitializedMsal().then(instance => {
          if (cancelled) return
          if (!instance) {
            setOutlookStatus('error')
            setOutlookError(mod.getMsalInitError?.() || 'MSAL failed to initialize')
            return
          }
          msalRef.current = instance
          if (instance.getAllAccounts().length > 0) {
            setOutlookConnected(true)
          }
        })
      })
    }

    return () => { cancelled = true }
  }, [])

  // ── Connect ───────────────────────────────────────────────────────────────

  const connectOutlook = useCallback(async () => {
    if (electron) {
      setOutlookStatus('fetching')
      setOutlookError(null)
      try {
        await electron.connect()
        setOutlookConnected(true)
        setOutlookStatus('idle')
      } catch (err) {
        setOutlookStatus('error')
        setOutlookError(err.message || 'Connection failed')
      }
    } else {
      // Browser fallback
      if (!msalRef.current) {
        const mod = await browserOutlook
        setOutlookStatus('error')
        setOutlookError(mod?.getMsalInitError?.() || 'MSAL not ready — try refreshing the page')
        return
      }
      const mod = await browserOutlook
      mod?.loginRedirect(msalRef.current)
    }
  }, [])

  // ── Disconnect ────────────────────────────────────────────────────────────

  const disconnectOutlook = useCallback(async () => {
    pushUndo()
    setEvents(prev => prev.filter(e => !e.outlookSynced))

    if (electron) {
      await electron.disconnect()
    } else if (msalRef.current) {
      const mod = await browserOutlook
      try { await mod?.logout(msalRef.current) } catch { /* ignore */ }
    }

    setOutlookConnected(false)
    setOutlookStatus('idle')
    setOutlookError(null)
    setLastFetched(null)
  }, [pushUndo, setEvents])

  // ── Fetch & merge events ──────────────────────────────────────────────────

  const refreshOutlookEvents = useCallback(async () => {
    if (fetchingRef.current) return
    fetchingRef.current = true
    setOutlookStatus('fetching')
    setOutlookError(null)
    try {
      let graphEvents

      if (electron) {
        // Electron: main process handles auth + fetch
        graphEvents = await electron.fetchEvents(minDate, maxDate)
      } else {
        // Browser: use MSAL browser (will fail with CORS until CaTS adds SPA)
        if (!msalRef.current) throw new Error('Not connected')
        const mod = await browserOutlook
        let token = await mod.acquireTokenSilent(msalRef.current)
        if (!token) { mod.loginRedirect(msalRef.current); return }
        graphEvents = await mod.fetchCalendarEvents(token, minDate, maxDate)
      }

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
