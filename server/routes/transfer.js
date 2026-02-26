const express = require('express');
const path = require('path');
const fs = require('fs');
const archiver = require('archiver');
const AdmZip = require('adm-zip');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const { getDb, getImagesDir, getTmpDir } = require('../book-context');

// Configure multer for zip file uploads with dynamic temp directory
const importStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const tmpDir = getTmpDir();
    fs.mkdirSync(tmpDir, { recursive: true });
    cb(null, tmpDir);
  },
  filename: (req, file, cb) => {
    cb(null, `import-${Date.now()}-${file.originalname}`);
  }
});

const importUpload = multer({
  storage: importStorage,
  limits: { fileSize: 100 * 1024 * 1024 }, // 100MB
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'application/zip' || file.originalname.endsWith('.zip') || file.originalname.endsWith('.stepseq')) {
      cb(null, true);
    } else {
      cb(new Error('Only .stepseq and .zip files are allowed'));
    }
  }
});

const ALLOWED_IMAGE_EXTS = /\.(jpg|jpeg|png|gif|webp)$/i;
const MAX_IMAGE_SIZE = 50 * 1024 * 1024; // 50MB per image

const router = express.Router();

// Export a sequence as a zip file
router.get('/:id/export', (req, res) => {
  const sequence = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  if (!sequence) return res.status(404).json({ error: 'Sequence not found' });

  const steps = getDb().prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(req.params.id);

  // Build manifest
  const manifest = {
    version: 1,
    sequence: {
      title: sequence.title,
      description: sequence.description
    },
    steps: steps.map((step) => {
      const ext = path.extname(step.image_path) || '.png';
      return {
        order_index: step.order_index,
        image_filename: `${step.order_index}${ext}`,
        annotations: typeof step.annotations === 'string' ? JSON.parse(step.annotations) : step.annotations,
        notes: step.notes
      };
    })
  };

  // Sanitize title for use as filename
  const safeTitle = sequence.title.replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 50) || 'sequence';

  res.set('Content-Type', 'application/octet-stream');
  res.set('Content-Disposition', `attachment; filename="${safeTitle}.stepseq"`);

  const archive = archiver('zip', { zlib: { level: 5 } });

  archive.on('error', (err) => {
    console.error('Archive error:', err);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to create archive' });
    }
  });

  archive.pipe(res);

  // Add manifest.json
  archive.append(JSON.stringify(manifest, null, 2), { name: 'manifest.json' });

  // Add step images
  const imagesDir = getImagesDir();
  for (const step of steps) {
    const ext = path.extname(step.image_path) || '.png';
    const imagePath = path.join(imagesDir, step.image_path);
    if (!path.resolve(imagePath).startsWith(path.resolve(imagesDir))) continue;
    if (fs.existsSync(imagePath)) {
      archive.file(imagePath, { name: `images/${step.order_index}${ext}` });
    }
  }

  archive.finalize();
});

