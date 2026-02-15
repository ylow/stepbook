const { app, BrowserWindow } = require('electron');
const path = require('path');

// Set data directory to ~/Documents/Stepbook before anything else loads
const documentsDir = app.getPath('documents');
const dataDir = path.join(documentsDir, 'Stepbook');
process.env.STEPBOOK_DATA_DIR = dataDir;

const { startServer } = require('../server/index');

let mainWindow;
let server;

async function createWindow() {
  const result = await startServer(0);
  server = result.server;

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    title: 'Stepbook',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  mainWindow.loadURL(`http://localhost:${result.port}`);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (server) {
    server.close();
  }
  app.quit();
});

app.on('activate', () => {
  if (mainWindow === null) {
    createWindow();
  }
});
