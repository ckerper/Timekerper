# Timekerper

A single-page time-blocking calendar app built with React 19 + Vite. All state lives in localStorage — no backend.

## Architecture

- **`src/App.jsx`** — The entire UI: state, handlers, rendering (~1600 lines, single component)
- **`src/scheduler.js`** — Pure scheduling engine + date/time utilities. Takes tasks, events, and settings, returns positioned blocks for the calendar.
- **`src/App.css`** — All styles, CSS custom properties for theming

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
- If it's **device/session-specific** (zoom level, debug flags, window-dependent values) — add its key to the `LOCAL_ONLY_SETTINGS` array in the `exportSettings` handler so it gets excluded from export/import.
- When in doubt, ask whether the new setting should transfer across devices.

## Dev

```
cd timekerper
npm run dev     # Vite dev server on localhost:5173
npm run build   # Production build
```

## Deployment Workflow

**CRITICAL**: After making ANY code changes, you MUST automatically build and push to GitHub. Follow these steps in order:

1. **Build**: `npm run build` - Updates the production build in `/dist`
2. **Stage**: `git add .` - Stages all changed files
3. **Commit**: `git commit -m "Description of changes"` - Creates a commit with a clear message
4. **Push**: `git push` - Pushes to GitHub (updates GitHub Pages automatically)

**This workflow is mandatory for every code change** - the build and git push do not happen automatically. Always run all four commands after editing source code.
