# Zip Export/Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable users to export sequences as zip files and import sequences from zip files for sharing between Stepbook instances.

**Architecture:** Server-side zip creation/parsing via new `server/routes/transfer.js`. Export streams a zip built with `archiver` containing a `manifest.json` and image files. Import accepts a zip upload via multer, extracts it with `adm-zip`, creates a new sequence with fresh UUIDs, and copies images into place.

**Tech Stack:** Express.js backend, `archiver` for zip creation, `adm-zip` for zip reading, `multer` for upload handling, Vue 3 frontend.

---

### Task 1: Install dependencies

**Files:**
- Modify: `package.json`

**Step 1: Install archiver and adm-zip**

Run:
```bash
cd /Users/ylow/repos/stepbook && npm install archiver adm-zip
```

Expected: Both packages added to `dependencies` in `package.json`.

**Step 2: Commit**

```bash
git add package.json package-lock.json
git commit -m "feat: add archiver and adm-zip dependencies for zip export/import"
```

---

### Task 2: Create export endpoint

**Files:**
- Create: `server/routes/transfer.js`
- Modify: `server/index.js:23-25` (add route registration)

**Step 1: Create `server/routes/transfer.js` with export endpoint**

```javascript
const express = require('express');
const path = require('path');
const fs = require('fs');
const archiver = require('archiver');
const db = require('../db');

const router = express.Router();

const DATA_DIR = path.join(__dirname, '..', '..', 'data');
const IMAGES_DIR = path.join(DATA_DIR, 'images');

// Export a sequence as a zip file
router.get('/:id/export', (req, res) => {
  const sequence = db.prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  if (!sequence) return res.status(404).json({ error: 'Sequence not found' });

  const steps = db.prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(req.params.id);

  const manifest = {
    version: 1,
    sequence: {
      title: sequence.title,
      description: sequence.description
    },
    steps: steps.map(step => {
      const ext = path.extname(step.image_path);
      return {
        order_index: step.order_index,
        image_filename: `${step.order_index}${ext}`,
        annotations: JSON.parse(step.annotations || '{}'),
        notes: step.notes || ''
      };
    })
  };

  const safeTitle = sequence.title.replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 50);
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="${safeTitle}.zip"`);

  const archive = archiver('zip', { zlib: { level: 5 } });
  archive.on('error', (err) => {
    res.status(500).json({ error: 'Failed to create zip' });
  });
  archive.pipe(res);

  // Add manifest
  archive.append(JSON.stringify(manifest, null, 2), { name: 'manifest.json' });

  // Add images
  for (const step of steps) {
    const imagePath = path.join(IMAGES_DIR, step.image_path);
    const ext = path.extname(step.image_path);
    if (fs.existsSync(imagePath)) {
      archive.file(imagePath, { name: `images/${step.order_index}${ext}` });
    }
  }

  archive.finalize();
});

module.exports = router;
```

**Step 2: Register the route in `server/index.js`**

Add after line 25 (`app.use('/api', require('./routes/steps'));`):

```javascript
app.use('/api/sequences', require('./routes/transfer'));
```

**Step 3: Test manually**

Run:
```bash
cd /Users/ylow/repos/stepbook && npm run dev
```

Then in another terminal:
```bash
curl -o test-export.zip http://localhost:3001/api/sequences/<SOME_ID>/export
unzip -l test-export.zip
```

Expected: Zip contains `manifest.json` and `images/` directory with image files.

**Step 4: Commit**

```bash
git add server/routes/transfer.js server/index.js
git commit -m "feat: add export endpoint for sequences as zip files"
```

---

### Task 3: Add import endpoint

**Files:**
- Modify: `server/routes/transfer.js`

**Step 1: Add import endpoint to `server/routes/transfer.js`**

Add these requires at the top (after existing requires):
```javascript
const AdmZip = require('adm-zip');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
```

Add multer config after the `IMAGES_DIR` constant:
```javascript
const uploadDir = path.join(DATA_DIR, 'tmp');
fs.mkdirSync(uploadDir, { recursive: true });

