// E2E de foros y sala de debates (Chrome headless contra PostgREST local; no toca producción).
// BASE=http://localhost:8080 FD=1  -> base con las migraciones de foros/debates
// BASE=http://localhost:8081 FD=0  -> base como prod hoy (sin foros): la UI no se rompe
const { chromium } = require('playwright-core');
const jwt = require('jsonwebtoken');
const BASE = process.env.BASE || 'http://localhost:8080';
const FD = process.env.FD ? process.env.FD === '1' : BASE.endsWith('8080');
const SECRET = 'e2e-secret-e2e-secret-e2e-secret-0123456789';
const U = {
  admin: { id:'00000000-0000-0000-0000-00000000000a', email:'federico.admin@gmail.com', name:'Federico' },
  ana:   { id:'00000000-0000-0000-0000-000000000001', email:'ana.alumna@gmail.com', name:'Ana' },
  beto:  { id:'00000000-0000-0000-0000-000000000002', email:'beto.alumno@gmail.com', name:'Beto' },
  carla: { id:'00000000-0000-0000-0000-000000000003', email:'carla.profe@gmail.com', name:'Carla' },
  dani:  { id:'00000000-0000-0000-0000-000000000004', email:'dani.otro@gmail.com', name:'Dani' },
  eva:   { id:'00000000-0000-0000-0000-000000000006', email:'eva@gmail.com', name:'Eva' },
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
  const ctx = await browser.newContext({ viewport: u && u.movil ? { width: 390, height: 844 } : undefined });
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
  if (u) await page.waitForSelector('#main-layout:not(.hidden)', { timeout: 8000 });
  return { ctx, page, errores };
}
const csp = page => page.evaluate(() => window.__csp);
const errReales = e => e.filter(x => !/googleusercontent|ui-avatars|ERR_|Failed to load resource/.test(x));
const nav = async (page, p) => { await page.click(`.nav-item[data-page="${p}"]`); await page.waitForTimeout(500); };
const espera = page => page.waitForTimeout(600);
const limpio = async (page, errores, quien) => {
  ok((await csp(page)).length === 0, quien + ': sin violaciones de CSP ' + JSON.stringify(await csp(page)));
  ok(errReales(errores).length === 0, quien + ': sin errores JS ' + JSON.stringify(errReales(errores)));
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  console.log(`== Base: ${BASE} (${FD ? 'con foros y debates' : 'sin las migraciones de foros/debates'})`);

  if (!FD) {
    console.log('-- frontend nuevo contra la base sin migrar');
    { const { ctx, page, errores } = await abrir(browser, null);
      await page.waitForTimeout(800);
      ok(await page.locator('#lp-debates').isHidden(), 'portada: la sección de debates queda oculta');
      await limpio(page, errores, 'anon'); await ctx.close(); }
    { const { ctx, page, errores } = await abrir(browser, U.ana);
      await nav(page, 'foros');
      ok(await page.isVisible('text=todavía no está disponible'), 'Foros muestra aviso amable');
      await nav(page, 'debates');
      ok(await page.isVisible('text=todavía no está disponible'), 'Debates muestra aviso amable');
      await nav(page, 'textos');
      ok(await page.locator('#textos-list .card').count() >= 1, 'el resto de la app sigue andando');
      await limpio(page, errores, 'Ana'); await ctx.close(); }
    await browser.close();
    console.log(`== ${oks} ok, ${fallas} fallas`); process.exit(fallas ? 1 : 0);
  }

  console.log('-- Admin: abre un foro en GENERAL');
  { const { ctx, page, errores } = await abrir(browser, U.admin);
    ok(await page.locator('nav.sidebar [data-page="foros"]').count() === 1 && await page.locator('nav.sidebar [data-page="debates"]').count() === 1, 'menú con Foros y Debates');
    await nav(page, 'foros');
    await page.click('.cv-nuevo summary');
    ok(await page.locator('#fo-curso option').count() === 2, 'admin elige entre todos los cursos');
    await page.selectOption('#fo-curso', '20000000-0000-0000-0000-000000000001');
    await page.fill('#fo-titulo', '¿Qué estamos leyendo?'); await page.fill('#fo-consigna', 'Contá un libro <b>que</b> te guste');
    await page.click('[data-action="foro-crear"]'); await espera(page);
    ok(await page.isVisible('h1:has-text("¿Qué estamos leyendo?")'), 'foro creado y abierto');
    ok(await page.isVisible('text=Contá un libro <b>que</b> te guste'), 'consigna con HTML se muestra como texto (escapada)');
    await limpio(page, errores, 'admin'); await ctx.close(); }

  console.log('-- Ana (alumna GENERAL): publica, edita');
  { const { ctx, page, errores } = await abrir(browser, U.ana);
    await nav(page, 'foros');
    ok(await page.locator('.cv-nuevo').count() === 0, 'alumna no ve "abrir foro"');
    await page.click('#foros-lista .card:has-text("¿Qué estamos leyendo?")'); await espera(page);
    await page.fill('#foro-body', 'Estoy leyendo Rayuela <img src=x onerror=alert(1)>');
    await page.click('[data-action="foro-publicar"]'); await espera(page);
    ok(await page.isVisible('text=Estoy leyendo Rayuela <img src=x onerror=alert(1)>'), 'mensaje publicado; HTML inyectado queda como texto');
    ok(await page.locator('.cv-msg img').count() === 0, 'no se creó ningún <img> desde el mensaje');
    await page.click('[data-action="cv-editar"]'); await page.waitForTimeout(200);
    await page.fill('textarea[id^="cv-edit-"]', 'Estoy leyendo Rayuela, de Cortázar');
    await page.click('[data-action="foro-guardar"]'); await espera(page);
    ok(await page.isVisible('text=Estoy leyendo Rayuela, de Cortázar') && await page.isVisible('text=editado'), 'autora edita en línea (queda "editado")');
    ok(await page.locator('[data-action="foro-fijar"], [data-action="foro-ocultar"], [data-action="foro-estado"]').count() === 0, 'alumna no ve botones de moderación');
    await limpio(page, errores, 'Ana'); await ctx.close(); }

  console.log('-- Beto (compañero) responde en hilo');
  { const { ctx, page, errores } = await abrir(browser, U.beto);
    await nav(page, 'foros');
    await page.click('#foros-lista .card >> nth=0'); await espera(page);
    ok(await page.locator('.cv-msg:has-text("Rayuela") [data-action="cv-editar"]').count() === 0, 'no puede editar el mensaje ajeno');
    await page.click('[data-action="foro-responder"]'); await page.waitForTimeout(200);
    await page.fill('textarea[id^="resp-"]', '¡Yo también lo estoy leyendo!');
    await page.click('[data-action="foro-publicar"][data-parent]'); await espera(page);
    ok(await page.locator('.cv-respuesta:has-text("¡Yo también")').count() === 1, 'respuesta en hilo');
    await limpio(page, errores, 'Beto'); await ctx.close(); }

  console.log('-- Admin modera: fija, oculta, cierra');
  { const { ctx, page, errores } = await abrir(browser, U.admin);
    await nav(page, 'foros');
    await page.click('#foros-lista .card >> nth=0'); await espera(page);
    await page.click('.cv-msg:has-text("Rayuela") >> [data-action="foro-fijar"] >> nth=0'); await espera(page);
    ok(await page.isVisible('text=📌 Fijado'), 'docente fija un mensaje');
    await page.click('.cv-respuesta [data-action="foro-ocultar"]'); await espera(page);
    ok(await page.isVisible('text=Oculto para el curso'), 'docente oculta una respuesta');
    await page.click('[data-action="foro-estado"]'); await espera(page);
    ok(await page.isVisible('text=El foro está cerrado'), 'docente cierra el foro');
    await page.click('[data-action="foro-estado"]'); await espera(page);
    ok(await page.isVisible('#foro-body'), 'y lo reabre');
    await limpio(page, errores, 'admin'); await ctx.close(); }

  { const { ctx, page, errores } = await abrir(browser, U.ana);
    await nav(page, 'foros'); await page.click('#foros-lista .card >> nth=0'); await espera(page);
    ok(!(await page.isVisible('text=¡Yo también')), 'Ana ya no ve la respuesta oculta');
    await limpio(page, errores, 'Ana'); await ctx.close(); }

  console.log('-- Carla (profesora de OTRO) abre un debate');
  { const { ctx, page, errores } = await abrir(browser, U.carla);
    await nav(page, 'debates');
    await page.click('.cv-nuevo summary');
    ok(await page.locator('#de-curso[type="hidden"]').count() === 1, 'un solo curso propio: no pide elegir');
    await page.fill('#de-pregunta', '¿Debería ser obligatorio el uniforme?');
    await page.fill('#de-posturas', 'Sí\nNo');
    await page.click('[data-action="debate-crear"]'); await espera(page);
    ok(await page.isVisible('h1:has-text("uniforme")') && await page.locator('.cv-postura').count() === 2, 'debate creado con 2 posturas');
    await limpio(page, errores, 'Carla'); await ctx.close(); }

  console.log('-- Ana (no es de OTRO; la app une a todos a GENERAL al entrar)');
  { const { ctx, page, errores } = await abrir(browser, U.ana);
    await nav(page, 'debates'); await page.waitForTimeout(300);
    ok(await page.locator('#debates-lista .card').count() === 0, 'no ve el debate de un curso del que no es miembro');
    const r = await page.evaluate(() => db.from('debate_posturas').select('id'));
    ok(!r.error && r.data.length === 0, 'ni sus posturas por la API');
    await limpio(page, errores, 'Ana'); await ctx.close(); }

  console.log('-- Dani elige postura y argumenta (en celular)');
  { const { ctx, page, errores } = await abrir(browser, { ...U.dani, movil: true });
    await nav(page, 'debates');
    await page.click('#debates-lista .card >> nth=0'); await espera(page);
    ok(await page.isVisible('text=Elegí una postura para poder argumentar'), 'sin postura no hay caja de argumento');
    await page.click('[data-action="debate-elegir"]:has-text("Sí")'); await espera(page);
    ok(await page.getAttribute('[data-action="debate-elegir"]:has-text("Sí")', 'aria-pressed') === 'true', 'postura elegida');
    await page.fill('#debate-body', 'El uniforme iguala a todos');
    await page.click('[data-action="debate-argumentar"]:not([data-parent])'); await espera(page);
    ok(await page.locator('.cv-postura:has(h3:has-text("Sí")) :text("El uniforme iguala a todos")').count() === 1, 'argumento en la columna de su postura');
    ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'sin scroll horizontal en 390px');
    await limpio(page, errores, 'Dani'); await ctx.close(); }

  console.log('-- Eva (alumna de OTRO): otra postura, réplica y "me hizo pensar"');
  { const { ctx, page, errores } = await abrir(browser, U.eva);
    await page.evaluate(() => db.rpc('unirse_a_curso', { codigo: 'OTRO01' }));
    await page.reload(); await page.waitForSelector('#main-layout:not(.hidden)');
    await nav(page, 'debates');
    await page.click('#debates-lista .card >> nth=0'); await espera(page);
    await page.click('[data-action="debate-elegir"]:has-text("No")'); await espera(page);
    await page.click('[data-action="debate-replicar"]'); await page.waitForTimeout(200);
    await page.fill('textarea[id^="resp-"]', 'Pero limita la expresión');
    await page.click('[data-action="debate-argumentar"][data-parent]'); await espera(page);
    ok(await page.isVisible('text=desde "No"'), 'réplica marcada con la postura de quien replica');
    await page.click('.cv-msg:has-text("iguala") >> [data-action="debate-pensar"] >> nth=0'); await espera(page);
    ok(await page.isVisible('text=Me hizo pensar ✓'), '"me hizo pensar" marcado');
    ok(!(await page.isVisible('text=votos')) && !(await page.isVisible('text=gana')), 'sin conteos por postura ni ganador');
    await limpio(page, errores, 'Eva'); await ctx.close(); }

  console.log('-- Carla cierra, escribe la síntesis y la destaca');
  { const { ctx, page, errores } = await abrir(browser, U.carla);
    await nav(page, 'debates');
    await page.click('#debates-lista .card >> nth=0'); await espera(page);
    ok(await page.isVisible('text=A 1 persona le hizo pensar') === false, 'la docente no ve ranking de argumentos');
    await page.click('[data-action="debate-estado"]'); await espera(page);
    await page.fill('#de-sintesis', 'El grupo pensó en la igualdad y en la expresión personal.');
    await page.click('[data-action="debate-sintesis"]'); await espera(page);
    await page.click('[data-action="debate-destacar"]'); await espera(page);
    ok(await page.isVisible('text=Síntesis destacada en la portada'), 'síntesis destacada');
    await limpio(page, errores, 'Carla'); await ctx.close(); }

  console.log('-- Dani ve su "me hizo pensar" (solo el autor ve el número)');
  { const { ctx, page, errores } = await abrir(browser, U.dani);
    await nav(page, 'debates'); await page.click('#debates-lista .card >> nth=0'); await espera(page);
    ok(await page.isVisible('text=A 1 persona le hizo pensar'), 'el autor ve a cuántos les hizo pensar');
    ok(await page.isVisible('text=El grupo pensó en la igualdad'), 'alumno lee la síntesis');
    ok(await page.locator('[data-action="debate-elegir"][disabled]').count() === 2, 'cerrado: no puede cambiar de postura');
    await limpio(page, errores, 'Dani'); await ctx.close(); }

  console.log('-- anon: portada con la síntesis destacada');
  { const { ctx, page, errores } = await abrir(browser, null);
    await page.waitForSelector('#lp-debates:not(.hidden) .lp-card', { timeout: 5000 }).catch(() => {});
    ok(await page.isVisible('#lp-debates .lp-card:has-text("uniforme")'), 'la síntesis destacada aparece en la portada');
    const txt = await page.textContent('#lp-debates');
    ok(!/Dani|Eva|Carla|iguala a todos|limita la expresión/.test(txt), 'sin nombres ni argumentos de alumnos en la portada');
    await limpio(page, errores, 'anon'); await ctx.close(); }

  await browser.close();
  console.log(`== ${oks} ok, ${fallas} fallas`);
  process.exit(fallas ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
