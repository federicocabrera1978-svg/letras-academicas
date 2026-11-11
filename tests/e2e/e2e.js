// E2E de la UI contra PostgREST local (BASE=http://localhost:8080 migrada, :8081 esquema viejo)
const { chromium } = require('playwright-core');
const jwt = require('jsonwebtoken');
const BASE = process.env.BASE || 'http://localhost:8080';
const MIGRADA = BASE.endsWith('8080');
const SECRET = 'e2e-secret-e2e-secret-e2e-secret-0123456789';
const U = {
  admin: { id:'00000000-0000-0000-0000-00000000000a', email:'federico.admin@gmail.com', name:'Federico' },
  ana:   { id:'00000000-0000-0000-0000-000000000001', email:'ana.alumna@gmail.com', name:'Ana' },
  beto:  { id:'00000000-0000-0000-0000-000000000002', email:'beto.alumno@gmail.com', name:'Beto' },
  carla: { id:'00000000-0000-0000-0000-000000000003', email:'carla.profe@gmail.com', name:'Carla' },
  dani:  { id:'00000000-0000-0000-0000-000000000004', email:'dani.otro@gmail.com', name:'Dani' },
  nuevo: { id:'00000000-0000-0000-0000-000000000005', email:'ana-alumna@hotmail.com', name:'Ana Nueva' },
};
let fallas = 0, oks = 0;
const ok = (c, m) => { if (c) { oks++; console.log('  ok:', m); } else { fallas++; console.log('  FAIL:', m); } };

function sesion(u) {
  const now = Math.floor(Date.now()/1000);
  const user_metadata = { full_name: u.name, avatar_url: 'https://lh3.googleusercontent.com/a/test-' + u.id.slice(-2) };
  const access_token = jwt.sign({ sub:u.id, role:'authenticated', aud:'authenticated', email:u.email, user_metadata, exp: now + 3600 }, SECRET);
  return { access_token, token_type:'bearer', expires_in:3600, expires_at: now + 3600, refresh_token:'fake',
    user: { id:u.id, aud:'authenticated', role:'authenticated', email:u.email, user_metadata, app_metadata:{ provider:'google' } } };
}

async function abrir(browser, u) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const errores = [];
  page.on('pageerror', e => errores.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errores.push('console: ' + m.text()); });
  page.on('dialog', d => { page._dialogs = (page._dialogs||[]).concat(d.message()); d.accept(); });
  await page.addInitScript(([s]) => {
    window.__csp = [];
    document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));
    if (s && !sessionStorage.getItem('__set')) { localStorage.setItem('letras-academicas-auth', JSON.stringify(s)); sessionStorage.setItem('__set', '1'); }
  }, [u ? sesion(u) : null]);
  await page.goto(BASE + '/');
  return { ctx, page, errores };
}
const csp = page => page.evaluate(() => window.__csp);
// fallos de red de avatares externos (sin internet) no cuentan
const errReales = e => e.filter(x => !/googleusercontent|ui-avatars|ERR_|Failed to load resource/.test(x));
const nav = async (page, p) => { await page.click(`.nav-item[data-page="${p}"]`); await page.waitForTimeout(300); };

