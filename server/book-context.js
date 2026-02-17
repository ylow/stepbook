const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

let rootDir = null;
let currentDb = null;
let currentDataDir = null;
let currentImagesDir = null;
let currentTmpDir = null;
let currentBookId = null;

function init(dir) {
  rootDir = dir;
}

function switchBook(bookId, bookPath) {
  // Close existing DB if open
  if (currentDb) {
    try { currentDb.close(); } catch (e) { /* ignore */ }
    currentDb = null;
  }

  currentBookId = bookId;
  currentDataDir = bookPath;
  currentImagesDir = path.join(bookPath, 'images');
  currentTmpDir = path.join(bookPath, 'tmp');

  // Ensure directories exist
  fs.mkdirSync(currentDataDir, { recursive: true });
  fs.mkdirSync(currentImagesDir, { recursive: true });
  fs.mkdirSync(currentTmpDir, { recursive: true });

  // Open database
  const dbPath = path.join(bookPath, 'stepbook.db');
  currentDb = new Database(dbPath);
  currentDb.pragma('journal_mode = WAL');
  currentDb.pragma('foreign_keys = ON');

  // Create tables if needed
  currentDb.exec(`
    CREATE TABLE IF NOT EXISTS sequences (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS steps (
      id TEXT PRIMARY KEY,
      sequence_id TEXT NOT NULL,
      order_index INTEGER NOT NULL,
      image_path TEXT NOT NULL,
      annotations TEXT DEFAULT '{}',
      notes TEXT DEFAULT '',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (sequence_id) REFERENCES sequences(id) ON DELETE CASCADE
    );
  `);
}

function getDb() {
  if (!currentDb) throw new Error('No book selected');
  return currentDb;
}

function getImagesDir() {
  if (!currentImagesDir) throw new Error('No book selected');
  return currentImagesDir;
}

function getTmpDir() {
  if (!currentTmpDir) throw new Error('No book selected');
  return currentTmpDir;
}

function getDataDir() {
  if (!currentDataDir) throw new Error('No book selected');
  return currentDataDir;
}

function getRootDir() {
  return rootDir;
}

function getCurrentBookId() {
  return currentBookId;
}

module.exports = { init, switchBook, getDb, getImagesDir, getTmpDir, getDataDir, getRootDir, getCurrentBookId };
