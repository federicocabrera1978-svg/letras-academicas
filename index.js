// ═══════════════════════════════════════════════════════════════
// 1. CONFIGURACIÓN SUPABASE Y VARIABLES GLOBALES
// ═══════════════════════════════════════════════════════════════
const SUPABASE_URL = 'https://xjrdjesezseuofjoqpzn.supabase.co';
const SUPABASE_KEY = 'sb_publishable_c6zrWAExpbRtV6tfrYS2fg_7BpKUO1P';
const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let currentUser   = null;
let allTexts      = [];
let allUsers      = [];
let quillEditor   = null;
let editingTextId = null;

// Utilidades DOM
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
  await db.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } });
});

async function doLogout() {
  try {
    await db.auth.signOut();
    // Limpiar manualmente la sesión de Supabase del localStorage
    Object.keys(localStorage).forEach(key => {
      if (key.startsWith('sb-')) localStorage.removeItem(key);
    });
  } catch(err) {
    console.error('Error al cerrar sesión:', err);
  } finally {
    location.href = window.location.origin;
  }
}

db.auth.onAuthStateChange(async (event, session) => {
  if (!session) return;

  const email        = session.user.email;
  const name         = session.user.user_metadata.full_name || email.split('@')[0];
  const baseUsername = email.split('@')[0].toLowerCase().replace(/[^a-z0-9]/g, '');
  const avatarUrl    = session.user.user_metadata.avatar_url
    || `https://ui-avatars.com/api/?name=${encodeURIComponent(name)}&background=random`;

  let { data: userProfile } = await db.from('perfiles').select('*').eq('id', session.user.id).maybeSingle();

  if (!userProfile) {
    const newProfile = {
      id:         session.user.id,
      username:   baseUsername,
      name:       name,
      color:      '#2d5a8e',
      avatar_url: avatarUrl,
      rol:        (email === 'paulabaigorriabernal@gmail.com') ? 'profesor' : 'alumno'
    };
    await db.from('perfiles').insert([newProfile]);
    userProfile = newProfile;
  } else if (userProfile.avatar_url !== avatarUrl) {
    await db.from('perfiles').update({ avatar_url: avatarUrl }).eq('id', session.user.id);
    userProfile.avatar_url = avatarUrl;
  }

  currentUser = userProfile;
  document.getElementById('topbar-uname').textContent = currentUser.name;
  document.getElementById('topbar-avatar').src = currentUser.avatar_url;
  showEl('topbar-avatar');

  hideEl('landing-screen');
  showEl('topbar');
  showEl('main-layout');
  await refreshData();
  navigate('dashboard');
});

// ═══════════════════════════════════════════════════════════════
// 3. CARGA DE DATOS
// ═══════════════════════════════════════════════════════════════
async function refreshData() {
  const { data: uData } = await db.from('perfiles').select('*');
  allUsers = uData || [];
  const { data: tData } = await db.from('textos').select('*').order('created_at', { ascending: false });
  allTexts = tData || [];
}

function getAvatar(username, fallbackName) {
  const user = allUsers.find(u => u.username === username);
  return user?.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(fallbackName)}&background=random`;
}

// ═══════════════════════════════════════════════════════════════
// 4. NAVEGACIÓN (ENRUTADOR)
// ═══════════════════════════════════════════════════════════════
function navigate(page) {
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

    // Restaurar borrador si existe
    const borrador = localStorage.getItem('borrador');
    if (borrador && !editingTextId) {
      const data = JSON.parse(borrador);
      document.getElementById('f-title').value = data.title || '';
      document.getElementById('f-type').value  = data.type  || 'ensayo';
      quillEditor.root.innerHTML               = data.body  || '';
    }

    // Guardar automáticamente cada 10 segundos
    setInterval(() => {
      localStorage.setItem('borrador', JSON.stringify({
        title: document.getElementById('f-title').value,
        type:  document.getElementById('f-type').value,
        body:  quillEditor.root.innerHTML
      }));
    }, 10000);

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
      <h1>Bienvenido/a, ${currentUser.name.split(' ')[0]} 👋</h1>
    </div>
    ${destacados.length ? `
      <h3 style="font-family:var(--font-serif); margin-bottom:15px;">⭐ Destacados por el profesor</h3>
      ${destacados.map(cardHtml).join('')}
      <hr style="margin:30px 0; border-color:var(--border-color);">
    ` : ''}
    <h3 style="font-family:var(--font-serif); margin-bottom:15px;">📋 Publicaciones recientes</h3>
    ${recientes.length ? recientes.map(cardHtml).join('') : '<p style="color:var(--text-muted);">Aún no hay publicaciones.</p>'}
  `;
}