(async () => {
  const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  console.log(`== Base: ${BASE} (${MIGRADA ? 'con migraciones' : 'esquema actual de prod, sin migrar'})`);

  console.log('-- anon: home pública');
  { const { ctx, page, errores } = await abrir(browser, null);
    await page.waitForSelector('#landing-textos .lp-card', { timeout: 5000 }).catch(() => {});
    ok(await page.locator('#landing-textos .lp-card').count() >= 1, 'destacados visibles sin login');
    ok(await page.isVisible('#login-google-btn img'), 'logo de Google local');
    ok((await csp(page)).length === 0, 'sin violaciones de CSP: ' + JSON.stringify(await csp(page)));
    ok(errReales(errores).length === 0, 'sin errores JS: ' + JSON.stringify(errReales(errores)));
    await ctx.close(); }

  console.log('-- Ana (alumna de GENERAL)');
  { const { ctx, page, errores } = await abrir(browser, U.ana);
    await page.waitForSelector('#main-layout:not(.hidden)', { timeout: 8000 });
    ok(await page.isVisible('text=Bienvenido/a, Ana'), 'dashboard carga');
    await nav(page, 'textos');
    const titulos = await page.locator('#textos-list .card h2').allTextContents();
    ok(titulos.includes('Texto Ana') && titulos.includes('Texto Beto destacado'), 've textos de su curso: ' + titulos.join(' | '));
    if (MIGRADA) ok(!titulos.includes('Texto Dani (otro curso)'), 'NO ve textos de otro curso');
    // teclado: Enter sobre una tarjeta
    await page.focus('#textos-list .card >> nth=0'); await page.keyboard.press('Enter'); await page.waitForTimeout(400);
    ok(await page.isVisible('text=Devoluciones'), 'tarjeta se abre con Enter');
    await nav(page, 'textos');
    await page.click('#textos-list .card:has-text("Texto Beto destacado")'); await page.waitForTimeout(400);
    ok(!(await page.isVisible('[data-action="edit"]')), 'no puede editar texto ajeno');
    ok(!(await page.isVisible('[data-action="destacar"]')), 'alumna no ve Destacar');
    await page.click('[data-action="like"]'); await page.waitForTimeout(500);
    ok((await page.textContent('[data-action="like"]')).includes('Ya no me gusta (1)'), 'like suma');
    await page.click('[data-action="like"]'); await page.waitForTimeout(500);
    ok((await page.textContent('[data-action="like"]')).includes('Me gusta (0)'), 'unlike real resta');
    await page.fill('#com-body', 'Muy bueno'); await page.click('[data-action="comment"]'); await page.waitForTimeout(500);
    ok(await page.isVisible('text=Muy bueno'), 'comentario publicado');
    await nav(page, 'nuevo');
    await page.fill('#f-title', 'Nuevo de Ana'); await page.click('.ql-editor'); await page.keyboard.type('Cuerpo del texto.');
    await page.evaluate(() => guardarBorrador());
    const claves = await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('borrador')));
    ok(claves.length === 1 && claves[0] === "borrador:" + U.ana.id + ":nuevo", "borrador con clave por usuario+modo: " + claves.join(","));
    await page.click('#btn-pub'); await page.waitForTimeout(700);
    ok((await page.locator('.card h2').allTextContents()).includes('Nuevo de Ana'), 'publica y aparece en Mis textos');
    ok((await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('borrador')).length)) === 0, 'borrador se limpia al publicar');
    await page.click('.card:has-text("Nuevo de Ana")'); await page.waitForTimeout(400);
    ok(await page.isVisible('[data-action="edit"]') && await page.isVisible('[data-action="delete"]'), 'autora ve Editar/Eliminar');
    await page.click('[data-action="edit"]'); await page.waitForTimeout(300);
    await page.fill('#f-title', 'Nuevo de Ana (editado)'); await page.click('#btn-pub'); await page.waitForTimeout(700);
    ok((await page.locator('.card h2').allTextContents()).includes('Nuevo de Ana (editado)'), 'edición guardada');
    await page.click('.card:has-text("Nuevo de Ana (editado)")'); await page.waitForTimeout(400);
    await page.click('[data-action="delete"]'); await page.waitForTimeout(700);
    ok(!(await page.locator('.card h2').allTextContents()).includes('Nuevo de Ana (editado)'), 'borrado con un solo DELETE');
    await nav(page, 'miembros');
    ok(await page.locator('[data-action="eliminar-miembro"]').count() === 0, 'alumna no ve Eliminar miembro');
    if (MIGRADA) ok(!(await page.isVisible('text=@danierotro')), 'no ve perfiles de otro curso');
    ok(await page.locator('nav.sidebar button.nav-item[aria-current="page"]').count() === 1, 'menú con <button> y aria-current');
    ok(await page.getAttribute('#theme-toggle', 'aria-label') === 'Modo oscuro', '🌓 con aria-label');
    ok(await page.locator('img:not([alt])').count() === 0, 'todas las imágenes tienen alt');
    ok((await csp(page)).length === 0, 'sin violaciones de CSP: ' + JSON.stringify(await csp(page)));
    ok(errReales(errores).length === 0, 'sin errores JS: ' + JSON.stringify(errReales(errores)));
    // logout
    await page.evaluate(() => localStorage.setItem('borrador:' + currentUser.id + ':nuevo', '{"title":"x"}'));
    await page.click('#btn-logout'); await page.waitForTimeout(800);
    ok(await page.isVisible('#landing-screen'), 'logout vuelve a la landing');
    ok((await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('borrador') || k.startsWith('letras-academicas-auth')).length)) === 0, 'logout limpia sesión y borradores');
    await ctx.close(); }

  console.log('-- Carla (docente de OTRO curso)');
  { const { ctx, page, errores } = await abrir(browser, U.carla);
    await page.waitForSelector('#main-layout:not(.hidden)', { timeout: 8000 });
    await nav(page, 'textos');
    await page.click('#textos-list .card:has-text("Texto Dani")'); await page.waitForTimeout(400);
    ok(await page.isVisible('[data-action="destacar"]') && await page.isVisible('[data-action="delete"]'), 'docente del curso ve Destacar/Eliminar');
    await page.click('[data-action="destacar"]'); await page.waitForTimeout(600);
    ok(await page.isVisible('text=Quitar Destacado'), 'docente destaca un texto de su curso');
    await page.click('[data-action="destacar"]'); await page.waitForTimeout(600);
    if (MIGRADA) {
      await nav(page, 'textos');
      await page.click('#textos-list .card:has-text("Texto Beto destacado")'); await page.waitForTimeout(400);
      ok(!(await page.isVisible('[data-action="destacar"]')), 'docente de OTRO no modera textos de GENERAL');
    }
    ok(errReales(errores).length === 0, 'sin errores JS: ' + JSON.stringify(errReales(errores)));
    await ctx.close(); }

  console.log('-- Admin');
  { const { ctx, page, errores } = await abrir(browser, U.admin);
    await page.waitForSelector('#main-layout:not(.hidden)', { timeout: 8000 });
    await nav(page, 'miembros');
    const filas = page.locator('.u-s39');
    const n = await filas.count();
    ok(n >= 5, 'admin ve a todos (' + n + ')');
    ok(await page.locator('.u-s39:has-text("@federicoadmin") [data-action="eliminar-miembro"]').count() === 0, 'sin Eliminar frente a sí mismo');
    await page.click('.u-s39:has-text("@betoalumno") [data-action="eliminar-miembro"]'); await page.waitForTimeout(800);
    if (MIGRADA) ok(!(await page.isVisible('text=@betoalumno')), 'admin elimina a Beto vía RPC');
    else ok((page._dialogs||[]).some(m => /No se pudo eliminar/.test(m)), 'sin migrar: la RPC no existe y se muestra el error (sin romper la app)');
    ok(errReales(errores).filter(x => MIGRADA || !/eliminar_miembro|404/.test(x)).length === 0, 'sin errores JS: ' + JSON.stringify(errReales(errores)));
    await ctx.close(); }

  console.log('-- Usuario nuevo (sin perfil)');
  { const { ctx, page, errores } = await abrir(browser, U.nuevo);
    await page.waitForSelector('#main-layout:not(.hidden)', { timeout: 8000 });
    await nav(page, 'miembros');
    const un = await page.locator('.u-s39:has-text("Ana Nueva") .u-s43').textContent();
    ok(MIGRADA ? un === '@anaalumna2' : un === '@anaalumna' || un.startsWith('@'), 'perfil creado; username ' + un + (MIGRADA ? ' (único, lo fijó el servidor)' : ''));
    ok(errReales(errores).filter(x => MIGRADA || !/409|duplicate|23505/.test(x)).length === 0, 'sin errores JS: ' + JSON.stringify(errReales(errores)));
    await ctx.close(); }

  await browser.close();
  console.log(`== ${oks} ok, ${fallas} fallas`);
  process.exit(fallas ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
