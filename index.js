// ═══════════════════════════════════════════════════════════════
// 1. CONFIGURACIÓN SUPABASE Y VARIABLES GLOBALES
// ═══════════════════════════════════════════════════════════════
const SUPABASE_URL = 'https://xjrdjesezseuofjoqpzn.supabase.co';
const SUPABASE_KEY = 'sb_publishable_c6zrWAExpbRtV6tfrYS2fg_7BpKUO1P';
const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    // PKCE: el login vuelve con ?code= (de un solo uso, 5 min) en vez de tokens en el #fragmento
    flowType: 'pkce',
    storageKey: 'letras-academicas-auth'
  }
});

let currentUser   = null;
let allTexts      = [];
let allUsers      = [];
let quillEditor   = null;
let editingTextId = null;
let appInitialized = false;
let cursoGeneralId = null;   // Fase 1: todo texto nuevo va al curso General
let misCursosDocente = new Set(); // cursos donde soy docente (para moderar)

// Columnas de perfiles que la base deja leer (hallazgo 4: nada de select *)
const PERFIL_COLS = 'id, name, username, avatar_url, rol';
const esDocente = u => u && (u.rol === 'profesor' || u.rol === 'admin');
const esAdmin   = u => u && u.rol === 'admin';
// Autoría por id de cuenta (author_id); el username es solo un dato visible.
// (Fallback a username solo mientras la base no tenga la migración f02.)
const esMio = t => !!currentUser && (t.author_id ? t.author_id === currentUser.id : t.author_username === currentUser.username);
// Moderar (destacar / borrar) = admin o docente del curso del texto; igual que en la base
const puedeModerar = t => esAdmin(currentUser) || (!!t.curso_id && misCursosDocente.has(t.curso_id));

// Utilidades DOM
function esc(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function safeHtml(h){ return DOMPurify.sanitize(h || '', { ALLOWED_TAGS:['p','br','strong','b','em','i','u','blockquote','ol','ul','li','span','h2','h3'], ALLOWED_ATTR:['class'] }); }
// Quill 2: cargar HTML guardado (convierte <ul>/<ol> al modelo de Quill) y exportar HTML semántico
function cargarEnEditor(h){ quillEditor.setContents([]); quillEditor.clipboard.dangerouslyPasteHTML(0, safeHtml(h)); }
function htmlDelEditor(){
  if (quillEditor.getLength() <= 1) return '';
  return quillEditor.getSemanticHTML().replace(/&nbsp;/g, ' ').replace(/(<p><\/p>)+$/, '');
}
function showEl(id){ document.getElementById(id).classList.remove('hidden'); }
function hideEl(id){ document.getElementById(id).classList.add('hidden'); }
function formatDate(d){
  if (!d) return '';
  return new Date(d).toLocaleDateString('es-AR', { day:'numeric', month:'long', year:'numeric' });
}

// Tema oscuro
document.getElementById('theme-toggle').addEventListener('click', () => {
  document.body.classList.toggle('dark');
  document.getElementById('theme-toggle').textContent = document.body.classList.contains('dark') ? '☀️' : '🌓';
});

// ═══════════════════════════════════════════════════════════════
// 2. AUTENTICACIÓN
// ═══════════════════════════════════════════════════════════════
document.getElementById('login-google-btn').addEventListener('click', async () => {
  const { error } = await db.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } });
  if (error) alert('No se pudo iniciar sesión: ' + error.message);
});

function limpiarSesionLocal(uid) {
  if (typeof borrarBorradores === 'function') borrarBorradores(uid);
  Object.keys(localStorage).forEach(key => {
    if (key.startsWith('sb-') || key.startsWith('letras-academicas-auth')) localStorage.removeItem(key);
  });
}

async function doLogout() {
  const uid = currentUser?.id;
  try {
    const { error } = await db.auth.signOut();
    if (error) console.error('Error al cerrar sesión:', error);
  } catch (err) {
    console.error('Error al cerrar sesión:', err);
  } finally {
    limpiarSesionLocal(uid);
    location.href = window.location.origin;
  }
}

