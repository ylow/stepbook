const path = require('path');
const fs = require('fs');

const ROOT_DIR = process.env.STEPBOOK_DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(ROOT_DIR, { recursive: true });

module.exports = { ROOT_DIR };
