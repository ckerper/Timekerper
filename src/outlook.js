// ── Outlook Calendar Integration Engine ──────────────────────────────────────
// Pure functions for authenticating with Microsoft and fetching calendar events.
// No React dependencies — mirrors the pattern of sync.js.

import { PublicClientApplication } from '@azure/msal-browser'

const MSAL_CONFIG = {
  auth: {
    clientId: '893adac7-4ea6-44e3-b2fe-e7bd49f64814',
    authority: 'https://login.microsoftonline.com/d8d598e0-2fb2-4605-8514-1967b50e2bd6',
    redirectUri: window.location.origin + window.location.pathname,
  },
  cache: {
    cacheLocation: 'localStorage',
    storeAuthStateInCookie: false,
  },
}

const SCOPES = ['Calendars.ReadWrite.Shared']
const GRAPH_BASE = 'https://graph.microsoft.com/v1.0'

// ── Eager initialization ─────────────────────────────────────────────────────
// MSAL must initialize before React renders so that popup redirects are
// detected and closed immediately (before the full app renders in the popup).

const msalInstance = new PublicClientApplication(MSAL_CONFIG)
const msalReady = msalInstance.initialize()
  .then(() => msalInstance.handleRedirectPromise())
  .then(() => msalInstance)
  .catch(err => {
    console.error('MSAL init failed:', err)
    return null
  })

// Returns true if this page is running inside an MSAL popup/redirect.
// Used by App.jsx to skip rendering the full UI in the popup window.
export function isMsalPopup() {
  return window.opener && window.opener !== window && (
    window.location.hash.includes('code=') ||
    window.location.hash.includes('error=') ||
    window.location.search.includes('code=') ||
    window.location.search.includes('error=') ||
    document.referrer.includes('login.microsoftonline.com')
  )
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

export async function loginPopup(instance) {
  const response = await instance.loginPopup({ scopes: SCOPES })
  return { accessToken: response.accessToken, account: response.account }
}

export async function logout(instance) {
  const accounts = instance.getAllAccounts()
  if (accounts.length > 0) {
    await instance.logoutPopup({ account: accounts[0] })
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
