# Localhost Runner — Design Spec

Mac menu bar app that shows all projects running on localhost, with project name, port, and runtime info. Click to open in browser.

## Architecture

- **Platform**: macOS 13+ (SwiftUI + AppKit hybrid)
- **Approach**: SwiftUI app with `MenuBarExtra` for menu bar integration, `lsof` for port/process detection
- **Distribution**: Direct download (outside App Store) — requires code signing but no sandbox restrictions
- **No Dock icon**: `LSUIElement = true`
- **No main window**: Menu bar only
- **Concurrency**: All `lsof` / `Process()` calls run off the main thread via Swift concurrency (`Task`, `async/await`). UI updates dispatch back to `@MainActor`.

### Components

1. **`LocalhostRunnerApp`** — `@main` SwiftUI App with `MenuBarExtra` (`.window` style for custom SwiftUI content). Displays project count in menu bar.
2. **`PortScanner`** — Actor that executes `lsof`, parses output, resolves working directories per PID. Returns `[LocalProject]`.
3. **`LocalProject`** (Model) — name (folder name), port, PID, process type (node/python/etc.), cwd path, url (`http://localhost:{port}`)

## Menu Bar

- **Icon**: Number showing count of running projects (e.g. "3")
- **Empty state**: Greyed-out "0" when no projects are running
- **Autostart**: Login item via `SMAppService`, enabled by default

## Dropdown Menu (Layout: "Detailed")

Uses `MenuBarExtra` with `.window` content style. Scan triggers on `onAppear` of the content view.

Each project entry shows two lines:
- **Line 1**: Project name (bold)
- **Line 2**: `localhost:{port}` + runtime (e.g. "node", "python")

Footer items:
- Refresh button
- Settings link
- Quit

**Click action**: Opens `http://localhost:{port}` in system default browser via `NSWorkspace.shared.open()`.

## Port Scanning & Process Detection

### Scanning Logic

1. Execute `lsof -iTCP:3000-9000 -sTCP:LISTEN -n -P` via `Process()` on a background thread
2. Parse output → extract port + PID per line
3. Per PID: `lsof -p {PID} -d cwd -Fn` → resolve working directory (the `n` field from the cwd file descriptor)
4. Folder name from cwd path = project name
5. Process name from `lsof` COMMAND column (node, python, ruby, etc.) = runtime label

### Filtering

- Only ports in range 3000–9000 (configurable)
- Ignore system processes (cwd under `/usr/` or `/System/`)
- Merge duplicates: same port with both IPv4 and IPv6 listeners → single entry. Same PID on multiple ports → separate entries. Multiple PIDs on same port (fork) → single entry, first PID wins.

### Error Handling

- `lsof` not found or fails → show "Scan failed" in menu, log error
- `lsof` returns no results → show empty state ("0" greyed out, "No projects running" in menu)
- Permission issues (processes owned by other users) → silently omitted (expected behavior for non-root `lsof`)
- `Process()` timeout: 5 second timeout on all shell calls, abort and show error if exceeded
- Malformed `lsof` output → skip unparseable lines, log warning

### Performance

- Single `lsof` call for all ports (~50ms)
- PID lookups cached until next refresh
- No polling by default — refresh on menu open or configurable interval

## Settings

Stored in `UserDefaults`. Accessed via a separate SwiftUI window opened with `NSApp.activate(ignoringOtherApps: true)` + `openWindow`.

| Setting | Default | Options |
|---------|---------|---------|
| Scan interval | Manual (on menu open) | Manual, 5s, 15s, 30s |
| Port range | 3000–9000 | Editable min/max (valid: 1024–65535, min must be < max) |
| Autostart | On | Toggle |
| Browser | System default | — |

## Tech Stack

- Swift / SwiftUI
- `MenuBarExtra` with `.window` content style (macOS 13+)
- `Process` (Foundation) for shell commands
- Swift concurrency (`async/await`, actors) for background scanning
- `SMAppService` for login item
- `UserDefaults` for settings
- `NSWorkspace.shared.open()` for browser launch