function renderTextos() {
  return `
    <div class="page-header"><h1>Biblioteca Virtual</h1></div>
    <div style="display:flex; gap:10px; margin-bottom:20px; flex-wrap:wrap;">
      ${['todos','ensayo','informe','argumentativo','narrativo','expositivo','otro'].map(f => `
        <button class="btn-outline" onclick="filterTextos('${f}')" id="f-${f}"
          style="${f === 'todos' ? 'background:var(--accent);color:#fff;border-color:var(--accent);' : ''}">
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
    btn.style.background  = f === tipo ? 'var(--accent)' : '';
    btn.style.color       = f === tipo ? '#fff' : '';
    btn.style.borderColor = f === tipo ? 'var(--accent)' : 'var(--border-color)';
  });
  const filtered = tipo === 'todos' ? allTexts : allTexts.filter(t => t.type === tipo);
  document.getElementById('textos-list').innerHTML = filtered.map(cardHtml).join('');
}

function renderMisTextos() {
  const mis = allTexts.filter(t => t.author_username === currentUser.username);
  return `
    <div class="page-header"><h1>Mis textos</h1></div>
    <button class="btn-primary" onclick="navigate('nuevo')" style="margin-bottom:20px;">＋ Publicar nuevo texto</button>
    ${mis.length ? mis.map(cardHtml).join('') : '<p style="color:var(--text-muted);">Todavía no publicaste ningún texto.</p>'}
  `;
}

function cardHtml(t) {
  const tempDiv     = document.createElement('div');
  tempDiv.innerHTML = t.body;
  const plainText   = tempDiv.textContent || tempDiv.innerText || "";
  return `
    <div class="card" onclick="openText('${t.id}')">
      <div style="display:flex; gap:10px; align-items:center; margin-bottom:12px;">
        <span class="tag ${t.type}">${t.type}</span>
        ${t.destacado ? '<span style="font-size:13px;">⭐ Destacado</span>' : ''}
        <span style="font-size:12px; color:var(--text-muted); margin-left:auto;">${formatDate(t.created_at)}</span>
      </div>
      <h2>${t.title}</h2>
      <div class="text-excerpt">${plainText}</div>
      <div style="border-top:1px solid var(--border-color); padding-top:15px; margin-top:15px; display:flex; justify-content:space-between; align-items:center;">
        <div style="display:flex; align-items:center; gap:8px;">
          <img src="${getAvatar(t.author_username, t.author_name)}" class="avatar avatar-sm">
          <span style="font-size:14px; font-weight:500;">${t.author_name}</span>
        </div>
        <span style="font-size:14px; color:var(--text-muted);">❤️ ${t.likes || 0}</span>
      </div>
    </div>`;
}

