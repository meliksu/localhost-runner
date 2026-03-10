# Localhost Runner — Design Spec

Mac menu bar app that shows all projects running on localhost, with project name, port, and runtime info. Click to open in browser.

## Architecture

- **Platform**: macOS 13+ (SwiftUI + AppKit hybrid)
- **Approach**: SwiftUI app with `MenuBarExtra` for menu bar integration, `lsof` for port/process detection
- **No Dock icon**: `LSUIElement = true`
- **No main window**: Menu bar only

### Components

1. **`LocalhostRunnerApp`** — `@main` SwiftUI App with `MenuBarExtra`. Displays project count in menu bar.
2. **`PortScanner`** — Executes `lsof`, parses output, resolves working directories per PID. Returns `[LocalProject]`.
3. **`LocalProject`** (Model) — name (folder name), port, PID, process type (node/python/vite/etc.)

## Menu Bar

- **Icon**: Number showing count of running projects (e.g. "3")
- **Empty state**: Greyed-out "0" when no projects are running
- **Autostart**: Login item via `SMAppService`, enabled by default

## Dropdown Menu (Layout: "Detailed")

Each project entry shows two lines:
- **Line 1**: Project name (bold)
- **Line 2**: `localhost:{port}` + runtime (e.g. "node", "python")

Footer items:
- Refresh button
- Settings link
- Quit

**Click action**: Opens `http://localhost:{port}` in system default browser.

## Port Scanning & Process Detection

### Scanning Logic

1. Execute `lsof -iTCP:3000-9000 -sTCP:LISTEN -n -P` via `Process()`
2. Parse output → extract port + PID per line
3. Per PID: `lsof -p {PID} -Fn` → resolve working directory (cwd)
4. Folder name from cwd path = project name
5. Process name (node, python, ruby, etc.) = runtime info

### Filtering

- Only ports in range 3000–9000
- Ignore system processes (cwd under `/usr/` or `/System/`)
- Merge duplicates (same port, multiple file descriptors)

### Performance

- Single `lsof` call for all ports (~50ms)
- PID lookups cached until next refresh
- No polling by default — refresh on menu open or configurable interval

## Settings

Stored in `UserDefaults`. Accessed via a separate SwiftUI settings window.

| Setting | Default | Options |
|---------|---------|---------|
| Scan interval | Manual (on menu open) | Manual, 5s, 15s, 30s |
| Port range | 3000–9000 | Editable min/max |
| Autostart | On | Toggle |
| Browser | System default | — |

## Tech Stack

- Swift / SwiftUI
- `MenuBarExtra` (macOS 13+)
- `Process` (Foundation) for shell commands
- `SMAppService` for login item
- `UserDefaults` for settings
- `NSWorkspace.shared.open()` for browser launch