const upload = multer({
  dest: uploadDir,
  limits: { fileSize: 100 * 1024 * 1024 }, // 100MB max zip
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'application/zip' || file.originalname.endsWith('.zip')) {
      cb(null, true);
    } else {
      cb(new Error('Only zip files are allowed'));
    }
  }
});
```

Add the import endpoint before `module.exports`:
```javascript
// Import a sequence from a zip file
router.post('/import', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Zip file is required' });

  let zip;
  try {
    zip = new AdmZip(req.file.path);
  } catch (err) {
    fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'Invalid zip file' });
  }

  const manifestEntry = zip.getEntry('manifest.json');
  if (!manifestEntry) {
    fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'Missing manifest.json in zip' });
  }

  let manifest;
  try {
    manifest = JSON.parse(manifestEntry.getData().toString('utf8'));
  } catch (err) {
    fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'Invalid manifest.json' });
  }

  if (!manifest.sequence || !manifest.sequence.title || !Array.isArray(manifest.steps)) {
    fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'Invalid manifest format' });
  }

  // Create new sequence
  const sequenceId = uuidv4();
  const seqImageDir = path.join(IMAGES_DIR, sequenceId);
  fs.mkdirSync(seqImageDir, { recursive: true });

  db.prepare('INSERT INTO sequences (id, title, description) VALUES (?, ?, ?)').run(
    sequenceId,
    manifest.sequence.title,
    manifest.sequence.description || ''
  );

  // Create steps
  const insertStep = db.prepare(
    'INSERT INTO steps (id, sequence_id, order_index, image_path, annotations, notes) VALUES (?, ?, ?, ?, ?, ?)'
  );

  const importSteps = db.transaction((steps) => {
    for (const step of steps) {
      const imageEntry = zip.getEntry(`images/${step.image_filename}`);
      if (!imageEntry) continue;

      const stepId = uuidv4();
      const ext = path.extname(step.image_filename);
      const imageFilename = `${stepId}${ext}`;
      const imageDest = path.join(seqImageDir, imageFilename);

      fs.writeFileSync(imageDest, imageEntry.getData());

      insertStep.run(
        stepId,
        sequenceId,
        step.order_index,
        `${sequenceId}/${imageFilename}`,
        JSON.stringify(step.annotations || {}),
        step.notes || ''
      );
    }
  });

  importSteps(manifest.steps);

  // Clean up uploaded zip
  fs.unlinkSync(req.file.path);

  const sequence = db.prepare('SELECT * FROM sequences WHERE id = ?').get(sequenceId);
  const steps = db.prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(sequenceId);
  res.status(201).json({ ...sequence, steps });
});
```

**Step 2: Test round-trip**

Export a sequence, then import the zip:
```bash
curl -X POST -F "file=@test-export.zip" http://localhost:3001/api/sequences/import
```

Expected: Returns new sequence JSON with fresh IDs and all steps.

**Step 3: Commit**

```bash
git add server/routes/transfer.js
git commit -m "feat: add import endpoint for sequences from zip files"
```

---

### Task 4: Add client API functions

**Files:**
- Modify: `client/src/api.js`

**Step 1: Add export and import functions to `client/src/api.js`**

Add at the end of the file:
```javascript
export async function exportSequence(id) {
  const res = await fetch(`${API}/sequences/${id}/export`)
  if (!res.ok) throw new Error('Export failed')
  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = res.headers.get('Content-Disposition')?.match(/filename="(.+)"/)?.[1] || 'sequence.zip'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

export async function importSequence(file) {
  const form = new FormData()
  form.append('file', file)
  const res = await fetch(`${API}/sequences/import`, {
    method: 'POST',
    body: form
  })
  if (!res.ok) {
    const err = await res.json()
    throw new Error(err.error || 'Import failed')
  }
  return res.json()
}
```

**Step 2: Commit**

```bash
git add client/src/api.js
git commit -m "feat: add client API functions for export/import"
```

---

### Task 5: Add export button to sequence cards

**Files:**
- Modify: `client/src/components/SequenceList.vue`

**Step 1: Add export button and emit to `SequenceList.vue`**

Add an export button next to the delete button in the template (inside `.sequence-card`, before the delete button):
```html
<button class="export-btn" @click.stop="$emit('export', seq.id)" title="Export as zip">&#8615;</button>
```

Update the `defineEmits`:
```javascript
defineEmits(['delete', 'export'])
```

Add CSS for `.export-btn` (same style as `.delete-btn` but positioned to the left):
```css
.export-btn {
  position: absolute;
  top: 8px;
  right: 42px;
  background: rgba(0,0,0,0.6);
  color: #64b5f6;
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 18px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.sequence-card:hover .export-btn {
  display: flex;
}
```

**Step 2: Commit**

```bash
git add client/src/components/SequenceList.vue
git commit -m "feat: add export button to sequence cards"
```

---

### Task 6: Add import button and wire up HomeView

**Files:**
- Modify: `client/src/views/HomeView.vue`

**Step 1: Add import button and export handler to `HomeView.vue`**

In the template, add an import button next to the existing "New Sequence" button and a hidden file input. Update the header:
```html
<header class="home-header">
  <h1>Stepbook</h1>
  <div class="header-actions">
    <button @click="triggerImport">Import Zip</button>
    <button @click="showCreate = true">+ New Sequence</button>
    <input
      ref="importInput"
      type="file"
      accept=".zip"
      style="display: none"
      @change="handleImport"
    />
  </div>
</header>
```

In the `<SequenceList>` tag, add the export handler:
```html
<SequenceList
  v-if="sequences.length"
  :sequences="sequences"
  @delete="handleDelete"
  @export="handleExport"
/>
```

In the `<script setup>`, add imports and handlers:

Update the import line:
```javascript
import { fetchSequences, createSequence, deleteSequence, exportSequence, importSequence } from '../api.js'
```

Add ref:
```javascript
const importInput = ref(null)
```

Add functions:
```javascript
async function handleExport(id) {
  try {
    await exportSequence(id)
  } catch (e) {
    alert('Export failed: ' + e.message)
  }
}

function triggerImport() {
  importInput.value.click()
}

async function handleImport(e) {
  const file = e.target.files[0]
  if (!file) return
  try {
    await importSequence(file)
    await load()
  } catch (e) {
    alert('Import failed: ' + e.message)
  }
  importInput.value.value = ''
}
```

Add CSS for header actions:
```css
.header-actions {
  display: flex;
  gap: 8px;
}
```

**Step 2: Commit**

```bash
git add client/src/views/HomeView.vue
git commit -m "feat: add import button and wire up export/import in HomeView"
```

---

### Task 7: Manual end-to-end test

**Step 1: Start the dev server**

```bash
cd /Users/ylow/repos/stepbook && npm run dev
```

**Step 2: Test in browser**

1. Open http://localhost:5173
2. Create a sequence with a few steps (upload images, add annotations and notes)
3. Go back to home page
4. Hover over the sequence card — verify export button appears
5. Click export button — verify a zip file downloads
6. Inspect the zip: should contain `manifest.json` and `images/` with numbered image files
7. Click "Import Zip" — select the downloaded zip
8. Verify a new sequence appears in the list with the same title, steps, annotations, and notes
9. Open the imported sequence — verify all images display, annotations render, and notes are present

**Step 3: Commit any fixes if needed**
