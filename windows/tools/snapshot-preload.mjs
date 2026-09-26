// snapshot-preload.mjs — the single bridge the snapshot page needs: telling
// the main process the scene has rendered its first frame.

import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('snapshotAPI', {
  ready: (dataUrl) => ipcRenderer.send('snapshot-ready', dataUrl),
});