function renderNuevo() {
  const tituloPantalla = editingTextId ? "Editar publicación" : "Publicar un texto";
  return `
    <div class="page-header"><h1 id="lbl-header-nuevo">${tituloPantalla}</h1></div>
    <div style="background:var(--bg-card); padding:30px; border-radius:var(--r); border:1px solid var(--border-color);">
      <div style="margin-bottom:20px;">
        <label style="display:block; margin-bottom:8px; font-weight:500;">Título</label>
        <input id="f-title" type="text" placeholder="Ej: Análisis del discurso en medios digitales"
          style="width:100%; padding:10px 14px; border:1px solid var(--border-color); border-radius:6px; font-family:var(--font-sans); font-size:15px; background:var(--bg-body); color:var(--text-main);">
      </div>
      <div style="margin-bottom:20px;">
        <label style="display:block; margin-bottom:8px; font-weight:500;">Tipo de texto</label>
        <select id="f-type" style="padding:10px 14px; border:1px solid var(--border-color); border-radius:6px; font-family:var(--font-sans); background:var(--bg-body); color:var(--text-main);">
          <option value="ensayo">Ensayo</option>
          <option value="informe">Informe</option>
          <option value="argumentativo">Argumentativo</option>
          <option value="narrativo">Narrativo</option>
          <option value="expositivo">Expositivo</option>
          <option value="otro">Otro</option>
        </select>
      </div>
      <div style="margin-bottom:20px;">
        <label style="display:block; margin-bottom:8px; font-weight:500;">Contenido</label>
        <div id="editor-container" style="background:var(--bg-body); min-height:250px;"></div>
      </div>
      <button class="btn-primary" id="btn-pub" onclick="submitText()">Publicar en la plataforma</button>
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
  quillEditor.root.innerHTML                              = t.body;
  document.getElementById('btn-pub').textContent          = "Guardar cambios";
  document.getElementById('lbl-header-nuevo').textContent = "Editar publicación";
}

async function submitText() {
  const title     = document.getElementById('f-title').value.trim();
  const type      = document.getElementById('f-type').value;
  const bodyHTML  = quillEditor.root.innerHTML;
  const tempDiv   = document.createElement('div');
  tempDiv.innerHTML = bodyHTML;
  const textPlain = tempDiv.textContent || tempDiv.innerText || "";

  if (!title || !textPlain) { alert('Por favor, completa el título y el contenido.'); return; }

  const btn = document.getElementById('btn-pub');
  btn.disabled = true;

  try {
    if (editingTextId) {
      await db.from('textos').update({ title, type, body: bodyHTML }).eq('id', editingTextId);
      editingTextId = null;
    } else {
      await db.from('textos').insert([{
        title,
        author_username: currentUser.username,
        author_name:     currentUser.name,
        type,
        body:            bodyHTML,
        destacado:       false,
        likes:           0,
        date:            new Date().toISOString()
      }]);
    }
    await refreshData();
    localStorage.removeItem('borrador');
    navigate('mis-textos');
  } catch (err) {
    console.error('Error al guardar:', err);
    alert('Hubo un error al guardar. Intentá de nuevo.');
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
    <button class="btn-outline" onclick="navigate('textos')" style="margin-bottom:20px;">← Volver</button>
    <div style="background:var(--bg-card); padding:40px; border-radius:var(--r); border:1px solid var(--border-color); margin-bottom:20px;">
      <h1 style="font-family:var(--font-serif); font-size:36px; line-height:1.2; margin-bottom:20px;">${t.title}</h1>
      <div style="display:flex; gap:15px; align-items:center; flex-wrap:wrap; margin-bottom:30px;">
        <span class="tag ${t.type}">${t.type}</span>
        <span style="color:var(--text-muted);">${formatDate(t.created_at)}</span>
        <div style="display:flex; align-items:center; gap:8px;">
          <img src="${getAvatar(t.author_username, t.author_name)}" class="avatar avatar-sm">
          <span style="font-weight:500;">${t.author_name}</span>
        </div>
        <button class="btn-outline" onclick="toggleLike('${t.id}', ${yaDioLike})"
          style="${yaDioLike ? 'color:var(--accent);border-color:var(--accent);' : ''}">
          ${yaDioLike ? '❤️ Ya no me gusta' : '🤍 Me gusta'} (${t.likes || 0})
        </button>
        ${currentUser.rol === 'profesor' ? `
          <button class="btn-outline" onclick="toggleDestacado('${t.id}', ${t.destacado})">
            ${t.destacado ? 'Quitar Destacado' : '⭐ Destacar'}
          </button>` : ''}
        ${currentUser.username === t.author_username ? `
          <button class="btn-outline" style="color:#0284c7;border-color:#0284c7;" onclick="editText('${t.id}')">✏️ Editar</button>
          <button class="btn-outline" style="color:var(--warn);border-color:var(--warn);" onclick="deleteText('${t.id}')">🗑️ Eliminar</button>
        ` : ''}
      </div>
      <div style="font-family:var(--font-serif); font-size:17px; line-height:1.8; color:var(--text-main);">${t.body}</div>
    </div>

    <div style="background:var(--bg-card); padding:30px; border-radius:var(--r); border:1px solid var(--border-color);">
      <h3 style="font-family:var(--font-serif); margin-bottom:20px;">Devoluciones (${coms ? coms.length : 0})</h3>
      ${(coms && coms.length) ? coms.map(c => `
        <div class="comment">
          <div style="display:flex; align-items:center; gap:8px; margin-bottom:8px;">
            <img src="${getAvatar(c.author_username, c.author_name)}" class="avatar avatar-sm">
            <span style="font-weight:600; font-size:13px;">${c.author_name}</span>
            <span style="font-weight:400; color:var(--text-muted); font-size:12px;">${formatDate(c.created_at)}</span>
          </div>
          <div style="color:var(--text-main); line-height:1.6;">${c.body}</div>
        </div>
      `).join('') : '<p style="color:var(--text-muted); margin-bottom:20px;">Aún no hay devoluciones. ¡Sé el primero!</p>'}
      <h4 style="margin-bottom:10px;">Añadir devolución</h4>
      <textarea id="com-body" rows="4" placeholder="Escribí tu devolución académica..."
        style="width:100%; padding:12px; border:1px solid var(--border-color); border-radius:6px; font-family:var(--font-sans); font-size:14px; background:var(--bg-body); color:var(--text-main); resize:vertical;"></textarea>
      <button class="btn-primary" style="margin-top:12px;" onclick="submitComment('${t.id}')">Enviar devolución</button>
    </div>
  `;
  ca.scrollTop = 0;
}

