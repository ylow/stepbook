const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const db = require('../db');

const router = express.Router();

// Configure multer for image uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', '..', 'data', 'images', req.params.sequenceId);
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

  const sequence = db.prepare('SELECT * FROM sequences WHERE id = ?').get(sequenceId);
  if (!sequence) return res.status(404).json({ error: 'Sequence not found' });

  if (!req.file) return res.status(400).json({ error: 'Image file is required' });

  const stepId = req.stepId;
  const imagePath = `${sequenceId}/${req.file.filename}`;

  // Get the next order index
  const maxOrder = db.prepare('SELECT MAX(order_index) as max_idx FROM steps WHERE sequence_id = ?').get(sequenceId);
  const orderIndex = (maxOrder.max_idx ?? -1) + 1;

  db.prepare(`
    INSERT INTO steps (id, sequence_id, order_index, image_path, annotations, notes)
    VALUES (?, ?, ?, ?, '{}', '')
  `).run(stepId, sequenceId, orderIndex, imagePath);

  // Update sequence timestamp
  db.prepare("UPDATE sequences SET updated_at = datetime('now') WHERE id = ?").run(sequenceId);

  const step = db.prepare('SELECT * FROM steps WHERE id = ?').get(stepId);
  res.status(201).json(step);
});

// Update a step (annotations, notes)
router.put('/steps/:id', (req, res) => {
  const step = db.prepare('SELECT * FROM steps WHERE id = ?').get(req.params.id);
  if (!step) return res.status(404).json({ error: 'Step not found' });

  const { annotations, notes } = req.body;

  db.prepare(`
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
  db.prepare("UPDATE sequences SET updated_at = datetime('now') WHERE id = ?").run(step.sequence_id);

  const updated = db.prepare('SELECT * FROM steps WHERE id = ?').get(req.params.id);
  res.json(updated);
});

// Delete a step
router.delete('/steps/:id', (req, res) => {
  const step = db.prepare('SELECT * FROM steps WHERE id = ?').get(req.params.id);
  if (!step) return res.status(404).json({ error: 'Step not found' });

  db.prepare('DELETE FROM steps WHERE id = ?').run(req.params.id);

  // Remove image file
  const imagePath = path.join(__dirname, '..', '..', 'data', 'images', step.image_path);
  if (fs.existsSync(imagePath)) fs.unlinkSync(imagePath);

  // Re-index remaining steps
  const remaining = db.prepare('SELECT id FROM steps WHERE sequence_id = ? ORDER BY order_index').all(step.sequence_id);
  const reindex = db.prepare('UPDATE steps SET order_index = ? WHERE id = ?');
  remaining.forEach((s, i) => reindex.run(i, s.id));

  res.status(204).end();
});

// Reorder steps in a sequence
router.put('/:sequenceId/reorder', (req, res) => {
  const { stepIds } = req.body;
  if (!Array.isArray(stepIds)) return res.status(400).json({ error: 'stepIds array is required' });

  const update = db.prepare('UPDATE steps SET order_index = ? WHERE id = ? AND sequence_id = ?');
  const reorder = db.transaction((ids, seqId) => {
    ids.forEach((id, index) => {
      update.run(index, id, seqId);
    });
  });

  reorder(stepIds, req.params.sequenceId);

  const steps = db.prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(req.params.sequenceId);
  res.json(steps);
});

module.exports = router;
