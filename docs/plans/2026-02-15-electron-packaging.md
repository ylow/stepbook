# Electron Packaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Package Stepbook as a desktop Electron app for macOS and Windows so non-developers can run it locally.

**Architecture:** Extract a configurable data directory from hardcoded paths, refactor the Express server to start programmatically, create an Electron main process that launches the server on a random port and opens a BrowserWindow. Use electron-builder for packaging. Data stored in `~/Documents/Stepbook/`.

**Tech Stack:** Electron, electron-builder, existing Express + Vue stack.

---

### Task 1: Extract configurable data directory

**Files:**
- Create: `server/config.js`
- Modify: `server/db.js`
- Modify: `server/index.js`
- Modify: `server/routes/sequences.js`
- Modify: `server/routes/steps.js`
- Modify: `server/routes/transfer.js`

**Step 1: Create `server/config.js`**

This module centralizes the data directory. All other server files import from here instead of computing paths themselves.

```javascript
const path = require('path');
const fs = require('fs');

const DATA_DIR = process.env.STEPBOOK_DATA_DIR || path.join(__dirname, '..', 'data');
const IMAGES_DIR = path.join(DATA_DIR, 'images');
const TMP_DIR = path.join(DATA_DIR, 'tmp');

// Ensure directories exist
fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(IMAGES_DIR, { recursive: true });

module.exports = { DATA_DIR, IMAGES_DIR, TMP_DIR };
```

**Step 2: Update `server/db.js` to use config**

Replace lines 1-10 with:

```javascript
const Database = require('better-sqlite3');
const path = require('path');
const { DATA_DIR } = require('./config');

const DB_PATH = path.join(DATA_DIR, 'stepbook.db');

const db = new Database(DB_PATH);
```

Remove the `fs` import and `mkdirSync` calls (config.js handles that now).

**Step 3: Update `server/index.js` line 20**

Replace:
```javascript
app.use('/images', express.static(path.join(__dirname, '..', 'data', 'images')));
```
With:
```javascript
const { IMAGES_DIR } = require('./config');
app.use('/images', express.static(IMAGES_DIR));
```

**Step 4: Update `server/routes/sequences.js` line 64**

Replace:
```javascript
const imageDir = path.join(__dirname, '..', '..', 'data', 'images', req.params.id);
```
With:
```javascript
const { IMAGES_DIR } = require('../config');
// ... (inside the delete handler)
const imageDir = path.join(IMAGES_DIR, req.params.id);
```

Move the require to the top of the file (after existing requires).

**Step 5: Update `server/routes/steps.js` lines 13, 100**

Add at top:
```javascript
const { IMAGES_DIR } = require('../config');
```

Replace line 13:
```javascript
const dir = path.join(IMAGES_DIR, req.params.sequenceId);
```

Replace line 100:
```javascript
const imagePath = path.join(IMAGES_DIR, step.image_path);
```

**Step 6: Update `server/routes/transfer.js` lines 11, 76, 142, 237**

Add at top:
```javascript
const { IMAGES_DIR, TMP_DIR } = require('../config');
```

Replace line 11 (`tmpDir`):
```javascript
const tmpDir = TMP_DIR;
```

Replace line 76, 142, 237 (all `imagesDir` / `seqImagesDir` references):
- Line 76: `const imagesDir = IMAGES_DIR;`
- Line 142: `const imagesDir = IMAGES_DIR;`
- Line 237: `const seqImagesDir = path.join(IMAGES_DIR, sequenceId);`

**Step 7: Verify server still works**

Run:
```bash
node -e "require('./server/config'); require('./server/db'); console.log('OK')"
```
Expected: `OK`

**Step 8: Commit**

```bash
git add server/config.js server/db.js server/index.js server/routes/sequences.js server/routes/steps.js server/routes/transfer.js
git commit -m "refactor: extract configurable data directory into server/config.js"
```

---

### Task 2: Refactor server to start programmatically

**Files:**
- Modify: `server/index.js`

Currently `server/index.js` calls `app.listen()` on import. Refactor so it exports a `startServer` function that returns a promise resolving to `{ app, server, port }`. This lets Electron start the server on a random port.

