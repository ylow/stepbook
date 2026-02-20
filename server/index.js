const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { ROOT_DIR } = require('./config');
const books = require('./books');
const bookContext = require('./book-context');

function createApp() {
  // Initialize books registry and book context
  books.init(ROOT_DIR);
  bookContext.init(ROOT_DIR);

  // Auto-select the default book
  const defaultBook = books.getBook('default');
  if (defaultBook) {
    bookContext.switchBook(defaultBook.id, books.resolveBookPath(defaultBook));
  }

  const app = express();

  // In production, serve the built Vue app's static assets FIRST
  const clientDist = path.join(__dirname, '..', 'client', 'dist');
  const hasClientDist = fs.existsSync(clientDist);
  if (hasClientDist) {
    // Service worker files must never be cached — browser needs to fetch
    // fresh on every check to detect updates promptly after deploys.
    app.get(/^\/(sw|workbox-.*?)\.js$/, (req, res, next) => {
      res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      next();
    });
    app.use(express.static(clientDist));
  }

  app.use(cors());
  app.use(express.json({ limit: '10mb' }));

  // Config endpoint — tells the frontend where data is stored
  app.get('/api/config', (req, res) => {
    res.json({ rootDir: ROOT_DIR, dataDir: bookContext.getDataDir() });
  });

  // Serve uploaded images dynamically from the active book's images dir
  app.use('/images', (req, res, next) => {
    express.static(bookContext.getImagesDir())(req, res, next);
  });

  // API routes
  app.use('/api/books', require('./routes/books'));
  app.use('/api/sequences', require('./routes/sequences'));
  app.use('/api/sequences', require('./routes/steps'));
  app.use('/api', require('./routes/steps'));
  app.use('/api/sequences', require('./routes/transfer'));

  // SPA fallback: serve index.html for any non-API GET route
  if (hasClientDist) {
    app.use((req, res, next) => {
      if (req.method === 'GET' && !req.path.startsWith('/api/') && !req.path.startsWith('/images/')) {
        res.sendFile(path.join(clientDist, 'index.html'));
      } else {
        next();
      }
    });
  }

  return app;
}

function startServer(port = 0) {
  return new Promise((resolve, reject) => {
    const app = createApp();
    const server = app.listen(port, () => {
      const actualPort = server.address().port;
      console.log(`Server running on http://localhost:${actualPort}`);
      resolve({ app, server, port: actualPort });
    });
    server.on('error', reject);
  });
}

// If run directly (not imported), start on the configured port
if (require.main === module) {
  const PORT = process.env.PORT || 3001;
  startServer(PORT);
}

module.exports = { createApp, startServer };
