const express = require('express');
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

module.exports = router;