**Step 1: Refactor `server/index.js`**

Replace the entire file with:

```javascript
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { IMAGES_DIR } = require('./config');

function createApp() {
  const app = express();

  // In production, serve the built Vue app's static assets FIRST
  const clientDist = path.join(__dirname, '..', 'client', 'dist');
  const hasClientDist = fs.existsSync(clientDist);
  if (hasClientDist) {
    app.use(express.static(clientDist));
  }

  app.use(cors());
  app.use(express.json());

  // Serve uploaded images
  app.use('/images', express.static(IMAGES_DIR));

  // API routes
  app.use('/api/sequences', require('./routes/sequences'));
  app.use('/api/sequences', require('./routes/steps'));
  app.use('/api', require('./routes/steps'));
  app.use('/api/sequences', require('./routes/transfer'));

  // SPA fallback: serve index.html for any non-API GET route
  if (hasClientDist) {
    app.use((req, res, next) => {
      if (req.method === 'GET' && !req.path.startsWith('/api/') && !req.path.startsWith('/images/')) {
        res.sendFile(path.join(clientDist, 'index.html'));
      } else {
        next();
      }
    });
  }

  return app;
}

function startServer(port = 0) {
  return new Promise((resolve, reject) => {
    const app = createApp();
    const server = app.listen(port, () => {
      const actualPort = server.address().port;
      console.log(`Server running on http://localhost:${actualPort}`);
      resolve({ app, server, port: actualPort });
    });
    server.on('error', reject);
  });
}

// If run directly (not imported), start on the configured port
if (require.main === module) {
  const PORT = process.env.PORT || 3001;
  startServer(PORT);
}

module.exports = { createApp, startServer };
```

**Step 2: Verify `npm start` still works**

Run:
```bash
node server/index.js
```
Expected: `Server running on http://localhost:3001` — then Ctrl+C to stop.

**Step 3: Verify programmatic start works**

Run:
```bash
node -e "require('./server/index').startServer(0).then(({port}) => { console.log('Started on', port); process.exit(0); })"
```
Expected: `Started on <random port>`

**Step 4: Commit**

```bash
git add server/index.js
git commit -m "refactor: make server startable programmatically for Electron"
```

---

### Task 3: Add config API endpoint and data directory display

**Files:**
- Modify: `server/index.js` (add `/api/config` route)
- Modify: `client/src/api.js` (add `fetchConfig`)
- Modify: `client/src/views/HomeView.vue` (show data path)

**Step 1: Add `/api/config` route in `server/index.js`**

Inside the `createApp()` function, after the line `app.use(express.json());` and before the image static route, add:

```javascript
// Config endpoint — tells the frontend where data is stored
const { DATA_DIR } = require('./config');
app.get('/api/config', (req, res) => {
  res.json({ dataDir: DATA_DIR });
});
```

**Step 2: Add `fetchConfig` to `client/src/api.js`**

Add at the end of the file:

```javascript
export async function fetchConfig() {
  const res = await fetch(`${API}/config`)
  return res.json()
}
```

**Step 3: Update `client/src/views/HomeView.vue`**

Add import of `fetchConfig`:
```javascript
import { fetchSequences, createSequence, deleteSequence, exportSequence, importSequence, fetchConfig } from '../api.js'
```

Add a ref for the data path:
```javascript
const dataDir = ref('')
```

In the `load()` function, fetch the config:
```javascript
async function load() {
  sequences.value = await fetchSequences()
  if (!dataDir.value) {
    try {
      const config = await fetchConfig()
      dataDir.value = config.dataDir
    } catch {}
  }
}
```

Add a template element below the header and above the create form:
```html
<p v-if="dataDir" class="data-info">
  Data saved to <strong>{{ dataDir }}</strong> — back up this folder to preserve your work.
</p>
```

Add CSS:
```css
.data-info {
  color: #888;
  font-size: 13px;
  margin-bottom: 16px;
}
```

**Step 4: Build and verify**

```bash
npm run build && node server/index.js
```
Open http://localhost:3001 — verify the data path appears below the header.

**Step 5: Commit**

```bash
git add server/index.js client/src/api.js client/src/views/HomeView.vue
git commit -m "feat: show data directory location on home page"
```