// Quitar ?code= / errores de OAuth de la barra de direcciones después del login
function limpiarUrlDeAuth() {
  const u = new URL(window.location.href);
  const err = u.searchParams.get('error_description');
  if (err) alert('No se pudo iniciar sesión: ' + err);
  if (['code', 'error', 'error_code', 'error_description', 'state'].some(k => u.searchParams.has(k))) {
    history.replaceState(null, '', u.pathname + u.hash);
  }
}

let authGen = 0;          // invalida inicializaciones en curso si cambia la sesión
let iniciandoUid = null;

// Supabase recomienda no hacer await dentro del callback (puede trabar el cliente):
// se difiere el trabajo con setTimeout(0).
db.auth.onAuthStateChange((event, session) => {
  setTimeout(() => { manejarAuth(event, session); }, 0);
});

async function manejarAuth(event, session) {
  const uid = session?.user?.id || null;
  if (!uid) {                       // SIGNED_OUT (también desde otra pestaña) o sin sesión
    authGen++;
    iniciandoUid = null;
    if (currentUser || appInitialized) cerrarApp();
    else mostrarLanding();
    return;
  }
  if (currentUser && currentUser.id === uid) return;   // TOKEN_REFRESHED, USER_UPDATED…
  if (iniciandoUid === uid) return;                    // ya se está cargando esta cuenta
  if (currentUser && currentUser.id !== uid) cerrarApp();  // cambió la cuenta (otra pestaña)
  const gen = ++authGen;
  iniciandoUid = uid;
  try {
    await iniciarApp(session, gen);
  } catch (e) {
    if (gen !== authGen) return;
    console.error('Error al cargar la cuenta:', e);
    alert('No se pudo cargar tu cuenta: ' + (e?.message || 'intentá de nuevo.'));
    await db.auth.signOut();
  } finally {
    if (iniciandoUid === uid) iniciandoUid = null;
  }
}

async function obtenerOCrearPerfil(session) {
  const uid          = session.user.id;
  const email        = session.user.email || '';
  const name         = session.user.user_metadata?.full_name || email.split('@')[0] || 'Usuario';
  const avatarUrl    = session.user.user_metadata?.avatar_url
    || `https://ui-avatars.com/api/?name=${encodeURIComponent(name)}&background=random`;
  const leer = () => db.from('perfiles').select(PERFIL_COLS).eq('id', uid).maybeSingle();

  let { data: perfil, error } = await leer();
  if (error) throw error;

  // El username y el rol los decide la base (único, derivado del email); acá solo se sugiere.
  for (let intento = 0; !perfil && intento < 3; intento++) {
    const { error: insErr } = await db.from('perfiles').insert([{
      id:         uid,
      username:   email.split('@')[0].toLowerCase().replace(/[^a-z0-9]/g, '') || 'usuario',
      name:       name.slice(0, 120),
      color:      '#2d5a8e',
      avatar_url: avatarUrl
    }]);
    // 23505 = ya existe (otra pestaña lo creó) o choque de username: releer / reintentar
    if (insErr && insErr.code !== '23505') throw insErr;
    ({ data: perfil, error } = await leer());
    if (error) throw error;
  }
  if (!perfil) throw new Error('No se pudo crear tu perfil.');

  if (perfil.avatar_url !== avatarUrl) {
    const { error: updErr } = await db.from('perfiles').update({ avatar_url: avatarUrl }).eq('id', uid);
    if (updErr) console.warn('No se pudo actualizar el avatar', updErr);
    else perfil.avatar_url = avatarUrl;
  }
  return perfil;
}

