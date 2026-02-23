# Timekerper

A single-page time-blocking calendar app built with React 19 + Vite. All state lives in localStorage — no backend.

## Architecture

- **`src/App.jsx`** — The entire UI: state, handlers, rendering (single component)
- **`src/scheduler.js`** — Pure scheduling engine + date/time utilities. Takes tasks, events, and settings, returns positioned blocks for the calendar.
- **`src/App.css`** — All styles, CSS custom properties for theming
- **`src/useSync.jsx`** — Custom hook containing all GitHub Gist sync logic (state, effects, handlers, UI). Conditionally loaded via `import.meta.glob`; only exists on GitHub.
- **`src/useSyncStub.js`** — No-op stub returning `{ syncIndicator: null, syncSettingsUI: null }`. Exists on both repos.
- **`src/sync.js`** — Pure GitHub Gist API functions (no React). Only exists on GitHub.

## Key Concepts

- **Tasks**: A global ordered queue. The scheduler fills them into available time slots around events. Tasks split across gaps, pause/resume, and overflow across days.
- **Events**: Fixed-time blocks with a `date` field. Events are blocking — tasks never overlap them.
- **Tags**: Colored labels shared between tasks and events. Stored as a separate array with `{ id, name, color }`.
- **Settings**: User preferences stored in `settings` state object (persisted to localStorage).
- **Undo/Redo**: Snapshot-based using refs. `pushUndo()` before any mutation.

## Settings Transfer (Export/Import)

The app can export and import user preferences (Settings > Transfer Settings). This covers settings that should feel the same across devices.

**When adding a new setting to `defaultSettings`:**
- If it's a **user preference** (hours, colors, durations, behavior toggles, font size) — it transfers automatically. No action needed.
- If it's **device/session-specific** (zoom level, debug flags, window-dependent values) — add its key to `LOCAL_ONLY_SETTINGS` in **both** `src/App.jsx` and `src/sync.js` so it gets excluded from export/import and sync.
- When in doubt, ask whether the new setting should transfer across devices.

## Dev

```
cd timekerper
npm run dev     # Vite dev server on localhost:5173
npm run build   # Production build
```

## Dual Deployment

Timekerper deploys to two environments:
- **GitHub Pages** (dev/test): Auto-deploys from `docs/` on push to `main`. Includes sync functionality.
- **GitLab Pages** (prod/sharing): Manual push only when the user asks. Sync code and iOS app are stripped. No references to GitHub PATs, mobile app, or multi-device syncing should exist in the GitLab code.

### How Sync Conditional Loading Works

`App.jsx` uses `import.meta.glob('./useSync.jsx', { eager: true })` to optionally load the sync hook. When `useSync.jsx` exists (GitHub), real sync is loaded. When absent (GitLab), `useSyncStub` provides null returns and no sync UI renders. `App.jsx` is identical on both repos.

### Push to Lab Workflow (only when the user explicitly asks)

```
git checkout -b gitlab-deploy
git rm src/sync.js src/useSync.jsx
git rm -r Timekerper-iOS/
git commit -m "Strip sync and iOS for GitLab deploy"
git push gitlab gitlab-deploy:main --force
git checkout main
git branch -D gitlab-deploy
```

The GitLab remote is: `https://gitlab.epic.com/timekerper/timekerper.git`

**Do NOT auto-push to GitLab.** Only push when explicitly asked.

## Deployment Workflow (GitHub — automatic)

**CRITICAL**: After making ANY code changes, you MUST follow these steps in order:

1. **Update timestamp**: Edit the `LAST_UPDATED` constant at the top of `src/App.jsx` with the current date and time in Central Time (format: `YYYY-MM-DD HH:MM AM/PM CT`). This is displayed in the Debug menu.
2. **Build**: `npm run build` - Updates the production build in `/docs`
3. **Stage**: `git add .` - Stages all changed files
4. **Commit**: `git commit -m "Description of changes"` - Creates a commit with a clear message
5. **Push**: `git push` - Pushes to GitHub (updates GitHub Pages automatically)

**These steps are mandatory for every code change** - the timestamp update, build, and git push do not happen automatically. Always run all five steps after editing source code. After pushing, always explicitly confirm to the user that you've committed and pushed to main (e.g., "Committed and pushed to `main`.").