---

### Task 4: Install Electron dependencies

**Files:**
- Modify: `package.json`

**Step 1: Install electron and electron-builder as dev dependencies**

```bash
npm install --save-dev electron electron-builder
```

**Step 2: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: add electron and electron-builder dev dependencies"
```

---

### Task 5: Create Electron main process

**Files:**
- Create: `electron/main.js`

**Step 1: Create `electron/main.js`**

```javascript
const { app, BrowserWindow } = require('electron');
const path = require('path');

// Set data directory to ~/Documents/Stepbook before anything else loads
const documentsDir = app.getPath('documents');
const dataDir = path.join(documentsDir, 'Stepbook');
process.env.STEPBOOK_DATA_DIR = dataDir;

const { startServer } = require('../server/index');

let mainWindow;
let server;

async function createWindow() {
  const { port } = await startServer(0);

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    title: 'Stepbook',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  mainWindow.loadURL(`http://localhost:${port}`);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (server) {
    server.close();
  }
  app.quit();
});

app.on('activate', () => {
  if (mainWindow === null) {
    createWindow();
  }
});
```

**Step 2: Verify it loads without syntax errors**

```bash
node -e "try { require('./electron/main.js') } catch(e) { console.log(e.message) }"
```
Expected: An error about Electron not being available (that's fine — it can only run inside Electron), but no syntax errors.

**Step 3: Commit**

```bash
git add electron/main.js
git commit -m "feat: add Electron main process"
```

---

### Task 6: Configure electron-builder and add scripts

**Files:**
- Modify: `package.json`

**Step 1: Update `package.json`**

Add/update these fields:

Change `"main"` from `"index.js"` to `"electron/main.js"`.

Add these scripts:
```json
"electron:dev": "npm run build && electron .",
"electron:build": "npm run build && electron-builder"
```

Add the `build` config for electron-builder:
```json
"build": {
  "appId": "com.stepbook.app",
  "productName": "Stepbook",
  "directories": {
    "output": "dist-electron"
  },
  "files": [
    "server/**/*",
    "client/dist/**/*",
    "electron/**/*",
    "node_modules/**/*",
    "package.json"
  ],
  "mac": {
    "target": "dmg"
  },
  "win": {
    "target": "nsis"
  },
  "asarUnpack": [
    "node_modules/better-sqlite3/**/*"
  ]
}
```

The `asarUnpack` for `better-sqlite3` is critical — it's a native module that can't run from inside an asar archive.

**Step 2: Add `dist-electron/` to `.gitignore`**

Append `dist-electron/` to `.gitignore`.

**Step 3: Test `electron:dev`**

```bash
npm run electron:dev
```

Expected: The Vue client builds, then an Electron window opens showing Stepbook at `http://localhost:<port>`. The home page should display "Data saved to /Users/<you>/Documents/Stepbook/".

**Step 4: Commit**

```bash
git add package.json .gitignore
git commit -m "feat: add electron-builder config and build scripts"
```

---

### Task 7: Build and test the packaged app

**Step 1: Build the Electron app for the current platform**

```bash
npm run electron:build -- --mac
```

Expected: Creates a `.dmg` in `dist-electron/`. On Windows, use `--win` instead.

**Step 2: Install and test the packaged app**

1. Open the `.dmg` and drag Stepbook to Applications
2. Launch Stepbook from Applications
3. Verify: window opens, home page shows data path `~/Documents/Stepbook/`
4. Create a sequence, add steps with images, add annotations and notes
5. Export the sequence as a zip
6. Import the zip — verify new sequence appears
7. Quit and relaunch — verify data persists
8. Check `~/Documents/Stepbook/` — verify `stepbook.db` and `images/` exist

**Step 3: Commit any fixes if needed**

---

### Task 8: Update README

**Files:**
- Modify: `README.md`

**Step 1: Add Electron section to README**

Add a section after "Production" covering:
- How to run the desktop app in development (`npm run electron:dev`)
- How to build the desktop app (`npm run electron:build`)
- Where data is stored (`~/Documents/Stepbook/`)
- Supported platforms (macOS, Windows)

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add Electron desktop app section to README"
```
