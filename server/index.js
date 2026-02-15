const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3001;

// In production, serve the built Vue app's static assets FIRST
const clientDist = path.join(__dirname, '..', 'client', 'dist');
const hasClientDist = fs.existsSync(clientDist);
if (hasClientDist) {
  app.use(express.static(clientDist));
}

app.use(cors());
app.use(express.json());

// Serve uploaded images
app.use('/images', express.static(path.join(__dirname, '..', 'data', 'images')));

// API routes
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

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
