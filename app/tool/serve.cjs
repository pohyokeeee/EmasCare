const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const types = { '.html':'text/html; charset=utf-8', '.js':'application/javascript', '.mjs':'application/javascript', '.json':'application/json', '.wasm':'application/wasm', '.svg':'image/svg+xml', '.png':'image/png', '.ico':'image/x-icon', '.ttf':'font/ttf', '.woff2':'font/woff2' };
function createPreviewServer(root = path.resolve(__dirname, '../build/web')) {
if (!fs.existsSync(path.join(root, 'index.html'))) throw new Error('Build the web app first: .\\preview.ps1 -Mode build');
return http.createServer((req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (pathname === '/__emascare/health') {
      res.writeHead(200, {'Content-Type':'application/json','Cache-Control':'no-store'});
      const app = path.resolve(__dirname,'..').replaceAll('\\','/').toLowerCase();
      res.end(JSON.stringify({project:'demo-emascare',workspace:crypto.createHash('sha256').update(app).digest('hex')}));
      return;
    }
    let file = path.resolve(root, '.' + pathname);
    if (file !== root && !file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    if (!fs.existsSync(file)) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control':'no-store' });
    fs.createReadStream(file).pipe(res);
  } catch (_) { res.writeHead(400); res.end('Bad request'); }
});
}
module.exports = {createPreviewServer};
if (require.main === module) {
  const port = Number(process.argv[2] || 8090);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Use a port between 1024 and 65535.');
  createPreviewServer().listen(port, '127.0.0.1', () => console.log(`EmasCare preview: http://127.0.0.1:${port} (Ctrl+C to stop)`)).on('error', (e) => { console.error(e.message); process.exitCode=1; });
}
