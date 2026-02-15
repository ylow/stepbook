const express = require('express');
const path = require('path');
const fs = require('fs');
const archiver = require('archiver');
const db = require('../db');

const router = express.Router();

// Export a sequence as a zip file
router.get('/:id/export', (req, res) => {
  const sequence = db.prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  if (!sequence) return res.status(404).json({ error: 'Sequence not found' });

  const steps = db.prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(req.params.id);

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

  res.set('Content-Type', 'application/zip');
  res.set('Content-Disposition', `attachment; filename="${safeTitle}.zip"`);

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
  const imagesDir = path.join(__dirname, '..', '..', 'data', 'images');
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

module.exports = router;
