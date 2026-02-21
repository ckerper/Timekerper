# Timekerper iOS — Xcode Setup

## Creating the Xcode Project

1. Open Xcode on your Mac
2. **File > New > Project**
3. Choose **iOS > App**
4. Configure:
   - Product Name: `Timekerper`
   - Team: Your development team
   - Organization Identifier: `com.yourname` (or whatever you prefer)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Uncheck "Include Tests" for now (can add later)
5. Save the project somewhere temporarily

## Adding the Source Files

1. In Xcode, delete the auto-generated `ContentView.swift` and `TimekerperApp.swift` (move to trash)
2. Right-click on the project in the navigator > **Add Files to "Timekerper"**
3. Navigate to this `Timekerper-iOS/` folder
4. Select ALL the `.swift` files and folders (Models, Engine, Services, State, Views, Extensions)
5. Make sure "Copy items if needed" is checked
6. Make sure "Create groups" is selected (not "Create folder references")
7. Click **Add**

## Project Settings

1. Select the project in the navigator, then the **Timekerper** target
2. **General** tab:
   - Minimum Deployments: **iOS 17.0**
   - Device Orientation: Portrait (check), Landscape Left (optional), Landscape Right (optional)
3. **Signing & Capabilities** tab:
   - Select your Team
   - Add capability: **Keychain Sharing** (for PAT storage)
     - Keychain group: `com.timekerper.sync`

## Build & Run

1. Select an iPhone simulator (iPhone 15 or newer recommended)
2. **Cmd+R** to build and run
3. The app should launch with the default tasks/events from the web version

## File Structure

```
Models/          - Data types (TaskItem, EventItem, Tag, AppSettings, Block, SyncPayload)
Engine/          - Pure scheduling logic (Scheduler.swift, DateTimeUtils.swift)
Services/        - Side effects (PersistenceService, SyncService, KeychainService)
State/           - Observable state (AppState.swift — the brain of the app)
Views/
  Calendar/      - Day calendar view with time grid and blocks
  Tasks/         - Task list, task rows, active task bar
  Events/        - Event list, event rows
  Settings/      - Settings form, tag editor
  Modals/        - Task and event form sheets
  Components/    - Reusable components (TagSelector)
Extensions/      - Color+Hex, ColorUtils
```

## Notes

- The scheduling engine (`Scheduler.swift`) is a direct port of the web's `scheduler.js`
- Data models use the same JSON field names as the web app for Gist sync compatibility
- The Gist sync uses the same `timekerper-sync.json` filename and payload format
- Dark mode is controlled by the app's settings, not the system setting
