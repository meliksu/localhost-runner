# Localhost Runner

A lightweight macOS menu bar app that shows all your local dev servers at a glance. Click any project to open it in the browser.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Why?

If you're a developer running multiple projects at the same time — Next.js on port 3000, Vite on 5173, a Python API on 8000 — you know the pain of remembering which project runs on which port. Localhost Runner sits quietly in your menu bar and gives you a live overview of everything that's running.

## Features

- **Auto-detects** all dev servers running on ports 3000–9000 (configurable)
- **Shows project names** from the HTML `<title>` tag or the project folder name as fallback
- **One click** to open any project in your default browser
- **Stop servers** directly from the menu — kill any running project with one click
- **Menu bar icon** shows how many projects are currently running
- **Filters out** system processes (AirPlay, Antivirus, etc.) — only real dev servers
- **Configurable** refresh interval (manual, 5s, 15s, or 30s)
- **Autostart** at login (optional, enabled by default)
- **Zero dependencies** — pure Swift, no Electron, no background daemons
- **Privacy-friendly** — everything stays local, no network calls except to your own localhost

## Installation

### Build from source

You need Xcode Command Line Tools installed (`xcode-select --install`).

```bash
git clone https://github.com/user/localhost-runner.git
cd localhost-runner
./scripts/build-app.sh
```

This creates the app at `.build/release/Localhost Runner.app`.

**To install:**

```bash
cp -r ".build/release/Localhost Runner.app" /Applications/
```

Then open **Localhost Runner** from your Applications folder. You'll see a number appear in your menu bar — that's the count of running dev servers.

## Usage

1. **Start your dev servers** as usual (`npm run dev`, `python manage.py runserver`, etc.)
2. **Click the number** in the menu bar to see all running projects
3. **Click a project** to open it in your browser
4. **Click the X** next to a project to stop the server
5. **Click Refresh** to manually re-scan (or set an auto-refresh interval in Settings)

### Settings

Open Settings from the dropdown menu to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Scan Interval | Manual | How often to auto-refresh (off, 5s, 15s, 30s) |
| Port Range | 3000–9000 | Which ports to scan |
| Start at Login | On | Launch automatically when you log in |

## How it works

Localhost Runner uses the macOS system command `lsof` to find all processes listening on TCP ports in your configured range. For each server it finds, it:

1. Tries to fetch the HTML `<title>` from `http://localhost:{port}` for the project name
2. Falls back to the working directory folder name (e.g. `/Users/you/projects/my-app` → "my-app")
3. Filters out known system processes (ControlCenter, rapportd, etc.)

No root access needed. No background daemons. Just a single, native macOS app.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (for building from source)

## Running tests

```bash
swift test
```

## License

MIT
