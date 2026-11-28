/**
 * Serveur de vérification jetable pour l'app Flutter compilée en web.
 *
 * Sert build/web ET relaie /api vers le backend :3000. Tout est donc sur la
 * même origine — ni CORS, ni websocket de débogage (le serveur de dev Flutter
 * en dépend et il échoue dans le volet navigateur).
 *
 *   flutter build web --debug --dart-define=API_BASE_URL=http://localhost:4300/api/v1
 *   node _web_preview.js
 */
const http = require('http');
const fs   = require('fs');
const path = require('path');

const RACINE = path.join(__dirname, 'build', 'web');
const TYPES  = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.css': 'text/css', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2', '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  if (url.startsWith('/api')) {
    const amont = http.request(
      { host: 'localhost', port: 3000, path: req.url, method: req.method,
        headers: { ...req.headers, host: 'localhost:3000' } },
      r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); },
    );
    amont.on('error', e => { res.writeHead(502); res.end(JSON.stringify({ error: e.message })); });
    return req.pipe(amont);
  }

  // Empêche de sortir de build/web via ../
  const rel = path.normalize(url === '/' ? '/index.html' : url).replace(/^(\.\.[/\\])+/, '');
  const f   = path.join(RACINE, rel);
  if (!f.startsWith(RACINE)) { res.writeHead(403); return res.end('interdit'); }

  fs.readFile(f, (err, data) => {
    if (err) { res.writeHead(404); return res.end('introuvable'); }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream',
      'Cache-Control': 'no-store',   // toujours relire après un rebuild
    });
    res.end(data);
  });
}).listen(4300, () => console.log('aperçu web : http://localhost:4300  (+ /api -> :3000)'));