async function iniciarApp(session, gen) {
  limpiarUrlDeAuth();
  const perfil = await obtenerOCrearPerfil(session);
  if (gen !== authGen) return;
  currentUser = perfil;

  // Fase 1: asegurar membresía en el curso General (idempotente)
  try {
    const { data: cid, error } = await db.rpc('unirse_a_curso', { codigo: 'GENERAL' });
    if (error) console.warn('No se pudo unir al curso General', error);
    else cursoGeneralId = cid;
  } catch (e) { console.warn('No se pudo unir al curso General', e); }
  await cargarMisCursos();
  await refreshData();
  if (gen !== authGen) return;

  appInitialized = true;
  document.getElementById('topbar-uname').textContent = currentUser.name;
  document.getElementById('topbar-avatar').src = currentUser.avatar_url;
  showEl('topbar-avatar');
  hideEl('landing-screen');
  showEl('topbar');
  showEl('main-layout');
  navigate('dashboard');
}

function mostrarLanding() {
  hideEl('topbar');
  hideEl('main-layout');
  showEl('landing-screen');
  loadLandingDestacados();
}

// Sesión cerrada (acá o en otra pestaña) o cambio de cuenta: no dejar datos del usuario anterior
function cerrarApp() {
  const uid = currentUser?.id;
  if (typeof detenerBorrador === 'function') detenerBorrador();
  if (uid && typeof borrarBorradores === 'function') borrarBorradores(uid);
  currentUser = null; allTexts = []; allUsers = []; quillEditor = null; editingTextId = null;
  appInitialized = false; cursoGeneralId = null; misCursosDocente = new Set();
  document.getElementById('content-area').innerHTML = '';
  document.getElementById('topbar-uname').textContent = '';
  document.getElementById('topbar-avatar').removeAttribute('src');
  hideEl('topbar-avatar');
  mostrarLanding();
}

// ═══════════════════════════════════════════════════════════════
// 3. CARGA DE DATOS
// ═══════════════════════════════════════════════════════════════
async function cargarMisCursos() {
  const { data, error } = await db.from('miembros_curso').select('curso_id, rol').eq('user_id', currentUser.id);
  if (error) { console.warn('No se pudieron leer tus cursos', error); misCursosDocente = new Set(); return; }
  misCursosDocente = new Set((data || []).filter(m => m.rol === 'docente').map(m => m.curso_id));
}

async function refreshData() {
  const { data: uData } = await db.from('perfiles').select(PERFIL_COLS).order('name');
  allUsers = uData || [];
  const { data: tData } = await db.from('textos').select('*').order('created_at', { ascending: false });
  allTexts = tData || [];
}

