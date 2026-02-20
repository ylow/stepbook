const express = require('express');
const path = require('path');
const fs = require('fs');
const archiver = require('archiver');
const AdmZip = require('adm-zip');
const multer = require('multer');
const Database = require('better-sqlite3');
const { v4: uuidv4 } = require('uuid');
const books = require('../books');
const bookContext = require('../book-context');

const router = express.Router();

// List all books
router.get('/', (req, res) => {
  const allBooks = books.listBooks();
  const activeId = bookContext.getCurrentBookId();
  res.json(allBooks.map(b => ({ ...b, active: b.id === activeId })));
});

// Create a new book
router.post('/', (req, res) => {
  const { name } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });
  const book = books.createBook(name.trim());
  res.status(201).json(book);
});

// Add an existing folder as a book
router.post('/add', (req, res) => {
  const { name, path } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });
  if (!path || !path.trim()) return res.status(400).json({ error: 'Path is required' });
  const book = books.addBook(name.trim(), path.trim());
  res.status(201).json(book);
});

// Select/switch to a book
router.post('/:id/select', (req, res) => {
  const book = books.getBook(req.params.id);
  if (!book) return res.status(404).json({ error: 'Book not found' });
  const resolvedPath = books.resolveBookPath(book);
  bookContext.switchBook(book.id, resolvedPath);
  res.json({ ...book, active: true });
});

// Remove a book from registry (does not delete files)
router.delete('/:id', (req, res) => {
  if (req.params.id === 'default') {
    return res.status(400).json({ error: 'Cannot remove the default book' });
  }
  const removed = books.removeBook(req.params.id);
  if (!removed) return res.status(404).json({ error: 'Book not found' });
  res.status(204).end();
});

// Configure multer for book zip uploads
const ALLOWED_IMAGE_EXTS = /\.(jpg|jpeg|png|gif|webp)$/i;

const importBookStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const tmpDir = path.join(bookContext.getRootDir(), 'tmp');
    fs.mkdirSync(tmpDir, { recursive: true });
    cb(null, tmpDir);
  },
  filename: (req, file, cb) => {
    cb(null, `book-import-${Date.now()}-${file.originalname}`);
  }
});

const importBookUpload = multer({
  storage: importBookStorage,
  limits: { fileSize: 500 * 1024 * 1024 }, // 500MB
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'application/zip' || file.originalname.endsWith('.zip')) {
      cb(null, true);
    } else {
      cb(new Error('Only zip files are allowed'));
    }
  }
});

// Export a book as a zip file
router.get('/:id/export', (req, res) => {
  const book = books.getBook(req.params.id);
  if (!book) return res.status(404).json({ error: 'Book not found' });

  const bookPath = books.resolveBookPath(book);
  const dbPath = path.join(bookPath, 'stepbook.db');
  if (!fs.existsSync(dbPath)) {
    return res.status(404).json({ error: 'Book database not found' });
  }

  // Flush WAL so the .db file is self-contained
  const isActive = book.id === bookContext.getCurrentBookId();
  if (isActive) {
    bookContext.getDb().pragma('wal_checkpoint(TRUNCATE)');
  } else {
    const tmpDb = new Database(dbPath, { readonly: true });
    try { tmpDb.pragma('wal_checkpoint(TRUNCATE)'); } catch (e) { /* ignore */ }
    tmpDb.close();
  }

  const manifest = {
    version: 1,
    book: { name: book.name }
  };

  const safeName = book.name.replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 50) || 'book';

  res.set('Content-Type', 'application/zip');
  res.set('Content-Disposition', `attachment; filename="${safeName}.zip"`);

  const archive = archiver('zip', { zlib: { level: 5 } });

  archive.on('error', (err) => {
    console.error('Archive error:', err);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to create archive' });
    }
  });

  archive.pipe(res);

  // Add manifest
  archive.append(JSON.stringify(manifest, null, 2), { name: 'manifest.json' });

  // Add database
  archive.file(dbPath, { name: 'stepbook.db' });

  // Add images directory if it exists
  const imagesDir = path.join(bookPath, 'images');
  if (fs.existsSync(imagesDir)) {
    archive.directory(imagesDir, 'images');
  }

  archive.finalize();
});

// Import a book from a zip file
router.post('/import', importBookUpload.single('file'), (req, res) => {
  const tmpFile = req.file ? req.file.path : null;
  let bookDir = null;

  const cleanup = () => {
    if (tmpFile && fs.existsSync(tmpFile)) {
      try { fs.unlinkSync(tmpFile); } catch (e) { /* ignore */ }
    }
  };

  const cleanupBook = () => {
    if (bookDir && fs.existsSync(bookDir)) {
      try { fs.rmSync(bookDir, { recursive: true, force: true }); } catch (e) { /* ignore */ }
    }
  };

  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Zip file is required' });
    }

    let zip;
    try {
      zip = new AdmZip(tmpFile);
    } catch (err) {
      cleanup();
      return res.status(400).json({ error: 'Invalid zip file' });
    }

    // Validate manifest.json exists
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

    if (!manifest.book || !manifest.book.name) {
      cleanup();
      return res.status(400).json({ error: 'Invalid manifest: missing book.name' });
    }

    // Validate stepbook.db exists in zip
    const dbEntry = zip.getEntry('stepbook.db');
    if (!dbEntry) {
      cleanup();
      return res.status(400).json({ error: 'Missing stepbook.db in zip' });
    }

    // Create new book directory
    const bookId = uuidv4();
    const rootDir = bookContext.getRootDir();
    bookDir = path.join(rootDir, bookId);
    fs.mkdirSync(bookDir, { recursive: true });
    fs.mkdirSync(path.join(bookDir, 'images'), { recursive: true });
    fs.mkdirSync(path.join(bookDir, 'tmp'), { recursive: true });

    // Extract stepbook.db
    fs.writeFileSync(path.join(bookDir, 'stepbook.db'), dbEntry.getData());

    // Extract image files (only from images/ directory, with validation)
    const entries = zip.getEntries();
    for (const entry of entries) {
      if (entry.isDirectory) continue;
      const entryName = entry.entryName;

      // Only extract files under images/
      if (!entryName.startsWith('images/')) continue;

      // Path traversal guard
      const normalized = path.normalize(entryName);
      if (normalized.includes('..') || path.isAbsolute(normalized)) {
        cleanupBook();
        cleanup();
        return res.status(400).json({ error: 'Path traversal detected in zip' });
      }

      // Validate image extension
      if (!ALLOWED_IMAGE_EXTS.test(entryName)) continue;

      // Resolve destination and verify it's within book directory
      const destPath = path.join(bookDir, normalized);
      if (!path.resolve(destPath).startsWith(path.resolve(bookDir))) {
        cleanupBook();
        cleanup();
        return res.status(400).json({ error: 'Path traversal detected' });
      }

      // Ensure parent directory exists (for nested image dirs like images/<seqId>/)
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.writeFileSync(destPath, entry.getData());
    }

    // Register the new book
    const bookName = manifest.book.name;
    const newBook = { id: bookId, name: bookName, path: `./${bookId}` };
    const allBooks = books.listBooks();
    allBooks.push(newBook);
    books.writeRegistry(allBooks);

    cleanup();
    res.status(201).json(newBook);
  } catch (err) {
    cleanupBook();
    cleanup();
    console.error('Book import error:', err);
    res.status(500).json({ error: 'Failed to import book' });
  }
});

module.exports = router;
