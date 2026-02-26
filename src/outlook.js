// ── Outlook Calendar Integration Engine ──────────────────────────────────────
// Pure functions for authenticating with Microsoft and fetching calendar events.
// No React dependencies — mirrors the pattern of sync.js.
//
// Uses the REDIRECT auth flow (not popup) for maximum browser compatibility.
// Clicking "Connect Outlook" navigates the page to Microsoft login, then
// redirects back. All app state is in localStorage so nothing is lost.

import { PublicClientApplication } from '@azure/msal-browser'

// In Electron, MSAL browser is not used — auth goes through the main process.
// Skip all browser MSAL initialization to avoid crashes on file:// URLs.
const isElectron = typeof window !== 'undefined' && !!window.electronOutlook

const MSAL_CONFIG = !isElectron ? {
  auth: {
    clientId: '893adac7-4ea6-44e3-b2fe-e7bd49f64814',
    authority: 'https://login.microsoftonline.com/d8d598e0-2fb2-4605-8514-1967b50e2bd6',
    redirectUri: window.location.origin + window.location.pathname,
  },
  cache: {
    cacheLocation: 'localStorage',
    storeAuthStateInCookie: false,
  },
} : null

const SCOPES = ['Calendars.ReadWrite.Shared']
const GRAPH_BASE = 'https://graph.microsoft.com/v1.0'

// ── Eager initialization ─────────────────────────────────────────────────────
// MSAL must initialize and handle the redirect response before React renders,
// so the auth token from the redirect is available immediately on page load.
// Skipped entirely in Electron.

let msalInitError = null

const msalInstance = !isElectron ? new PublicClientApplication(MSAL_CONFIG) : null
const msalReady = !isElectron && msalInstance
  ? msalInstance.initialize()
    .then(() => msalInstance.handleRedirectPromise())
    .then(response => {
      if (response) {
        console.log('MSAL redirect login succeeded:', response.account?.username)
      }
      return msalInstance
    })
    .catch(err => {
      console.error('MSAL init failed:', err)
      msalInitError = err?.message || String(err)
      return null
    })
  : Promise.resolve(null)

export function getMsalInitError() {
  return msalInitError
}

export async function getInitializedMsal() {
  return msalReady
}

export async function acquireTokenSilent(instance) {
  const accounts = instance.getAllAccounts()
  if (accounts.length === 0) return null
  try {
    const response = await instance.acquireTokenSilent({
      scopes: SCOPES,
      account: accounts[0],
    })
    return response.accessToken
  } catch {
    return null
  }
}

// Redirect-based login: navigates away from the page, returns after auth.
export function loginRedirect(instance) {
  instance.loginRedirect({ scopes: SCOPES })
}

export async function logout(instance) {
  const accounts = instance.getAllAccounts()
  if (accounts.length > 0) {
    // Clear account from cache without navigating away
    instance.clearCache()
  }
}

export async function fetchCalendarEvents(accessToken, startDate, endDate) {
  const params = new URLSearchParams({
    startDateTime: `${startDate}T00:00:00`,
    endDateTime: `${endDate}T23:59:59`,
    $top: '100',
    $select: 'subject,start,end,showAs,isAllDay,isCancelled,attendees,categories',
    $orderby: 'start/dateTime',
  })

  const allEvents = []
  let url = `${GRAPH_BASE}/me/calendarView?${params}`

  while (url) {
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    })
    if (!res.ok) {
      if (res.status === 401) throw new Error('outlook_token_expired')
      throw new Error(`Graph API error: ${res.status}`)
    }
    const data = await res.json()
    allEvents.push(...(data.value || []))
    url = data['@odata.nextLink'] || null
  }

  return allEvents
}

const SHOW_AS_TO_STATUS = {
  busy: 'BUSY',
  oof: 'OOF',
  tentative: 'TENTATIVE',
  free: 'FREE',
  workingElsewhere: 'WORKING-ELSEWHERE',
  unknown: 'BUSY',
}

export function graphEventToParsedFormat(graphEvent) {
  // calendarView returns times in the user's mailbox timezone by default.
  // Parse as local time (no 'Z' suffix) since the timezone should match.
  const startLocal = new Date(graphEvent.start.dateTime)
  const endLocal = new Date(graphEvent.end.dateTime)

  const date = startLocal.getFullYear() + '-' +
    String(startLocal.getMonth() + 1).padStart(2, '0') + '-' +
    String(startLocal.getDate()).padStart(2, '0')
  const start = String(startLocal.getHours()).padStart(2, '0') + ':' +
    String(startLocal.getMinutes()).padStart(2, '0')
  const end = String(endLocal.getHours()).padStart(2, '0') + ':' +
    String(endLocal.getMinutes()).padStart(2, '0')

  return {
    name: graphEvent.subject || 'Outlook Event',
    date,
    start,
    end,
    status: SHOW_AS_TO_STATUS[graphEvent.showAs] || 'BUSY',
    isMeeting: (graphEvent.attendees?.length || 0) > 0,
    categories: graphEvent.categories || [],
    isAllDay: graphEvent.isAllDay || false,
    isCancelled: graphEvent.isCancelled || false,
    graphId: graphEvent.id,
  }
}