function getAvatar(userId, username, fallbackName) {
  const user = allUsers.find(u => (userId && u.id === userId) || u.username === username);
  return user?.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(fallbackName)}&background=random`;
}

// ═══════════════════════════════════════════════════════════════
// 4. NAVEGACIÓN (ENRUTADOR)
// ═══════════════════════════════════════════════════════════════
// ── Borradores locales: un solo intervalo, clave por usuario + modo, se limpian al salir ──
let draftTimer = null;
function claveBorrador() {
  if (!currentUser) return null;
  return `borrador:${currentUser.id}:${editingTextId ? 'editar:' + editingTextId : 'nuevo'}`;
}
function detenerBorrador() {
  if (draftTimer) { clearInterval(draftTimer); draftTimer = null; }
}
function guardarBorrador() {
  const k = claveBorrador();
  const titleInput = document.getElementById('f-title');
  const typeInput  = document.getElementById('f-type');
  if (!k || !titleInput || !typeInput || !quillEditor) return;
  const body = htmlDelEditor();
  if (!titleInput.value.trim() && !body) { localStorage.removeItem(k); return; }
  try {
    localStorage.setItem(k, JSON.stringify({ title: titleInput.value, type: typeInput.value, body, ts: Date.now() }));
  } catch (e) { console.warn('No se pudo guardar el borrador', e); }
}
function restaurarBorrador(original) {
  const k = claveBorrador();
  const raw = k && localStorage.getItem(k);
  if (!raw) return;
  let data;
  try { data = JSON.parse(raw); } catch { localStorage.removeItem(k); return; }
  if (original && data.title === original.title && data.type === original.type && data.body === original.body) return;
  if (original && !confirm('Tenés cambios sin guardar de este texto. ¿Recuperarlos?')) { localStorage.removeItem(k); return; }
  document.getElementById('f-title').value = data.title || '';
  document.getElementById('f-type').value  = data.type  || 'ensayo';
  cargarEnEditor(data.body);
}
function borrarBorradores(uid) {
  Object.keys(localStorage).forEach(k => {
    if (k === 'borrador' || (uid && k.startsWith(`borrador:${uid}:`))) localStorage.removeItem(k);
  });
}

function navigate(page) {
  detenerBorrador();
  document.querySelectorAll('.nav-item').forEach(el => {
    el.classList.toggle('active', el.dataset.page === page);
  });

  const ca = document.getElementById('content-area');

  const pages = {
    dashboard:    renderDashboard,
    textos:       renderTextos,
    nuevo:        renderNuevo,
    miembros:     renderMiembros,
    'mis-textos': renderMisTextos
  };

  ca.innerHTML = (pages[page] || renderDashboard)();

  if (page === 'nuevo') {
    quillEditor = new Quill('#editor-container', {
      theme: 'snow',
      placeholder: 'Redacta tu texto académico aquí...',
      modules: {
        toolbar: [
          [{ 'header': [2, 3, false] }],
          ['bold', 'italic', 'blockquote'],
          [{ 'list': 'ordered' }, { 'list': 'bullet' }],
          ['clean']
        ]
      }
    });

    if (!editingTextId) restaurarBorrador(null);
    // Guardado automático cada 10 s (un único intervalo; se detiene al salir de la vista)
    draftTimer = setInterval(guardarBorrador, 10000);

    if (!editingTextId) {
      document.getElementById('btn-pub').textContent = "Publicar en la plataforma";
    }

  } else {
    editingTextId = null;
    quillEditor   = null;
  }

  ca.scrollTop = 0;
}
// ═══════════════════════════════════════════════════════════════
// 5. VISTAS
// ═══════════════════════════════════════════════════════════════

function renderDashboard() {
  const destacados = allTexts.filter(t => t.destacado);
  const recientes  = allTexts.slice(0, 5);
  return `
    <div class="page-header">
      <h1>Bienvenido/a, ${esc(currentUser.name.split(' ')[0])} 👋</h1>
    </div>
    ${destacados.length ? `
      <h3 class="u-s7">⭐ Destacados por el profesor</h3>
      ${destacados.map(cardHtml).join('')}
      <hr class="u-s8">
    ` : ''}
    <h3 class="u-s7">📋 Publicaciones recientes</h3>
    ${recientes.length ? recientes.map(cardHtml).join('') : '<p class="u-s9">Aún no hay publicaciones.</p>'}
  `;
}

function renderTextos() {
  return `
    <div class="page-header"><h1>Biblioteca Virtual</h1></div>
    <div class="u-s10">
      ${['todos','ensayo','informe','argumentativo','narrativo','expositivo','otro'].map(f => `
        <button class="btn-outline${f === 'todos' ? ' is-active' : ''}" data-action="filter" data-arg="${f}" id="f-${f}">
          ${f.charAt(0).toUpperCase() + f.slice(1)}
        </button>
      `).join('')}
    </div>
    <div id="textos-list">${allTexts.map(cardHtml).join('')}</div>
  `;
}

function filterTextos(tipo) {
  ['todos','ensayo','informe','argumentativo','narrativo','expositivo','otro'].forEach(f => {
    const btn = document.getElementById('f-' + f);
    if (!btn) return;
    btn.classList.toggle('is-active', f === tipo);
  });
  const filtered = tipo === 'todos' ? allTexts : allTexts.filter(t => t.type === tipo);
  document.getElementById('textos-list').innerHTML = filtered.map(cardHtml).join('');
}

function renderMisTextos() {
  const mis = allTexts.filter(esMio);
  return `
    <div class="page-header"><h1>Mis textos</h1></div>
    <button class="btn-primary u-s11" data-action="navigate" data-arg="nuevo">＋ Publicar nuevo texto</button>
    ${mis.length ? mis.map(cardHtml).join('') : '<p class="u-s9">Todavía no publicaste ningún texto.</p>'}
  `;
}

function cardHtml(t) {
  const tempDiv     = document.createElement('div');
  tempDiv.innerHTML = safeHtml(t.body);
  const plainText   = tempDiv.textContent || tempDiv.innerText || "";
  return `
    <div class="card" data-action="open" data-id="${esc(t.id)}">
      <div class="u-s12">
        <span class="tag ${esc(t.type)}">${esc(t.type)}</span>
        ${t.destacado ? '<span class="u-s13">⭐ Destacado</span>' : ''}
        <span class="u-s14">${formatDate(t.created_at)}</span>
      </div>
      <h2>${esc(t.title)}</h2>
      <div class="text-excerpt">${esc(plainText)}</div>
      <div class="u-s15">
        <div class="u-s2">
          <img src="${esc(getAvatar(t.author_id, t.author_username, t.author_name))}" class="avatar avatar-sm">
          <span class="u-s16">${esc(t.author_name)}</span>
        </div>
        <span class="u-s17">❤️ ${t.likes || 0}</span>
      </div>
    </div>`;
}

function renderNuevo() {
  const tituloPantalla = editingTextId ? "Editar publicación" : "Publicar un texto";
  return `
    <div class="page-header"><h1 id="lbl-header-nuevo">${tituloPantalla}</h1></div>
    <div class="u-s18">
      <div class="u-s11">
        <label class="u-s19">Título</label>
        <input class="u-s20" id="f-title" type="text" maxlength="200" placeholder="Ej: Análisis del discurso en medios digitales">
      </div>
      <div class="u-s11">
        <label class="u-s19">Tipo de texto</label>
        <select class="u-s21" id="f-type">
          <option value="ensayo">Ensayo</option>
          <option value="informe">Informe</option>
          <option value="argumentativo">Argumentativo</option>
          <option value="narrativo">Narrativo</option>
          <option value="expositivo">Expositivo</option>
          <option value="otro">Otro</option>
        </select>
      </div>
      <div class="u-s11">
        <label class="u-s19">Contenido</label>
        <div class="u-s22" id="editor-container"></div>
      </div>
      <button class="btn-primary" id="btn-pub" data-action="submit-text">Publicar en la plataforma</button>
    </div>`;
}

// ═══════════════════════════════════════════════════════════════
// 6. LÓGICA DE PUBLICAR / EDITAR
// ═══════════════════════════════════════════════════════════════

function editText(id) {
  const t = allTexts.find(x => x.id === id);
  if (!t) return;
  editingTextId = id;
  navigate('nuevo');
  document.getElementById('f-title').value                = t.title;
  document.getElementById('f-type').value                 = t.type;
  cargarEnEditor(t.body);
  document.getElementById('btn-pub').textContent          = "Guardar cambios";
  document.getElementById('lbl-header-nuevo').textContent = "Editar publicación";
  restaurarBorrador({ title: t.title, type: t.type, body: htmlDelEditor() });
}

async function submitText() {
  const title     = document.getElementById('f-title').value.trim();
  if (title.length > 200) { alert('El título no puede superar los 200 caracteres.'); return; }
  const type      = document.getElementById('f-type').value;
  const bodyHTML  = htmlDelEditor();
  const tempDiv   = document.createElement('div');
  tempDiv.innerHTML = safeHtml(bodyHTML);
  const textPlain = tempDiv.textContent || tempDiv.innerText || "";

  if (!title || !textPlain) { alert('Por favor, completa el título y el contenido.'); return; }

  const btn = document.getElementById('btn-pub');
  btn.disabled = true;

  try {
    if (editingTextId) {
      const { data: upd, error: updErr } = await db.from('textos')
        .update({ title, type, body: bodyHTML }).eq('id', editingTextId).select('id');
      if (updErr) throw updErr;
      if (!upd || !upd.length) throw new Error('No tenés permiso para editar este texto (o ya no existe).');
    } else {
      const { error: insErr } = await db.from('textos').insert([{
        title,
        author_username: currentUser.username,
        author_name:     currentUser.name,
        type,
        body:            bodyHTML,
        destacado:       false,
        likes:           0,
        ...(cursoGeneralId ? { curso_id: cursoGeneralId } : {}),
        date:            new Date().toISOString()
      }]);
      if (insErr) throw insErr;
    }
    detenerBorrador();
    if (claveBorrador()) localStorage.removeItem(claveBorrador());
    localStorage.removeItem('borrador');   // clave vieja (compartida entre usuarios)
    editingTextId = null;
    await refreshData();
    navigate('mis-textos');
  } catch (err) {
    console.error('Error al guardar:', err);
    alert('Hubo un error al guardar: ' + (err?.message || 'intentá de nuevo.'));
    btn.disabled = false;
  }
}

// ═══════════════════════════════════════════════════════════════
// 7. DETALLE DEL TEXTO Y COMENTARIOS
// ═══════════════════════════════════════════════════════════════

async function openText(id) {
  const t = allTexts.find(x => x.id === id);
  if (!t) return;
  const ca = document.getElementById('content-area');

  const { data: coms }   = await db.from('comentarios').select('*').eq('texto_id', id).order('created_at', { ascending: true });
  const { data: myLike } = await db.from('likes').select('*').eq('texto_id', id).eq('user_username', currentUser.username).maybeSingle();
  const yaDioLike = !!myLike;

  ca.innerHTML = `
    <button class="btn-outline u-s11" data-action="navigate" data-arg="textos">← Volver</button>
    <div class="u-s23">
      <h1 class="u-s24">${esc(t.title)}</h1>
      <div class="u-s25">
        <span class="tag ${esc(t.type)}">${esc(t.type)}</span>
        <span class="u-s9">${formatDate(t.created_at)}</span>
        <div class="u-s2">
          <img src="${esc(getAvatar(t.author_id, t.author_username, t.author_name))}" class="avatar avatar-sm">
          <span class="u-s3">${esc(t.author_name)}</span>
        </div>
        <button class="btn-outline${yaDioLike ? ' btn-liked' : ''}" data-action="like" data-id="${esc(t.id)}" data-on="${yaDioLike ? '1' : '0'}">
          ${yaDioLike ? '❤️ Ya no me gusta' : '🤍 Me gusta'} (${t.likes || 0})
        </button>
        ${puedeModerar(t) ? `
          <button class="btn-outline" data-action="destacar" data-id="${esc(t.id)}" data-on="${t.destacado ? '1' : '0'}">
            ${t.destacado ? 'Quitar Destacado' : '⭐ Destacar'}
          </button>` : ''}
        ${esMio(t) ? `
          <button class="btn-outline u-s26" data-action="edit" data-id="${esc(t.id)}">✏️ Editar</button>` : ''}
        ${esMio(t) || puedeModerar(t) ? `
          <button class="btn-outline u-s27" data-action="delete" data-id="${esc(t.id)}">🗑️ Eliminar</button>` : ''}
      </div>
      <div class="u-s28">${safeHtml(t.body)}</div>
    </div>

    <div class="u-s18">
      <h3 class="u-s29">Devoluciones (${coms ? coms.length : 0})</h3>
      ${(coms && coms.length) ? coms.map(c => `
        <div class="comment">
          <div class="u-s30">
            <img src="${esc(getAvatar(c.author_id, c.author_username, c.author_name))}" class="avatar avatar-sm">
            <span class="u-s31">${esc(c.author_name)}</span>
            <span class="u-s32">${formatDate(c.created_at)}</span>
          </div>
          <div class="u-s33">${esc(c.body)}</div>
        </div>
      `).join('') : '<p class="u-s34">Aún no hay devoluciones. ¡Sé el primero!</p>'}
      <h4 class="u-s35">Añadir devolución</h4>
      <textarea class="u-s36" id="com-body" rows="4" maxlength="5000" placeholder="Escribí tu devolución académica..."></textarea>
      <button class="btn-primary u-s37" data-action="comment" data-id="${esc(t.id)}">Enviar devolución</button>
    </div>
  `;
  ca.scrollTop = 0;
}

async function submitComment(textoId) {
  const body = document.getElementById('com-body').value.trim();
  if (!body) { alert('Escribí algo antes de enviar.'); return; }
  if (body.length > 5000) { alert('El comentario debe tener entre 1 y 5000 caracteres.'); return; }
  
  const btn = document.querySelector('[data-action="comment"]');
  if (btn) { btn.disabled = true; btn.textContent = 'Enviando...'; }
  
  const { error: comErr } = await db.from('comentarios').insert([{
    texto_id:        textoId,
    author_username: currentUser.username,
    author_name:     currentUser.name,
    body:            body
  }]);
  if (comErr) { alert('No se pudo enviar: ' + comErr.message); if (btn) { btn.disabled = false; btn.textContent = 'Enviar devolución'; } return; }
  openText(textoId);
}

// ═══════════════════════════════════════════════════════════════
// 8. ACCIONES (LIKES, DESTACADOS, ELIMINAR)
// ═══════════════════════════════════════════════════════════════

async function toggleLike(id, yaDioLike) {
  // No se puede likear el propio texto
  const t = allTexts.find(x => x.id === id);
  if (t && esMio(t)) {
    alert('No podés darle like a tu propio texto.');
    return;
  }
  // Si ya dio like, mostrar mensaje
  if (yaDioLike) {
    alert('Ya le diste like a este texto.');
    return;
  }
  await db.from('likes').insert([{ texto_id: id, user_username: currentUser.username }]);
  await refreshData();
  openText(id);
}

async function toggleDestacado(id, estadoActual) {
  const { data, error } = await db.from('textos').update({ destacado: !estadoActual }).eq('id', id).select('id, destacado');
  if (error) { alert('No se pudo cambiar el destacado: ' + error.message); return; }
  if (!data || !data.length || data[0].destacado === estadoActual) {
    alert('No tenés permiso para destacar este texto.');
    return;
  }
  await refreshData();
  openText(id);
}

async function deleteText(id) {
  if (!confirm('¿Estás seguro de eliminar este texto permanentemente?')) return;
  // Un solo DELETE: comentarios y likes se borran en cascada (FK ON DELETE CASCADE)
  const { data, error } = await db.from('textos').delete().eq('id', id).select('id');
  if (error) { alert('No se pudo eliminar: ' + error.message); return; }
  if (!data || !data.length) { alert('No tenés permiso para eliminar este texto (o ya no existe).'); return; }
  await refreshData();
  navigate('mis-textos');
}

// ═══════════════════════════════════════════════════════════════
// 9. VISTA COMPAÑEROS
// ═══════════════════════════════════════════════════════════════

function renderMiembros() {
  return `
    <div class="page-header"><h1>Compañeros</h1></div>
    <div class="u-s38">
      ${allUsers.map(u => `
        <div class="u-s39">
          <img src="${esc(u.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(u.name)}`)}" class="avatar">
          <div class="u-s40">
            <div class="u-s41">${esc(u.name)}
              ${esAdmin(u) ? '<span class="u-s42">⭐ Admin</span>' : u.rol === 'profesor' ? '<span class="u-s42">👨‍🏫 Docente</span>' : ''}
            </div>
            <div class="u-s43">@${esc(u.username)}</div>
          </div>
          ${esAdmin(currentUser) && u.id !== currentUser.id && !esAdmin(u) ? `
            <button class="btn-outline" data-uid="${esc(u.id)}" data-habilitar="${u.rol === 'profesor' ? '0' : '1'}"
              data-action="docente">
              ${u.rol === 'profesor' ? '↩️ Quitar docente' : '👨‍🏫 Habilitar docente'}</button>
          ` : ''}
          ${esAdmin(currentUser) && u.id !== currentUser.id && !esAdmin(u) ? `
            <button class="btn-outline u-s27"
              data-action="eliminar-miembro" data-uid="${esc(u.id)}">🗑️ Eliminar</button>
          ` : ''}
        </div>
      `).join('')}
    </div>`;
}

