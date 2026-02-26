const { app, BrowserWindow, ipcMain } = require('electron')
const path = require('path')
const msal = require('@azure/msal-node')

// ── MSAL Configuration (same app registration as the wiki) ──────────────────

const MSAL_CONFIG = {
  auth: {
    clientId: '893adac7-4ea6-44e3-b2fe-e7bd49f64814',
    authority: 'https://login.microsoftonline.com/d8d598e0-2fb2-4605-8514-1967b50e2bd6',
  },
}

const SCOPES = ['Calendars.ReadWrite.Shared']
const GRAPH_BASE = 'https://graph.microsoft.com/v1.0'

const msalApp = new msal.PublicClientApplication(MSAL_CONFIG)

// ── Helper: get cached account ──────────────────────────────────────────────

async function getCachedAccount() {
  const cache = msalApp.getTokenCache()
  const accounts = await cache.getAllAccounts()
  return accounts.length > 0 ? accounts[0] : null
}

// ── Helper: get access token (silent or interactive) ────────────────────────

async function getAccessToken(parentWindow) {
  const account = await getCachedAccount()

  if (account) {
    try {
      const result = await msalApp.acquireTokenSilent({ scopes: SCOPES, account })
      return result.accessToken
    } catch {
      // Silent failed — fall through to interactive
    }
  }

  // Interactive login via system browser
  const result = await msalApp.acquireTokenInteractive({
    scopes: SCOPES,
    openBrowser: async (url) => {
      const { shell } = require('electron')
      await shell.openExternal(url)
    },
    successTemplate: '<h1>Sign-in successful!</h1><p>You can close this window.</p>',
    errorTemplate: '<h1>Sign-in failed</h1><p>Error: {{error}}</p>',
  })
  return result.accessToken
}

// ── Helper: fetch calendar events from Graph API ────────────────────────────

async function fetchCalendarEvents(accessToken, startDate, endDate) {
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
    if (!res.ok) throw new Error(`Graph API error: ${res.status}`)
    const data = await res.json()
    allEvents.push(...(data.value || []))
    url = data['@odata.nextLink'] || null
  }

  return allEvents
}

// ── Electron App ────────────────────────────────────────────────────────────

let mainWindow

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    title: 'Timekerper',
  })

  // Load the production build
  mainWindow.loadFile(path.join(__dirname, '..', 'docs', 'index.html'))
}

app.whenReady().then(createWindow)
app.on('window-all-closed', () => app.quit())

// ── IPC Handlers ────────────────────────────────────────────────────────────

ipcMain.handle('outlook:check-account', async () => {
  const account = await getCachedAccount()
  return !!account
})

ipcMain.handle('outlook:connect', async () => {
  const token = await getAccessToken(mainWindow)
  return !!token
})

ipcMain.handle('outlook:fetch-events', async (_event, startDate, endDate) => {
  const token = await getAccessToken(mainWindow)
  return fetchCalendarEvents(token, startDate, endDate)
})

ipcMain.handle('outlook:disconnect', async () => {
  const cache = msalApp.getTokenCache()
  const accounts = await cache.getAllAccounts()
  for (const account of accounts) {
    await cache.removeAccount(account)
  }
  return true
})
