const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

let rootDir = null;
let registryPath = null;

function init(dir) {
  rootDir = dir;
  registryPath = path.join(rootDir, 'books.json');

  // Migrate legacy layout: if stepbook.db exists at root level, move into default/
  const legacyDb = path.join(rootDir, 'stepbook.db');
  if (fs.existsSync(legacyDb) && !fs.existsSync(registryPath)) {
    const defaultDir = path.join(rootDir, 'default');
    fs.mkdirSync(defaultDir, { recursive: true });

    // Move database files
    for (const ext of ['', '-wal', '-shm']) {
      const src = path.join(rootDir, `stepbook.db${ext}`);
      if (fs.existsSync(src)) {
        fs.renameSync(src, path.join(defaultDir, `stepbook.db${ext}`));
      }
    }

    // Move images/ and tmp/ directories
    for (const dir of ['images', 'tmp']) {
      const src = path.join(rootDir, dir);
      const dest = path.join(defaultDir, dir);
      if (fs.existsSync(src)) {
        fs.renameSync(src, dest);
      }
    }
  }

  // Create registry if it doesn't exist
  if (!fs.existsSync(registryPath)) {
    const defaultBooks = [
      { id: 'default', name: 'Default', path: './default' }
    ];
    fs.writeFileSync(registryPath, JSON.stringify(defaultBooks, null, 2));
  }
}

function readRegistry() {
  return JSON.parse(fs.readFileSync(registryPath, 'utf8'));
}

function writeRegistry(books) {
  fs.writeFileSync(registryPath, JSON.stringify(books, null, 2));
}

function resolveBookPath(book) {
  if (path.isAbsolute(book.path)) return book.path;
  return path.resolve(rootDir, book.path);
}

function listBooks() {
  return readRegistry();
}

function getBook(id) {
  const books = readRegistry();
  return books.find(b => b.id === id) || null;
}

function createBook(name) {
  const books = readRegistry();
  const id = uuidv4();
  const bookDir = path.join(rootDir, id);
  fs.mkdirSync(bookDir, { recursive: true });
  fs.mkdirSync(path.join(bookDir, 'images'), { recursive: true });
  fs.mkdirSync(path.join(bookDir, 'tmp'), { recursive: true });
  const book = { id, name, path: `./${id}` };
  books.push(book);
  writeRegistry(books);
  return book;
}

function addBook(name, bookPath) {
  const books = readRegistry();
  const id = uuidv4();
  // Store relative path if inside rootDir, otherwise absolute
  const resolved = path.resolve(bookPath);
  const relative = path.relative(rootDir, resolved);
  const storedPath = relative.startsWith('..') ? resolved : `./${relative}`;
  const book = { id, name, path: storedPath };
  books.push(book);
  writeRegistry(books);
  return book;
}

function updateBook(id, name) {
  const books = readRegistry();
  const book = books.find(b => b.id === id);
  if (!book) return null;
  book.name = name;
  writeRegistry(books);
  return book;
}

function removeBook(id) {
  if (id === 'default') return false;
  const books = readRegistry();
  const idx = books.findIndex(b => b.id === id);
  if (idx === -1) return false;
  books.splice(idx, 1);
  writeRegistry(books);
  return true;
}

module.exports = { init, listBooks, getBook, createBook, addBook, updateBook, removeBook, resolveBookPath, writeRegistry };
