// snapshot.mjs — offscreen body render for the Windows port, the counterpart
// of the macOS build's `--snapshot` flag. Renders a posed body to a PNG so
// the three.js scene graph can be inspected (and regression-checked) without
// running the live overlay.
//
//   electron tools/snapshot.mjs --out=roach.png
//   electron tools/snapshot.mjs --form=fly --pose=walking --out=fly-walk.png
//   electron tools/snapshot.mjs --form=roach --pose=carry --top --out=carry-top.png
//
// Poses: idle (default), walking, flying, carry (an ootheca-bearing female).

import { app, BrowserWindow, ipcMain } from 'electron';
// Offscreen painting drops the GPU-composited WebGL layer on some drivers,
// and software rendering cannot create a WebGL context at all — so the
// renderer runs in a real (screen-off) window and capturePage() snapshots it.
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

function arg(name, fallback = null) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
}
const flag = (name) => process.argv.some((a) =>
  a === `--${name}` || a.startsWith(`--${name}=`));

const form = arg('form', 'roach');
const pose = arg('pose', 'idle');
const out = arg('out', `snapshot-${form}-${pose}.png`);
const width = Number(arg('width', '720'));
const height = Number(arg('height', '720'));

const FORMS = ['fly', 'roach'];
const POSES = ['idle', 'walking', 'flying', 'carry'];

let win = null;
let captured = false;

app.whenReady().then(() => {
  if (!FORMS.includes(form) || !POSES.includes(pose)) {
    process.stderr.write(`unknown form/pose: ${form} / ${pose}\n`);
    app.exit(1);
    return;
  }
  const query = new URLSearchParams({
    form, pose,
    top: flag('top') ? '1' : '',
    flat: flag('flat') ? '1' : '',
    hide: arg('hide', ''),
    only: arg('only', ''),
    noshadow: flag('noshadow') ? '1' : '',
    pure: flag('pure') ? '1' : '',
    tri: flag('tri') ? '1' : '',
    tric: flag('tric') ? '1' : '',
    probe: flag('probe') ? '1' : '',
  });
  win = new BrowserWindow({
    show: true,
    x: -40000,   // far off screen: rendered, never seen
    y: 0,
    width,
    height,
    webPreferences: {
      preload: path.join(HERE, 'snapshot-preload.mjs'),
      backgroundThrottling: false,
      sandbox: false,
    },
  });
  win.webContents.on('console-message', (_e, level, message) => {
    if (level >= 2 || process.env.DESKTOPFLY_DEBUG) {
      process.stderr.write(`[snapshot] ${message}\n`);
    }
  });
  win.loadURL(pathToFileURL(path.join(HERE, 'snapshot.html')).href + '?' + query.toString());
});

// A renderer error must not hang the tool: bail out after 20 s regardless.
setTimeout(() => {
  if (!captured) {
    process.stderr.write('snapshot timed out\n');
    app.exit(1);
  }
}, 20000);

// The renderer ships its own canvas pixels: offscreen painting drops the
// GPU-composited WebGL layer and capturePage returns the page without it.
ipcMain.on('snapshot-ready', (_e, dataUrl) => {
  if (captured || !dataUrl) return;
  captured = true;
  fs.writeFileSync(out, Buffer.from(dataUrl.split(',')[1], 'base64'));
  process.stdout.write(`wrote ${out}\n`);
  app.quit();
});
