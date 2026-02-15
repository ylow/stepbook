# Stepbook

A web app for creating step-by-step visual guides with image annotations. Upload images, draw arrows and labels directly on them, add notes, and arrange steps into shareable sequences.

## Features

- **Step-by-step sequences** — Organize images into ordered steps with drag-and-drop reordering
- **Image annotations** — Draw freehand lines, arrows, and text labels on each step using a canvas editor
- **Notes** — Add written notes alongside each step
- **Export/Import** — Share sequences as zip files between Stepbook instances

## Getting Started

```bash
npm install
npm install --prefix client
npm run dev
```

This starts both the backend (port 3001) and frontend dev server (port 5173). Open http://localhost:5173.

## Production

```bash
npm run build
npm start
```

Builds the Vue frontend and serves everything from the Express server on port 3001.

## Tech Stack

- **Frontend:** Vue 3, Konva (canvas drawing), Sortable.js (drag-and-drop), Vite
- **Backend:** Express 5, SQLite (better-sqlite3), Multer (file uploads)
- **Data:** SQLite database and images stored in `data/` (dev) or `~/Documents/Stepbook/` (desktop app)
- **Desktop:** Electron — runs as a native app on macOS and Windows

## Desktop App

For users who don't want to use the command line:

```bash
npm run electron:dev       # Run the desktop app in development
npm run electron:build     # Package as .dmg (macOS) or .exe (Windows)
```

The packaged app stores data in `~/Documents/Stepbook/` (macOS) or `Documents\Stepbook\` (Windows). Back up this folder to preserve your work.

## Project Structure

```
client/          Vue 3 frontend
  src/
    components/  StepCanvas, Filmstrip, StepNotes, SequenceList
    views/       HomeView, SequenceView
    api.js       API client
server/          Express backend
  routes/        sequences, steps, transfer (export/import)
  config.js      Data directory configuration
  db.js          SQLite setup
electron/        Electron main process
data/            Runtime data (dev mode)
```

Authored by Claude Opus 4.6
