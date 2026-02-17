const express = require('express');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { getDb, getImagesDir } = require('../book-context');

const router = express.Router();

// List all sequences
router.get('/', (req, res) => {
  const sequences = getDb().prepare(`
    SELECT s.*,
      (SELECT COUNT(*) FROM steps WHERE sequence_id = s.id) as step_count,
      (SELECT image_path FROM steps WHERE sequence_id = s.id ORDER BY order_index LIMIT 1) as thumbnail_path
    FROM sequences s
    ORDER BY s.updated_at DESC
  `).all();
  res.json(sequences);
});

// Get single sequence with all steps
router.get('/:id', (req, res) => {
  const sequence = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  if (!sequence) return res.status(404).json({ error: 'Sequence not found' });

  const steps = getDb().prepare('SELECT * FROM steps WHERE sequence_id = ? ORDER BY order_index').all(req.params.id);
  res.json({ ...sequence, steps });
});

// Create sequence
router.post('/', (req, res) => {
  const id = uuidv4();
  const { title, description } = req.body;
  if (!title) return res.status(400).json({ error: 'Title is required' });

  getDb().prepare('INSERT INTO sequences (id, title, description) VALUES (?, ?, ?)').run(id, title, description || '');

  const sequence = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(id);
  res.status(201).json(sequence);
});

// Update sequence
router.put('/:id', (req, res) => {
  const { title, description } = req.body;
  const existing = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Sequence not found' });

  getDb().prepare(`
    UPDATE sequences SET title = ?, description = ?, updated_at = datetime('now') WHERE id = ?
  `).run(title || existing.title, description !== undefined ? description : existing.description, req.params.id);

  const sequence = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  res.json(sequence);
});

// Delete sequence (cascade deletes steps, also remove image files)
router.delete('/:id', (req, res) => {
  const existing = getDb().prepare('SELECT * FROM sequences WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Sequence not found' });

  getDb().prepare('DELETE FROM sequences WHERE id = ?').run(req.params.id);

  // Remove image directory for this sequence
  const imageDir = path.join(getImagesDir(), req.params.id);
  if (fs.existsSync(imageDir)) {
    fs.rmSync(imageDir, { recursive: true });
  }

  res.status(204).end();
});

module.exports = router;
