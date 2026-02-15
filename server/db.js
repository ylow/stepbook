const Database = require('better-sqlite3');
const path = require('path');
const { DATA_DIR } = require('./config');

const DB_PATH = path.join(DATA_DIR, 'stepbook.db');

const db = new Database(DB_PATH);

// Enable WAL mode for better performance
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// Create tables
db.exec(`
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

module.exports = db;