async function habilitarDocente(id, habilitar) {
  const u = allUsers.find(x => x.id === id);
  if (!u) return;
  if (!confirm(`¿${habilitar ? 'Habilitar' : 'Quitar'} como docente a ${u.name}?`)) return;
  const { error } = await db.rpc('habilitar_docente', { p_user: id, p_habilitar: habilitar });
  if (error) { alert('No se pudo cambiar el rol: ' + error.message); return; }
  await refreshData();
  navigate('miembros');
}

async function eliminarMiembro(id, nombre) {
  // Solo el admin, nunca a sí mismo ni a otro admin (lo valida la RPC en la base)
  if (!esAdmin(currentUser)) return;
  if (!confirm(`¿Eliminar a ${nombre} de la plataforma?`)) return;
  const { error } = await db.rpc('eliminar_miembro', { p_user: id });
  if (error) { alert('No se pudo eliminar: ' + error.message); return; }
  await refreshData();
  navigate('miembros');
}

// ═══════════════════════════════════════════════════════════════
// 10. LANDING - TEXTOS DESTACADOS (SIN LOGIN)
// ═══════════════════════════════════════════════════════════════

async function loadLandingDestacados() {
  // anon solo puede leer estas columnas (hallazgo 12)
  const { data, error } = await db.from('textos')
    .select('id, title, type, body, author_name, created_at')
    .eq('destacado', true)
    .order('created_at', { ascending: false })
    .limit(9);
  if (error) console.warn('No se pudieron cargar los destacados', error);

  const contenedor = document.getElementById('landing-textos');
  if (!data || data.length === 0) {
    contenedor.innerHTML = `
      <div class="lp-empty">
        <p>Todavía no hay textos destacados. ¿Y si el primero es el tuyo?</p>
        <a class="lp-btn lp-btn-accent" href="#probar">Probar la consigna del día</a>
      </div>`;
    return;
  }
  contenedor.innerHTML = data.slice(0, 9).map(t => {
    const tmp = document.createElement('div');
    tmp.innerHTML = safeHtml(t.body || '');
    const extracto = (tmp.textContent || '').trim().slice(0, 180);
    return `
    <article class="lp-card">
      <span class="lp-card-type">${esc(t.type)}</span>
      <h3>${esc(t.title)}</h3>
      ${extracto ? `<p>${esc(extracto)}${extracto.length >= 180 ? '…' : ''}</p>` : ''}
      <span class="lp-card-by">Por ${esc(t.author_name)}</span>
    </article>`;
  }).join('');
}

