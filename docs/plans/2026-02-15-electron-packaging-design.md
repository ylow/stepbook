# Electron Packaging Design

## Purpose

Package Stepbook as a desktop app so non-developers can run it locally by double-clicking an `.app` (macOS) or `.exe` (Windows).

## Decisions

- **Electron** — bundles Chromium + Node.js, gives a native app experience
- **Platforms:** macOS + Windows
- **Data location:** `~/Documents/Stepbook/` (macOS) / `Documents\Stepbook\` (Windows) — visible, easy to back up
- **UI indicator:** Home page shows data save location with backup reminder

## How It Works

1. User launches the Electron app
2. Electron main process starts the Express server on a random available port
3. Opens a BrowserWindow pointing at `http://localhost:<port>`
4. On quit, the server shuts down cleanly

## Data Storage

- `~/Documents/Stepbook/stepbook.db` — SQLite database
- `~/Documents/Stepbook/images/` — uploaded step images

## Project Structure Changes

- New `electron/main.js` — Electron entry point (start server, open window, handle quit)
- `electron-builder` config in `package.json` for packaging
- Refactor `server/db.js` and `server/index.js` to accept a configurable data directory via environment variable or argument
- Same server code works in both dev mode (`data/` relative) and Electron mode (`~/Documents/Stepbook/`)

## UI Change

- Home page shows "Data saved to ~/Documents/Stepbook/" with backup reminder below the header

## What Doesn't Change

- `npm run dev` works the same for development
- All existing routes, components, and features are untouched
