// Render an animation page frame-by-frame with headless Chrome (CDP, no dependencies).
// usage: node capture.mjs <page.html> <light|dark> <outDir> <width> <height> <fps> <scale>
// The page must expose window.READY, window.LOOP (seconds) and window.renderAt(t).
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [page, theme, outDir, W, H, FPS, SCALE] = process.argv.slice(2);
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9300 + Math.floor(Math.random() * 500);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

mkdirSync(outDir, { recursive: true });
const profile = mkdtempSync(join(process.env.TMPDIR || tmpdir(), 'cdp-'));
const chrome = spawn(CHROME, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-color-profile=srgb',
    `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, 'about:blank',
], { stdio: 'ignore' });

try {
    let wsUrl;
    for (let i = 0; i < 100 && !wsUrl; i++) {
        try {
            const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
            wsUrl = list.find((t) => t.type === 'page')?.webSocketDebuggerUrl;
        } catch { /* not up yet */ }
        if (!wsUrl) await sleep(150);
    }
    if (!wsUrl) throw new Error('Chrome DevTools endpoint did not come up');

    const ws = new WebSocket(wsUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    let seq = 0;
    const pending = new Map();
    ws.onmessage = (e) => {
        const m = JSON.parse(e.data);
        if (!m.id || !pending.has(m.id)) return;
        const { res, rej } = pending.get(m.id);
        pending.delete(m.id);
        m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
    };
    const send = (method, params = {}) => new Promise((res, rej) => {
        const id = ++seq;
        pending.set(id, { res, rej });
        ws.send(JSON.stringify({ id, method, params }));
    });
    const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true })).result.value;

    await send('Page.enable');
    await send('Emulation.setDeviceMetricsOverride', { width: +W, height: +H, deviceScaleFactor: +SCALE, mobile: false });
    await send('Page.navigate', { url: `${pathToFileURL(resolve(page)).href}?theme=${theme}` });

    for (let i = 0; i < 150; i++) {
        if (await evaluate('window.READY === true').catch(() => false)) break;
        if (i === 149) throw new Error('page never became READY (fonts?)');
        await sleep(200);
    }

    const loop = await evaluate('window.LOOP');
    const frames = Math.round(loop * FPS);
    for (let f = 0; f < frames; f++) {
        await evaluate(`renderAt(${f / FPS})`);
        const shot = await send('Page.captureScreenshot', {
            format: 'png', clip: { x: 0, y: 0, width: +W, height: +H, scale: 1 },
        });
        writeFileSync(join(outDir, `${String(f).padStart(4, '0')}.png`), Buffer.from(shot.data, 'base64'));
    }
    console.log(`${page} [${theme}]: ${frames} frames (${loop}s @ ${FPS}fps) -> ${outDir}`);
    ws.close();
} finally {
    chrome.kill();
}