// Import a sequence from a zip file
router.post('/import', importUpload.single('file'), (req, res) => {
  const tmpFile = req.file ? req.file.path : null;

  // Helper to clean up the temp file
  const cleanup = () => {
    if (tmpFile && fs.existsSync(tmpFile)) {
      try { fs.unlinkSync(tmpFile); } catch (e) { /* ignore */ }
    }
  };

  let sequenceId = null;
  const imagesDir = getImagesDir();

  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Zip file is required' });
    }

    // Parse the zip file
    let zip;
    try {
      zip = new AdmZip(tmpFile);
    } catch (err) {
      cleanup();
      return res.status(400).json({ error: 'Invalid zip file' });
    }

    // Extract and validate manifest.json
    const manifestEntry = zip.getEntry('manifest.json');
    if (!manifestEntry) {
      cleanup();
      return res.status(400).json({ error: 'Missing manifest.json in zip' });
    }

    let manifest;
    try {
      manifest = JSON.parse(manifestEntry.getData().toString('utf8'));
    } catch (err) {
      cleanup();
      return res.status(400).json({ error: 'Invalid manifest.json: not valid JSON' });
    }

    // Validate manifest structure
    if (!manifest.sequence || !manifest.sequence.title) {
      cleanup();
      return res.status(400).json({ error: 'Invalid manifest: missing sequence.title' });
    }
    if (!Array.isArray(manifest.steps)) {
      cleanup();
      return res.status(400).json({ error: 'Invalid manifest: missing steps array' });
    }

    sequenceId = uuidv4();
    const seqImagesDir = path.join(imagesDir, sequenceId);
    fs.mkdirSync(seqImagesDir, { recursive: true });

    // Prepare step data and extract images
    const stepsToInsert = [];
    for (let i = 0; i < manifest.steps.length; i++) {
      const stepManifest = manifest.steps[i];
      const imageFilename = stepManifest.image_filename;

      if (!imageFilename || typeof imageFilename !== 'string') {
        // Clean up already-created images directory
        fs.rmSync(seqImagesDir, { recursive: true, force: true });
        cleanup();
        return res.status(400).json({ error: `Invalid manifest: step ${i} missing image_filename` });
      }

      // Path traversal guard: ensure image_filename is a simple filename (no slashes, no ..)
      const normalizedFilename = path.basename(imageFilename);
      if (normalizedFilename !== imageFilename || imageFilename.includes('..')) {
        fs.rmSync(seqImagesDir, { recursive: true, force: true });
        cleanup();
        return res.status(400).json({ error: `Invalid manifest: step ${i} has invalid image_filename` });
      }

      // Validate image extension
      if (!ALLOWED_IMAGE_EXTS.test(imageFilename)) {
        fs.rmSync(seqImagesDir, { recursive: true, force: true });
        cleanup();
        return res.status(400).json({ error: `Invalid image type for step ${i}: ${imageFilename}` });
      }

      // Look for the image in the zip under images/ directory
      const imageEntry = zip.getEntry(`images/${imageFilename}`);
      if (!imageEntry) {
        fs.rmSync(seqImagesDir, { recursive: true, force: true });
        cleanup();
        return res.status(400).json({ error: `Missing image file in zip: images/${imageFilename}` });
      }

      // Guard against zip bombs
      if (imageEntry.header.size > MAX_IMAGE_SIZE) {
        fs.rmSync(seqImagesDir, { recursive: true, force: true });
        cleanup();
        return res.status(400).json({ error: `Image file too large: images/${imageFilename}` });
      }

      const stepId = uuidv4();
      const ext = path.extname(imageFilename) || '.png';
      const destFilename = `${stepId}${ext}`;
      const destPath = path.join(seqImagesDir, destFilename);

      // Verify the resolved destination is within the expected directory
      if (!path.resolve(destPath).startsWith(path.resolve(seqImagesDir))) {
        fs.rmSync(seqImagesDir, { recursive: true, force: true });
        cleanup();
        return res.status(400).json({ error: 'Path traversal detected' });
      }

      // Write the image file
      fs.writeFileSync(destPath, imageEntry.getData());

      const imagePath = `${sequenceId}/${destFilename}`;
      const annotations = stepManifest.annotations
        ? (typeof stepManifest.annotations === 'string' ? stepManifest.annotations : JSON.stringify(stepManifest.annotations))
        : '{}';
      const notes = stepManifest.notes || '';
      const orderIndex = stepManifest.order_index !== undefined ? stepManifest.order_index : i;

      stepsToInsert.push({ stepId, orderIndex, imagePath, annotations, notes });
    }

    // Insert sequence and all steps in a transaction
    const db = getDb();
    const insertSequence = db.prepare('INSERT INTO sequences (id, title, description) VALUES (?, ?, ?)');
    const insertStep = db.prepare('INSERT INTO steps (id, sequence_id, order_index, image_path, annotations, notes) VALUES (?, ?, ?, ?, ?, ?)');

    const importTransaction = db.transaction(() => {
      insertSequence.run(sequenceId, manifest.sequence.title, manifest.sequence.description || '');
      for (const step of stepsToInsert) {
        insertStep.run(step.stepId, sequenceId, step.orderIndex, step.imagePath, step.annotations, step.notes);
      }
    });

    importTransaction();

    cleanup();

    // Return the newly created sequence with steps
    const sequence = db.prepare('SELECT * FROM sequences WHERE id = ?').get(sequenceId);
    const steps = db.prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(sequenceId);
    res.status(201).json({ ...sequence, steps });
  } catch (err) {
    cleanup();
    // If images were partially written, try to clean up the image directory
    if (sequenceId) {
      const seqImagesDir = path.join(imagesDir, sequenceId);
      try {
        if (fs.existsSync(seqImagesDir)) {
          fs.rmSync(seqImagesDir, { recursive: true, force: true });
        }
      } catch (e) { /* ignore cleanup errors */ }
    }
    console.error('Import error:', err);
    res.status(500).json({ error: 'Failed to import sequence' });
  }
});

module.exports = router;
