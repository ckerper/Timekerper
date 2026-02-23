// ── GitHub Gist Sync Engine ──────────────────────────────────────────────────
// Pure functions for syncing Timekerper state via GitHub Gists.
// No React dependencies — all functions take explicit arguments and return values.

const GIST_FILENAME = 'timekerper-sync.json'
const API_BASE = 'https://api.github.com'
export const LOCAL_ONLY_SETTINGS = ['zoomLevel', 'fitMode', 'debugMode', 'debugTimeOffset', 'darkMode']

function headers(pat) {
  return {
    Authorization: `Bearer ${pat}`,
    Accept: 'application/vnd.github+json',
    'Content-Type': 'application/json',
  }
}

// Find existing Timekerper gist by scanning user's gists for the known filename.
// Returns { gistId, data } if found, null otherwise.
export async function findGist(pat) {
  let page = 1
  while (page <= 10) { // safety cap
    const res = await fetch(`${API_BASE}/gists?per_page=100&page=${page}`, { headers: headers(pat) })
    if (!res.ok) throw new Error(res.status === 401 ? 'Invalid token' : `GitHub API error: ${res.status}`)
    const gists = await res.json()
    if (gists.length === 0) break
    for (const gist of gists) {
      if (gist.files[GIST_FILENAME]) {
        // Found it — fetch full content (list endpoint truncates large files)
        const full = await fetch(`${API_BASE}/gists/${gist.id}`, { headers: headers(pat) })
        if (!full.ok) throw new Error(`Failed to fetch gist: ${full.status}`)
        const fullGist = await full.json()
        const content = fullGist.files[GIST_FILENAME]?.content
        return { gistId: gist.id, data: content ? JSON.parse(content) : null }
      }
    }
    page++
  }
  return null
}

// Create a new private gist with the sync payload. Returns the gist ID.
export async function createGist(pat, payload) {
  const res = await fetch(`${API_BASE}/gists`, {
    method: 'POST',
    headers: headers(pat),
    body: JSON.stringify({
      description: 'Timekerper sync data',
      public: false,
      files: { [GIST_FILENAME]: { content: JSON.stringify(payload) } },
    }),
  })
  if (!res.ok) throw new Error(`Failed to create gist: ${res.status}`)
  const gist = await res.json()
  return gist.id
}

// Push local state to an existing gist.
export async function pushToGist(pat, gistId, payload) {
  const res = await fetch(`${API_BASE}/gists/${gistId}`, {
    method: 'PATCH',
    headers: headers(pat),
    body: JSON.stringify({
      files: { [GIST_FILENAME]: { content: JSON.stringify(payload) } },
    }),
  })
  if (!res.ok) {
    if (res.status === 404) throw new Error('gist_not_found')
    throw new Error(`Failed to push: ${res.status}`)
  }
}

// Pull remote state from a gist. Returns parsed payload.
export async function pullFromGist(pat, gistId) {
  const res = await fetch(`${API_BASE}/gists/${gistId}`, { headers: headers(pat) })
  if (!res.ok) {
    if (res.status === 404) throw new Error('gist_not_found')
    throw new Error(`Failed to pull: ${res.status}`)
  }
  const gist = await res.json()
  const content = gist.files[GIST_FILENAME]?.content
  if (!content) throw new Error('Sync file missing from gist')
  return JSON.parse(content)
}

// Build the sync payload from current app state.
export function buildPayload(tasks, events, tags, settings, activeTaskId) {
  const syncSettings = Object.fromEntries(
    Object.entries(settings).filter(([k]) => !LOCAL_ONLY_SETTINGS.includes(k))
  )
  return {
    version: 1,
    tasks,
    events,
    tags,
    settings: syncSettings,
    activeTaskId,
    pushedAt: new Date().toISOString(),
  }
}

// Compare local and remote payloads to detect meaningful changes.
// Returns true if remote data differs from local.
export function hasChanges(localPayload, remotePayload) {
  // Compare the data fields, ignoring pushedAt timestamp
  const fields = ['tasks', 'events', 'tags', 'activeTaskId']
  for (const field of fields) {
    if (JSON.stringify(localPayload[field]) !== JSON.stringify(remotePayload[field])) {
      return true
    }
  }
  // Compare settings separately — strip LOCAL_ONLY keys from both sides so
  // iOS's "reset-to-default" approach (keeps keys with default values) doesn't
  // cause false positives vs the web's "delete key" approach.
  const stripLocal = (s) => s ? Object.fromEntries(
    Object.entries(s).filter(([k]) => !LOCAL_ONLY_SETTINGS.includes(k))
  ) : s
  if (JSON.stringify(stripLocal(localPayload.settings)) !== JSON.stringify(stripLocal(remotePayload.settings))) {
    return true
  }
  return false
}
