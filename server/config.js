const path = require('path');
const fs = require('fs');

const DATA_DIR = process.env.STEPBOOK_DATA_DIR || path.join(__dirname, '..', 'data');
const IMAGES_DIR = path.join(DATA_DIR, 'images');
const TMP_DIR = path.join(DATA_DIR, 'tmp');

// Ensure directories exist
fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(IMAGES_DIR, { recursive: true });

module.exports = { DATA_DIR, IMAGES_DIR, TMP_DIR };
