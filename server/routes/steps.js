const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { getDb, getImagesDir } = require('../book-context');

const router = express.Router();

// Configure multer for image uploads with dynamic destination
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(getImagesDir(), req.params.sequenceId);
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const stepId = uuidv4();
    req.stepId = stepId;
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, stepId + ext);
  }
});

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => {
    const allowed = /\.(jpg|jpeg|png|gif|webp)$/i;
    if (allowed.test(path.extname(file.originalname))) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'));
    }
  },
  limits: { fileSize: 20 * 1024 * 1024 } // 20MB
});

// Add a step to a sequence
router.post('/:sequenceId/steps', upload.single('image'), (req, res) => {
  const { sequenceId } = req.params;

  const sequence = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(sequenceId);
  if (!sequence) return res.status(404).json({ error: 'Sequence not found' });

  if (!req.file) return res.status(400).json({ error: 'Image file is required' });

  const stepId = req.stepId;
  const imagePath = `${sequenceId}/${req.file.filename}`;

  // Get the next order index
  const maxOrder = getDb().prepare('SELECT MAX(order_index) as max_idx FROM steps WHERE sequence_id = ?').get(sequenceId);
  const orderIndex = (maxOrder.max_idx ?? -1) + 1;

  getDb().prepare(`
    INSERT INTO steps (id, sequence_id, order_index, image_path, annotations, notes)
    VALUES (?, ?, ?, ?, '{}', '')
  `).run(stepId, sequenceId, orderIndex, imagePath);

  // Update sequence timestamp
  getDb().prepare("UPDATE sequences SET updated_at = datetime('now') WHERE id = ?").run(sequenceId);

  const step = getDb().prepare('SELECT * FROM steps WHERE id = ?').get(stepId);
  res.status(201).json(step);
});

// Update a step (annotations, notes)
router.put('/steps/:id', (req, res) => {
  const step = getDb().prepare('SELECT * FROM steps WHERE id = ?').get(req.params.id);
  if (!step) return res.status(404).json({ error: 'Step not found' });

  const { annotations, notes } = req.body;

  getDb().prepare(`
    UPDATE steps SET
      annotations = ?,
      notes = ?,
      updated_at = datetime('now')
    WHERE id = ?
  `).run(
    annotations !== undefined ? (typeof annotations === 'string' ? annotations : JSON.stringify(annotations)) : step.annotations,
    notes !== undefined ? notes : step.notes,
    req.params.id
  );

  // Update sequence timestamp
  getDb().prepare("UPDATE sequences SET updated_at = datetime('now') WHERE id = ?").run(step.sequence_id);

  const updated = getDb().prepare('SELECT * FROM steps WHERE id = ?').get(req.params.id);
  res.json(updated);
});

// Delete a step
router.delete('/steps/:id', (req, res) => {
  const step = getDb().prepare('SELECT * FROM steps WHERE id = ?').get(req.params.id);
  if (!step) return res.status(404).json({ error: 'Step not found' });

  getDb().prepare('DELETE FROM steps WHERE id = ?').run(req.params.id);

  // Remove image file
  const imagePath = path.join(getImagesDir(), step.image_path);
  if (path.resolve(imagePath).startsWith(path.resolve(getImagesDir())) && fs.existsSync(imagePath)) {
    fs.unlinkSync(imagePath);
  }

  // Re-index remaining steps
  const remaining = getDb().prepare('SELECT id FROM steps WHERE sequence_id = ? ORDER BY order_index').all(step.sequence_id);
  const reindex = getDb().prepare('UPDATE steps SET order_index = ? WHERE id = ?');
  remaining.forEach((s, i) => reindex.run(i, s.id));

  res.status(204).end();
});

// Reorder steps in a sequence
router.put('/:sequenceId/reorder', (req, res) => {
  const { stepIds } = req.body;
  if (!Array.isArray(stepIds)) return res.status(400).json({ error: 'stepIds array is required' });

  // Validate: no duplicates
  if (new Set(stepIds).size !== stepIds.length) {
    return res.status(400).json({ error: 'Duplicate step IDs' });
  }

  // Validate: all IDs belong to this sequence and none are missing
  const existing = getDb().prepare('SELECT id FROM steps WHERE sequence_id = ?').all(req.params.sequenceId);
  const existingIds = new Set(existing.map(s => s.id));
  for (const id of stepIds) {
    if (!existingIds.has(id)) return res.status(400).json({ error: 'Invalid step ID in reorder' });
  }
  if (stepIds.length !== existingIds.size) {
    return res.status(400).json({ error: 'All steps must be included in reorder' });
  }

  const update = getDb().prepare('UPDATE steps SET order_index = ? WHERE id = ? AND sequence_id = ?');
  const reorder = getDb().transaction((ids, seqId) => {
    ids.forEach((id, index) => {
      update.run(index, id, seqId);
    });
  });

  reorder(stepIds, req.params.sequenceId);

  const steps = getDb().prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(req.params.sequenceId);
  res.json(steps);
});

module.exports = router;