async function submitComment(textoId) {
  const body = document.getElementById('com-body').value.trim();
  if (!body) { alert('Escribí algo antes de enviar.'); return; }
  await db.from('comentarios').insert([{
    texto_id:        textoId,
    author_username: currentUser.username,
    author_name:     currentUser.name,
    body:            body
  }]);
  openText(textoId);
}

// ═══════════════════════════════════════════════════════════════
// 8. ACCIONES (LIKES, DESTACADOS, ELIMINAR)
// ═══════════════════════════════════════════════════════════════

async function toggleLike(id, yaDioLike) {
  // No se puede likear el propio texto
  const t = allTexts.find(x => x.id === id);
  if (t && t.author_username === currentUser.username) {
    alert('No podés darle like a tu propio texto.');
    return;
  }
  // Si ya dio like, mostrar mensaje
  if (yaDioLike) {
    alert('Ya le diste like a este texto.');
    return;
  }
  await db.from('likes').insert([{ texto_id: id, user_username: currentUser.username }]);
  await db.from('textos').update({ likes: (allTexts.find(t => t.id === id)?.likes || 0) + 1 }).eq('id', id);
  await refreshData();
  openText(id);
}

async function toggleDestacado(id, estadoActual) {
  await db.from('textos').update({ destacado: !estadoActual }).eq('id', id);
  await refreshData();
  openText(id);
}

async function deleteText(id) {
  if (!confirm('¿Estás seguro de eliminar este texto permanentemente?')) return;
  await db.from('likes').delete().eq('texto_id', id);
  await db.from('comentarios').delete().eq('texto_id', id);
  await db.from('textos').delete().eq('id', id);
  await refreshData();
  navigate('mis-textos');
}

// ═══════════════════════════════════════════════════════════════
// 9. VISTA COMPAÑEROS
// ═══════════════════════════════════════════════════════════════

function renderMiembros() {
  return `
    <div class="page-header"><h1>Compañeros</h1></div>
    <div style="display:grid; gap:15px;">
      ${allUsers.map(u => `
        <div style="background:var(--bg-card); padding:15px 20px; border-radius:var(--r); border:1px solid var(--border-color); display:flex; align-items:center; gap:15px;">
          <img src="${u.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(u.name)}`}" class="avatar">
          <div style="flex:1;">
            <div style="font-weight:600;">${u.name}
              ${u.rol === 'profesor' ? '<span style="color:var(--accent); font-size:12px; margin-left:10px;">👨‍🏫 Profesora</span>' : ''}
            </div>
            <div style="color:var(--text-muted); font-size:13px;">@${u.username}</div>
          </div>
          ${currentUser.rol === 'profesor' && u.id !== currentUser.id ? `
            <button class="btn-outline" style="color:var(--warn);border-color:var(--warn);"
              onclick="eliminarMiembro('${u.id}', '${u.name}')">🗑️ Eliminar</button>
          ` : ''}
        </div>
      `).join('')}
    </div>`;
}

async function eliminarMiembro(id, nombre) {
  if (!confirm(`¿Eliminar a ${nombre} de la plataforma?`)) return;
  await db.from('perfiles').delete().eq('id', id);
  await refreshData();
  navigate('miembros');
}

// ═══════════════════════════════════════════════════════════════
// 10. LANDING - TEXTOS DESTACADOS (SIN LOGIN)
// ═══════════════════════════════════════════════════════════════

async function loadLandingDestacados() {
  const { data } = await db.from('textos')
    .select('*')
    .eq('destacado', true)
    .order('created_at', { ascending: false });

  const contenedor = document.getElementById('landing-textos');
  if (!data || data.length === 0) {
    contenedor.innerHTML = '<p style="color:#94a3b8;">No hay textos destacados aún.</p>';
    return;
  }

  contenedor.innerHTML = data.map(t => `
    <div style="background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:20px; margin-bottom:15px;">
      <div style="font-size:12px; color:#94a3b8; margin-bottom:8px; text-transform:uppercase;">${t.type}</div>
      <div style="font-family:var(--font-serif); font-size:18px; font-weight:600; margin-bottom:8px;">${t.title}</div>
      <div style="font-size:13px; color:#cbd5e1;">Por ${t.author_name}</div>
    </div>
  `).join('');
}

loadLandingDestacados();
