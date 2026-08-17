const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dangle', {
  getSettings: () => ipcRenderer.invoke('get-settings'),
  onSettings: (fn) => ipcRenderer.on('settings', (_e, s) => fn(s)),
  onCursor: (fn) => ipcRenderer.on('cursor', (_e, p) => fn(p)),
  onDrop: (fn) => ipcRenderer.on('drop', () => fn()),
  setHit: (hit) => ipcRenderer.send('hit', hit),
});
