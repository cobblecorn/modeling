// Headless render of every weapon in out/weapons.json -> out/<Name>.png
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const root = path.dirname(new URL(import.meta.url).pathname);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, r));
const port = server.address().port;

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
page.on('console', m => { if (m.type() === 'error') console.error('page:', m.text()); });
page.on('pageerror', e => console.error('page error:', e.message));
await page.goto(`http://localhost:${port}/render.html`);
await page.waitForFunction('window.ready === true', null, { timeout: 60000 });
const names = await page.evaluate('window.weaponNames');
const only = process.argv[2];
for (let i = 0; i < names.length; i++) {
  if (only && names[i] !== only) continue;
  await page.evaluate(i => window.renderWeapon(i), i);
  const out = path.join(root, 'out', `${names[i]}.png`);
  await page.locator('canvas').screenshot({ path: out });
  console.log('rendered', out);
}
if (!only) {
  for (let i = 0; i < names.length; i++) {
    await page.evaluate(i => window.renderIcon(i), i);
    const out = path.join(root, 'out', `icon_${names[i]}.png`);
    await page.screenshot({ path: out, clip: { x: 0, y: 0, width: 512, height: 512 }, omitBackground: true });
    console.log('rendered', out);
  }
  await page.evaluate(() => window.resetBackground());
  await page.evaluate(() => window.renderLineup());
  await page.screenshot({ path: path.join(root, 'out', 'lineup.png'), clip: { x: 0, y: 0, width: 1600, height: 560 } });
  console.log('rendered lineup');
}
await browser.close();
server.close();
