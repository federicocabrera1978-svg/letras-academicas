// Servidor de pruebas: sirve el repo, reescribe la URL de Supabase y hace de proxy a PostgREST local.
const http = require('http'), fs = require('fs'), path = require('path'), jwt = require('jsonwebtoken');
const ROOT = process.env.ROOT || require('path').resolve(__dirname, '../..');
const PORT = +process.env.PORT || 8080, PGRST = +process.env.PGRST || 3000;
const SECRET = 'e2e-secret-e2e-secret-e2e-secret-0123456789';
const vercel = JSON.parse(fs.readFileSync(path.join(ROOT, 'vercel.json')));
const hdrs = vercel.headers[0].headers;
let csp = hdrs.find(h => h.key === 'Content-Security-Policy').value
  .replace(/https:\/\/xjrdjesezseuofjoqpzn\.supabase\.co/g, `http://localhost:${PORT}`)
  .replace(/wss:\/\/xjrdjesezseuofjoqpzn\.supabase\.co/g, `ws://localhost:${PORT}`)
  .replace('; upgrade-insecure-requests', '');
const types = { '.html':'text/html; charset=utf-8', '.js':'text/javascript', '.css':'text/css', '.svg':'image/svg+xml', '.json':'application/json' };
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname.startsWith('/rest/v1/')) {
    const opts = { host:'127.0.0.1', port:PGRST, path:u.pathname.slice(8) + u.search, method:req.method, headers:{ ...req.headers, host:`127.0.0.1:${PGRST}` } };
    const auth = req.headers['authorization'] || '';
    // la publishable key no es JWT: sin token de usuario = anon
    if (!/^Bearer ey/.test(auth)) delete opts.headers['authorization'];
    delete opts.headers['apikey'];
    const p = http.request(opts, r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
    p.on('error', e => { res.writeHead(502); res.end(String(e)); });
    req.pipe(p); return;
  }
  if (u.pathname.startsWith('/auth/v1/')) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    if (u.pathname === '/auth/v1/user') {
      try { const c = jwt.verify((req.headers.authorization||'').slice(7), SECRET); res.writeHead(200, {'content-type':'application/json'}); return res.end(JSON.stringify({ id:c.sub, email:c.email, aud:'authenticated', role:'authenticated', user_metadata:c.user_metadata||{} })); }
      catch { res.writeHead(401); return res.end('{}'); }
    }
    res.writeHead(204); return res.end();
  }
  let f = path.join(ROOT, decodeURIComponent(u.pathname === '/' ? '/index.html' : u.pathname));
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('404'); }
  let body = fs.readFileSync(f);
  if (f.endsWith('/index.js')) body = Buffer.from(body.toString().replace("'https://xjrdjesezseuofjoqpzn.supabase.co'", `'http://localhost:${PORT}'`));
  const h = { 'content-type': types[path.extname(f)] || 'application/octet-stream', 'cache-control':'no-store' };
  for (const x of hdrs) if (x.key !== 'Strict-Transport-Security') h[x.key] = x.key === 'Content-Security-Policy' ? csp : x.value;
  res.writeHead(200, h); res.end(body);
}).listen(PORT, () => console.log('e2e server on', PORT, '-> pgrst', PGRST));
