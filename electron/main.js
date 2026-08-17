//
//  Lucky Dangle — Electron main process.
//  Owns the transparent overlay window, the tray menu, and the global hotkey.
//

const { app, BrowserWindow, Tray, Menu, screen, globalShortcut, ipcMain } =
  require('electron');
const path = require('path');
const fs = require('fs');

const WIDTH = 980;
const HEIGHT = 630;                 // dropLength + 230, as in the Swift version
const IS_MAC = process.platform === 'darwin';

// ── settings ────────────────────────────────────────────────

const SETTINGS_FILE = path.join(app.getPath('userData'), 'settings.json');
const settings = { charm: 'nazar', sizeScale: 1.0, shimmer: true, xFraction: 0.86 };
try {
  Object.assign(settings, JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')));
} catch { /* first run, or unreadable — defaults are fine */ }

function saveSettings() {
  try {
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2));
  } catch (e) {
    console.error('could not save settings:', e.message);
  }
}

// ── window ──────────────────────────────────────────────────

let win = null;
let tray = null;
let cursorTimer = null;

function place() {
  if (!win) return;
  const b = screen.getPrimaryDisplay().bounds;
  const x = Math.round(
    Math.min(Math.max(b.x + settings.xFraction * b.width - WIDTH / 2, b.x),
             b.x + b.width - WIDTH));
  win.setPosition(x, b.y, false);
}

function createWindow() {
  win = new BrowserWindow({
    width: WIDTH,
    height: HEIGHT,
    transparent: true,
    frame: false,
    resizable: false,
    movable: false,
    focusable: false,
    skipTaskbar: true,
    hasShadow: false,
    alwaysOnTop: true,
    fullscreenable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // above normal windows, and present on every desktop
  win.setAlwaysOnTop(true, 'screen-saver');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });

  // click-through by default; `forward: true` still delivers move events so the
  // renderer can tell us when the pointer is actually on the charm
  win.setIgnoreMouseEvents(true, { forward: true });

  win.loadFile(path.join(__dirname, 'index.html'));
  win.once('ready-to-show', () => {
    place();
    win.showInactive();
  });

  // The charm reacts to the pointer anywhere on screen, which the renderer
  // cannot see while click-through. Feed it cursor positions from here.
  cursorTimer = setInterval(() => {
    if (!win || win.isDestroyed()) return;
    const p = screen.getCursorScreenPoint();
    const b = win.getBounds();
    win.webContents.send('cursor', { x: p.x - b.x, y: p.y - b.y });
  }, 16);

  screen.on('display-metrics-changed', place);
  screen.on('display-added', place);
  screen.on('display-removed', place);
}

// ── tray menu ───────────────────────────────────────────────

const CHARM_TITLES = {
  nazar: 'Nazar — evil eye (Türkiye)',
  clover: 'Four-leaf clover (Ireland)',
  horseshoe: 'Horseshoe (Europe)',
  knot: 'Lucky knot (China)',
  dog: 'Lucky dog — faithful guardian',
};

const SIZES = [['Small', 0.75], ['Medium', 1.0], ['Large', 1.3], ['Huge', 1.6]];
const PLACES = [['Left', 0.14], ['Centre', 0.5], ['Right', 0.86]];

function push(key, value) {
  settings[key] = value;
  saveSettings();
  if (win && !win.isDestroyed()) win.webContents.send('settings', settings);
}

function buildMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: 'Charm',
      submenu: Object.entries(CHARM_TITLES).map(([key, label]) => ({
        label,
        type: 'radio',
        checked: settings.charm === key,
        click: () => push('charm', key),
      })),
    },
    {
      label: 'Size',
      submenu: SIZES.map(([label, scale]) => ({
        label,
        type: 'radio',
        checked: Math.abs(settings.sizeScale - scale) < 0.01,
        click: () => push('sizeScale', scale),
      })),
    },
    {
      label: 'Hang it',
      submenu: PLACES.map(([label, frac]) => ({
        label,
        type: 'radio',
        checked: Math.abs(settings.xFraction - frac) < 0.01,
        click: () => { push('xFraction', frac); place(); },
      })),
    },
    { type: 'separator' },
    {
      label: 'Shimmer',
      type: 'checkbox',
      checked: settings.shimmer,
      click: (item) => push('shimmer', item.checked),
    },
    {
      label: 'Drop the charm',
      accelerator: IS_MAC ? 'Alt+Command+L' : 'Alt+Control+L',
      click: () => win && win.webContents.send('drop'),
    },
    { type: 'separator' },
    { label: 'Quit Lucky Dangle', role: 'quit' },
  ]);
  tray.setContextMenu(menu);
}

function createTray() {
  tray = new Tray(path.join(__dirname, 'tray.png'));
  tray.setToolTip('Lucky Dangle');
  buildMenu();
  // Windows: left-clicking the tray icon should also open the menu
  tray.on('click', () => tray.popUpContextMenu());
}

// ── lifecycle ───────────────────────────────────────────────

// The overlay is decorative; a second copy would just draw on top of the first.
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.whenReady().then(() => {
    if (IS_MAC && app.dock) app.dock.hide();

    createWindow();
    createTray();

    const accel = IS_MAC ? 'Alt+Command+L' : 'Alt+Control+L';
    if (!globalShortcut.register(accel, () => {
      if (win && !win.isDestroyed()) win.webContents.send('drop');
    })) {
      console.error(`could not register ${accel} — another app likely owns it`);
    }

    // The renderer pulls settings once it is ready. Pushing them on
    // 'ready-to-show' raced the module script and could arrive before the
    // listener existed.
    ipcMain.handle('get-settings', () => settings);

    // renderer tells us when the pointer is over the charm, so clicks land on it
    // and pass straight through everywhere else
    ipcMain.on('hit', (_e, hit) => {
      if (!win || win.isDestroyed()) return;
      win.setIgnoreMouseEvents(!hit, { forward: true });
    });

    ipcMain.on('menu-changed', buildMenu);
  });
}

app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  if (cursorTimer) clearInterval(cursorTimer);
});