// La carga inicial la resuelve onAuthStateChange (evento INITIAL_SESSION):
// sin sesión muestra la landing con destacados; con sesión abre la app.

// Delegación de eventos (CSP sin 'unsafe-inline')
const ACCIONES = {
  logout:            ()  => doLogout(),
  navigate:          el  => navigate(el.dataset.arg),
  filter:            el  => filterTextos(el.dataset.arg),
  open:              el  => openText(el.dataset.id),
  'submit-text':     ()  => submitText(),
  like:              el  => toggleLike(el.dataset.id, el.dataset.on === '1'),
  destacar:          el  => toggleDestacado(el.dataset.id, el.dataset.on === '1'),
  edit:              el  => editText(el.dataset.id),
  delete:            el  => deleteText(el.dataset.id),
  comment:           el  => submitComment(el.dataset.id),
  docente:           el  => habilitarDocente(el.dataset.uid, el.dataset.habilitar === '1'),
  'eliminar-miembro': el => eliminarMiembro(el.dataset.uid, allUsers.find(x => x.id === el.dataset.uid)?.name || '')
};
document.addEventListener('click', e => {
  const el = e.target.closest('[data-action]');
  if (!el || !ACCIONES[el.dataset.action]) return;
  if (el.tagName === 'A') e.preventDefault();
  ACCIONES[el.dataset.action](el);
});
