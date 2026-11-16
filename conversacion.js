// ═══════════════════════════════════════════════════════════════
// 11. FOROS Y SALA DE DEBATES
// ═══════════════════════════════════════════════════════════════
// Todo el contenido de alumnos es texto plano: se muestra con esc() (nunca como HTML).
// Los permisos los decide la base (RLS + triggers); la UI solo oculta botones que no corresponden.
// Avisos en vivo: no hay (refresco manual con "↻ Actualizar"); ver docs/FOROS-DEBATES.md.

let misCursos = [];            // [{ id, nombre }] cursos donde soy miembro
let foroActual = null;         // id del foro abierto
let debateActual = null;       // id del debate abierto
const LARGO_MSG = 5000;

const modera = cursoId => esAdmin(currentUser) || misCursosDocente.has(cursoId);
const cursosDocente = () => misCursos.filter(c => modera(c.id));
const nombreCurso = id => misCursos.find(c => c.id === id)?.nombre || '';
const textoPlano = s => `<div class="u-s33">${esc(s)}</div>`;
const NO_DISPONIBLE = '<p class="u-s9">Esta sección todavía no está disponible. Probá de nuevo más tarde.</p>';

async function cargarMisCursosConNombre() {
  const { data, error } = await db.from('cursos').select('id, nombre').order('nombre').limit(200);
  if (error) { console.warn('No se pudieron leer los cursos', error); misCursos = []; return; }
  misCursos = data || [];
}

function selectorCurso(id) {
  const cs = cursosDocente();
  if (cs.length <= 1) return cs.length ? `<input type="hidden" id="${id}" value="${esc(cs[0].id)}">` : '';
  return `
    <div class="u-s11">
      <label class="u-s19" for="${id}">Curso</label>
      <select class="u-s21" id="${id}">${cs.map(c => `<option value="${esc(c.id)}">${esc(c.nombre)}</option>`).join('')}</select>
    </div>`;
}

function autorYFecha(m) {
  return `
    <div class="u-s30">
      <span class="u-s31">${esc(m.author_name)}</span>
      <span class="u-s32">${formatDate(m.created_at)}${m.editado ? ' · editado' : ''}</span>
      ${m.fijado ? '<span class="cv-badge">📌 Fijado</span>' : ''}
      ${m.oculto ? '<span class="cv-badge cv-badge-warn">Oculto para el curso</span>' : ''}
    </div>`;
}

function errorAmigable(error) {
  const m = error?.message || '';
  if (/row-level security|permission denied|42501/.test(m + (error?.code || ''))) return 'No tenés permiso para hacer eso.';
  return m || 'intentá de nuevo.';
}

// Edición en línea (sin prompt): el cuerpo pasa a ser un textarea con Guardar/Cancelar
function abrirEdicion(el) {
  const caja = document.getElementById('cv-body-' + el.dataset.id);
  if (!caja || caja.dataset.editando) return;
  caja.dataset.editando = '1';
  const actual = caja.textContent;
  caja.innerHTML = `
    <label class="sr-only" for="cv-edit-${esc(el.dataset.id)}">Editar mensaje</label>
    <textarea class="u-s36" id="cv-edit-${esc(el.dataset.id)}" rows="4" maxlength="${LARGO_MSG}"></textarea>
    <div class="cv-acciones">
      <button class="btn-primary" type="button" data-action="${el.dataset.save}" data-id="${esc(el.dataset.id)}">Guardar</button>
      <button class="btn-outline" type="button" data-action="${el.dataset.cancel}">Cancelar</button>
    </div>`;
  const ta = document.getElementById('cv-edit-' + el.dataset.id);
  ta.value = actual;
  ta.focus();
}

// ─────────────── FOROS ───────────────
function renderForos() {
  return `
    <div class="page-header"><h1>Foros</h1></div>
    ${cursosDocente().length ? `
      <details class="u-s18 cv-nuevo">
        <summary>＋ Abrir un foro nuevo</summary>
        ${selectorCurso('fo-curso')}
        <div class="u-s11">
          <label class="u-s19" for="fo-titulo">Título</label>
          <input class="u-s20" id="fo-titulo" type="text" maxlength="200" placeholder="Ej: ¿Qué estamos leyendo?">
        </div>
        <div class="u-s11">
          <label class="u-s19" for="fo-consigna">Consigna</label>
          <textarea class="u-s36" id="fo-consigna" rows="3" maxlength="5000" placeholder="Contá de qué se trata el foro"></textarea>
        </div>
        <button class="btn-primary" type="button" data-action="foro-crear">Abrir foro</button>
      </details>` : ''}
    <div id="foros-lista"><p class="u-s9">Cargando…</p></div>`;
}

async function cargarForos() {
  await cargarMisCursosConNombre();
  const { data, error } = await db.from('foros').select('id, curso_id, titulo, consigna, estado, created_at')
    .order('created_at', { ascending: false }).limit(100);
  const lista = document.getElementById('foros-lista');
  if (!lista) return;
  if (error) { console.warn('No se pudieron cargar los foros', error); lista.innerHTML = NO_DISPONIBLE; return; }
  lista.innerHTML = (data || []).length ? data.map(f => `
    <div class="card" data-action="foro-abrir" data-id="${esc(f.id)}" role="link" tabindex="0">
      <div class="u-s12">
        <span class="cv-badge${f.estado === 'cerrado' ? ' cv-badge-warn' : ''}">${f.estado === 'cerrado' ? '🔒 Cerrado' : '💬 Abierto'}</span>
        ${nombreCurso(f.curso_id) ? `<span class="u-s14">${esc(nombreCurso(f.curso_id))}</span>` : ''}
        <span class="u-s14">${formatDate(f.created_at)}</span>
      </div>
      <h2>${esc(f.titulo)}</h2>
      <div class="text-excerpt">${esc(f.consigna)}</div>
    </div>`).join('') : '<p class="u-s9">Todavía no hay foros en tus cursos.</p>';
}

async function crearForo() {
  const curso_id = document.getElementById('fo-curso')?.value;
  const titulo   = document.getElementById('fo-titulo').value.trim();
  const consigna = document.getElementById('fo-consigna').value.trim();
  if (!curso_id) { alert('No sos docente de ningún curso.'); return; }
  if (!titulo || titulo.length > 200) { alert('El título tiene que tener entre 1 y 200 caracteres.'); return; }
  const { data, error } = await db.from('foros').insert([{ curso_id, titulo, consigna, creado_por: currentUser.id }]).select('id').single();
  if (error) { alert('No se pudo abrir el foro: ' + errorAmigable(error)); return; }
  abrirForo(data.id);
}

function mensajeHtml(m, f, puedeModerar, respuestas) {
  const mio = m.author_id === currentUser.id;
  const abierto = f.estado === 'abierto';
  return `
    <div class="comment cv-msg${m.parent_id ? ' cv-respuesta' : ''}">
      ${autorYFecha(m)}
      <div id="cv-body-${esc(m.id)}">${textoPlano(m.body)}</div>
      <div class="cv-acciones">
        ${!m.parent_id && abierto ? `<button class="btn-outline" type="button" data-action="foro-responder" data-id="${esc(m.id)}">↩️ Responder</button>` : ''}
        ${mio && abierto ? `<button class="btn-outline" type="button" data-action="cv-editar" data-id="${esc(m.id)}" data-save="foro-guardar" data-cancel="foro-refrescar">✏️ Editar</button>` : ''}
        ${puedeModerar && !m.parent_id ? `<button class="btn-outline" type="button" data-action="foro-fijar" data-id="${esc(m.id)}" data-on="${m.fijado ? '1' : '0'}">${m.fijado ? 'Desfijar' : '📌 Fijar'}</button>` : ''}
        ${puedeModerar ? `<button class="btn-outline" type="button" data-action="foro-ocultar" data-id="${esc(m.id)}" data-on="${m.oculto ? '1' : '0'}">${m.oculto ? '👁️ Mostrar' : '🙈 Ocultar'}</button>` : ''}
        ${mio || puedeModerar ? `<button class="btn-outline u-s27" type="button" data-action="foro-borrar-msg" data-id="${esc(m.id)}">🗑️ Borrar</button>` : ''}
      </div>
      <div id="cv-resp-${esc(m.id)}"></div>
      ${(respuestas || []).map(r => mensajeHtml(r, f, puedeModerar)).join('')}
    </div>`;
}

async function abrirForo(id) {
  foroActual = id;
  if (!misCursos.length) await cargarMisCursosConNombre();
  const [{ data: f, error }, { data: msgs, error: mErr }] = await Promise.all([
    db.from('foros').select('id, curso_id, titulo, consigna, estado, created_at').eq('id', id).maybeSingle(),
    db.from('foro_mensajes').select('id, foro_id, parent_id, author_id, author_name, body, fijado, oculto, editado, created_at')
      .eq('foro_id', id).order('created_at', { ascending: true }).limit(500)
  ]);
  if (error || !f) { alert('No se encontró el foro (o no tenés acceso).'); navigate('foros'); return; }
  if (mErr) console.warn('No se pudieron cargar los mensajes', mErr);
  const puedeModerar = modera(f.curso_id);
  const todos = msgs || [];
  const principales = todos.filter(m => !m.parent_id)
    .sort((a, b) => (b.fijado - a.fijado) || (new Date(a.created_at) - new Date(b.created_at)));
  const ca = document.getElementById('content-area');
  ca.innerHTML = `
    <button class="btn-outline u-s11" type="button" data-action="navigate" data-arg="foros">← Volver</button>
    <div class="u-s23">
      <div class="u-s12">
        <span class="cv-badge${f.estado === 'cerrado' ? ' cv-badge-warn' : ''}">${f.estado === 'cerrado' ? '🔒 Cerrado' : '💬 Abierto'}</span>
        ${nombreCurso(f.curso_id) ? `<span class="u-s14">${esc(nombreCurso(f.curso_id))}</span>` : ''}
      </div>
      <h1 class="u-s24">${esc(f.titulo)}</h1>
      ${f.consigna ? textoPlano(f.consigna) : ''}
      <div class="cv-acciones">
        <button class="btn-outline" type="button" data-action="foro-refrescar">↻ Actualizar</button>
        ${puedeModerar ? `
          <button class="btn-outline" type="button" data-action="foro-estado" data-id="${esc(f.id)}" data-on="${f.estado === 'abierto' ? '1' : '0'}">${f.estado === 'abierto' ? '🔒 Cerrar foro' : '🔓 Reabrir foro'}</button>
          <button class="btn-outline u-s27" type="button" data-action="foro-borrar" data-id="${esc(f.id)}">🗑️ Eliminar foro</button>` : ''}
      </div>
    </div>
    <div class="u-s18">
      <h3 class="u-s29">Mensajes (${todos.length})</h3>
      ${principales.length ? principales.map(m => mensajeHtml(m, f, puedeModerar, todos.filter(r => r.parent_id === m.id))).join('')
        : '<p class="u-s34">Todavía no hay mensajes. ¡Arrancá vos!</p>'}
      ${f.estado === 'abierto' ? `
        <h4 class="u-s35">Escribir en el foro</h4>
        <label class="sr-only" for="foro-body">Tu mensaje</label>
        <textarea class="u-s36" id="foro-body" rows="4" maxlength="${LARGO_MSG}" placeholder="Escribí tu mensaje…"></textarea>
        <button class="btn-primary u-s37" type="button" data-action="foro-publicar">Publicar</button>`
      : '<p class="u-s9">El foro está cerrado: se puede leer pero no escribir.</p>'}
    </div>`;
  ca.scrollTop = 0;
}

function abrirRespuesta(el) {
  const caja = document.getElementById('cv-resp-' + el.dataset.id);
  if (!caja || caja.innerHTML) return;
  caja.innerHTML = `
    <label class="sr-only" for="resp-${esc(el.dataset.id)}">Tu respuesta</label>
    <textarea class="u-s36" id="resp-${esc(el.dataset.id)}" rows="3" maxlength="${LARGO_MSG}" placeholder="Tu respuesta…"></textarea>
    <button class="btn-primary" type="button" data-action="${el.dataset.action === 'foro-responder' ? 'foro-publicar' : 'debate-argumentar'}" data-parent="${esc(el.dataset.id)}">Responder</button>`;
  document.getElementById('resp-' + el.dataset.id).focus();
}

function validarCuerpo(body) {
  if (!body) { alert('Escribí algo antes de enviar.'); return false; }
  if (body.length > LARGO_MSG) { alert(`El mensaje no puede superar los ${LARGO_MSG} caracteres.`); return false; }
  return true;
}

async function publicarEnForo(el) {
  const parent_id = el.dataset.parent || null;
  const ta = document.getElementById(parent_id ? 'resp-' + parent_id : 'foro-body');
  const body = (ta?.value || '').trim();
  if (!validarCuerpo(body)) return;
  el.disabled = true;
  const { error } = await db.from('foro_mensajes').insert([{ foro_id: foroActual, parent_id, body }]);
  if (error) { alert('No se pudo publicar: ' + errorAmigable(error)); el.disabled = false; return; }
  abrirForo(foroActual);
}

async function actualizarMensaje(id, cambios) {
  const { data, error } = await db.from('foro_mensajes').update(cambios).eq('id', id).select('id');
  if (error) { alert('No se pudo guardar: ' + errorAmigable(error)); return; }
  if (!data || !data.length) alert('No tenés permiso para cambiar este mensaje.');
  abrirForo(foroActual);
}

async function guardarMensajeForo(el) {
  const body = (document.getElementById('cv-edit-' + el.dataset.id)?.value || '').trim();
  if (validarCuerpo(body)) actualizarMensaje(el.dataset.id, { body });
}

async function borrarMensajeForo(id) {
  if (!confirm('¿Borrar este mensaje? También se borran sus respuestas.')) return;
  const { data, error } = await db.from('foro_mensajes').delete().eq('id', id).select('id');
  if (error || !data || !data.length) { alert('No se pudo borrar: ' + (error ? errorAmigable(error) : 'no tenés permiso.')); return; }
  abrirForo(foroActual);
}

async function cambiarEstadoForo(el) {
  const cerrar = el.dataset.on === '1';
  const { data, error } = await db.from('foros').update({ estado: cerrar ? 'cerrado' : 'abierto' }).eq('id', el.dataset.id).select('id');
  if (error || !data || !data.length) { alert('No se pudo cambiar el foro: ' + (error ? errorAmigable(error) : 'no tenés permiso.')); return; }
  abrirForo(el.dataset.id);
}

async function borrarForo(id) {
  if (!confirm('¿Eliminar el foro con todos sus mensajes? No se puede deshacer.')) return;
  const { data, error } = await db.from('foros').delete().eq('id', id).select('id');
  if (error || !data || !data.length) { alert('No se pudo eliminar: ' + (error ? errorAmigable(error) : 'no tenés permiso.')); return; }
  navigate('foros');
}

// ─────────────── SALA DE DEBATES ───────────────
function renderDebates() {
  return `
    <div class="page-header"><h1>Sala de debates</h1></div>
    <p class="u-s9 u-s11">Elegí una postura, defendela con argumentos y respondé a los de la otra. Acá no gana nadie: marcá "me hizo pensar" cuando un argumento te mueva.</p>
    ${cursosDocente().length ? `
      <details class="u-s18 cv-nuevo">
        <summary>＋ Plantear un debate nuevo</summary>
        ${selectorCurso('de-curso')}
        <div class="u-s11">
          <label class="u-s19" for="de-pregunta">Pregunta</label>
          <input class="u-s20" id="de-pregunta" type="text" maxlength="300" placeholder="Ej: ¿Debería ser obligatorio el uniforme?">
        </div>
        <div class="u-s11">
          <label class="u-s19" for="de-descripcion">Contexto (opcional)</label>
          <textarea class="u-s36" id="de-descripcion" rows="3" maxlength="5000"></textarea>
        </div>
        <div class="u-s11">
          <label class="u-s19" for="de-posturas">Posturas (una por línea, de 2 a 6)</label>
          <textarea class="u-s36" id="de-posturas" rows="3" maxlength="800" placeholder="Sí&#10;No"></textarea>
        </div>
        <button class="btn-primary" type="button" data-action="debate-crear">Abrir debate</button>
      </details>` : ''}
    <div id="debates-lista"><p class="u-s9">Cargando…</p></div>`;
}

async function cargarDebates() {
  await cargarMisCursosConNombre();
  const { data, error } = await db.from('debates').select('id, curso_id, pregunta, estado, sintesis_destacada, created_at')
    .order('created_at', { ascending: false }).limit(100);
  const lista = document.getElementById('debates-lista');
  if (!lista) return;
  if (error) { console.warn('No se pudieron cargar los debates', error); lista.innerHTML = NO_DISPONIBLE; return; }
  const mios = (data || []).filter(d => misCursos.some(c => c.id === d.curso_id) || esAdmin(currentUser));
  lista.innerHTML = mios.length ? mios.map(d => `
    <div class="card" data-action="debate-abrir" data-id="${esc(d.id)}" role="link" tabindex="0">
      <div class="u-s12">
        <span class="cv-badge${d.estado === 'cerrado' ? ' cv-badge-warn' : ''}">${d.estado === 'cerrado' ? '🔒 Cerrado' : '⚖️ Abierto'}</span>
        ${d.sintesis_destacada ? '<span class="u-s13">⭐ Síntesis destacada</span>' : ''}
        ${nombreCurso(d.curso_id) ? `<span class="u-s14">${esc(nombreCurso(d.curso_id))}</span>` : ''}
        <span class="u-s14">${formatDate(d.created_at)}</span>
      </div>
      <h2>${esc(d.pregunta)}</h2>
    </div>`).join('') : '<p class="u-s9">Todavía no hay debates en tus cursos.</p>';
}

async function crearDebate() {
  const p_curso = document.getElementById('de-curso')?.value;
  const p_pregunta = document.getElementById('de-pregunta').value.trim();
  const p_descripcion = document.getElementById('de-descripcion').value.trim();
  const p_posturas = [...new Set(document.getElementById('de-posturas').value.split('\n').map(s => s.trim()).filter(Boolean))];
  if (!p_curso) { alert('No sos docente de ningún curso.'); return; }
  if (!p_pregunta) { alert('Escribí la pregunta del debate.'); return; }
  if (p_posturas.length < 2 || p_posturas.length > 6) { alert('Poné entre 2 y 6 posturas distintas, una por línea.'); return; }
  if (p_posturas.some(p => p.length > 120)) { alert('Cada postura puede tener hasta 120 caracteres.'); return; }
  const { data, error } = await db.rpc('crear_debate', { p_curso, p_pregunta, p_descripcion, p_posturas });
  if (error) { alert('No se pudo abrir el debate: ' + errorAmigable(error)); return; }
  abrirDebate(data);
}

function argumentoHtml(a, d, puedeModerar, respuestas, posturas) {
  const mio = a.author_id === currentUser.id;
  const abierto = d.estado === 'abierto';
  const reacc = a.debate_reacciones || [];
  const yaReaccione = reacc.some(r => r.user_id === currentUser.id);
  const postura = a.postura_id ? posturas.find(p => p.id === a.postura_id)?.nombre : null;
  return `
    <div class="comment cv-msg${a.parent_id ? ' cv-respuesta' : ''}">
      ${autorYFecha(a)}
      ${a.parent_id && postura ? `<span class="cv-badge">desde "${esc(postura)}"</span>` : ''}
      <div id="cv-body-${esc(a.id)}">${textoPlano(a.body)}</div>
      <div class="cv-acciones">
        ${mio ? (reacc.length ? `<span class="u-s32">💭 A ${reacc.length} ${reacc.length === 1 ? 'persona le' : 'personas les'} hizo pensar</span>` : '')
          : `<button class="btn-outline${yaReaccione ? ' btn-liked' : ''}" type="button" aria-pressed="${yaReaccione}" data-action="debate-pensar" data-id="${esc(a.id)}" data-on="${yaReaccione ? '1' : '0'}">💭 ${yaReaccione ? 'Me hizo pensar ✓' : 'Me hizo pensar'}</button>`}
        ${!a.parent_id && abierto ? `<button class="btn-outline" type="button" data-action="debate-replicar" data-id="${esc(a.id)}">↩️ Replicar</button>` : ''}
        ${mio && abierto ? `<button class="btn-outline" type="button" data-action="cv-editar" data-id="${esc(a.id)}" data-save="debate-guardar" data-cancel="debate-refrescar">✏️ Editar</button>` : ''}
        ${puedeModerar ? `<button class="btn-outline" type="button" data-action="debate-ocultar" data-id="${esc(a.id)}" data-on="${a.oculto ? '1' : '0'}">${a.oculto ? '👁️ Mostrar' : '🙈 Ocultar'}</button>` : ''}
        ${mio || puedeModerar ? `<button class="btn-outline u-s27" type="button" data-action="debate-borrar-arg" data-id="${esc(a.id)}">🗑️ Borrar</button>` : ''}
      </div>
      <div id="cv-resp-${esc(a.id)}"></div>
      ${(respuestas || []).map(r => argumentoHtml(r, d, puedeModerar, null, posturas)).join('')}
    </div>`;
}

async function abrirDebate(id) {
  debateActual = id;
  if (!misCursos.length) await cargarMisCursosConNombre();
  const [{ data: d, error }, { data: posturas }, { data: eleccion }, { data: args, error: aErr }] = await Promise.all([
    db.from('debates').select('id, curso_id, pregunta, descripcion, estado, sintesis, sintesis_destacada, created_at, cerrado_en').eq('id', id).maybeSingle(),
    db.from('debate_posturas').select('id, nombre, orden').eq('debate_id', id).order('orden'),
    db.from('debate_elecciones').select('postura_id').eq('debate_id', id).eq('user_id', currentUser.id).maybeSingle(),
    db.from('debate_argumentos').select('id, debate_id, postura_id, parent_id, author_id, author_name, body, oculto, editado, created_at, debate_reacciones(user_id)')
      .eq('debate_id', id).order('created_at', { ascending: true }).limit(500)
  ]);
  if (error || !d) { alert('No se encontró el debate (o no tenés acceso).'); navigate('debates'); return; }
  if (aErr) console.warn('No se pudieron cargar los argumentos', aErr);
  const ps = posturas || [];
  const todos = args || [];
  const puedeModerar = modera(d.curso_id);
  const abierto = d.estado === 'abierto';
  const miPostura = eleccion?.postura_id || null;
  const principales = todos.filter(a => !a.parent_id);
  const hilo = a => argumentoHtml(a, d, puedeModerar, todos.filter(r => r.parent_id === a.id), ps);
  const columnas = ps.map(p => `
    <section class="cv-postura" aria-labelledby="pos-${esc(p.id)}">
      <h3 class="u-s29" id="pos-${esc(p.id)}">${esc(p.nombre)}</h3>
      ${principales.filter(a => a.postura_id === p.id).map(hilo).join('') || '<p class="u-s34">Sin argumentos todavía.</p>'}
    </section>`).join('');
  const intervenciones = principales.filter(a => !a.postura_id);
  const ca = document.getElementById('content-area');
  ca.innerHTML = `
    <button class="btn-outline u-s11" type="button" data-action="navigate" data-arg="debates">← Volver</button>
    <div class="u-s23">
      <div class="u-s12">
        <span class="cv-badge${abierto ? '' : ' cv-badge-warn'}">${abierto ? '⚖️ Abierto' : '🔒 Cerrado'}</span>
        ${d.sintesis_destacada ? '<span class="u-s13">⭐ Síntesis destacada en la portada</span>' : ''}
        ${nombreCurso(d.curso_id) ? `<span class="u-s14">${esc(nombreCurso(d.curso_id))}</span>` : ''}
      </div>
      <h1 class="u-s24">${esc(d.pregunta)}</h1>
      ${d.descripcion ? textoPlano(d.descripcion) : ''}
      <div class="cv-acciones">
        <button class="btn-outline" type="button" data-action="debate-refrescar">↻ Actualizar</button>
        ${puedeModerar ? `
          <button class="btn-outline" type="button" data-action="debate-estado" data-id="${esc(d.id)}" data-on="${abierto ? '1' : '0'}">${abierto ? '🔒 Cerrar debate' : '🔓 Reabrir debate'}</button>
          <button class="btn-outline u-s27" type="button" data-action="debate-borrar" data-id="${esc(d.id)}">🗑️ Eliminar debate</button>` : ''}
      </div>
    </div>
    ${!abierto ? `
      <div class="u-s18 u-s11">
        <h3 class="u-s29">Síntesis del debate</h3>
        ${puedeModerar ? `
          <label class="sr-only" for="de-sintesis">Síntesis</label>
          <textarea class="u-s36" id="de-sintesis" rows="5" maxlength="10000" placeholder="¿Qué se aprendió? ¿Qué argumentos movieron al grupo?"></textarea>
          <div class="cv-acciones">
            <button class="btn-primary" type="button" data-action="debate-sintesis">Guardar síntesis</button>
            ${d.sintesis ? `<button class="btn-outline" type="button" data-action="debate-destacar" data-on="${d.sintesis_destacada ? '1' : '0'}">${d.sintesis_destacada ? 'Quitar de la portada' : '⭐ Destacar en la portada'}</button>` : ''}
          </div>
          <p class="u-s32">Si la destacás, en la portada pública se ven solo la pregunta y esta síntesis (sin nombres ni argumentos).</p>`
        : (d.sintesis ? textoPlano(d.sintesis) : '<p class="u-s9">El docente todavía no escribió la síntesis.</p>')}
      </div>` : ''}
    <div class="u-s18 u-s11">
      <h3 class="u-s29">Tu postura</h3>
      <div class="cv-acciones" role="group" aria-label="Elegí tu postura">
        ${ps.map(p => `<button class="btn-outline${p.id === miPostura ? ' is-active' : ''}" type="button" aria-pressed="${p.id === miPostura}"
          data-action="debate-elegir" data-id="${esc(p.id)}" ${abierto ? '' : 'disabled'}>${esc(p.nombre)}</button>`).join('')}
      </div>
      ${abierto ? (miPostura || puedeModerar ? `
        <label class="u-s19" for="debate-body">${miPostura ? 'Tu argumento' : 'Intervención del docente (sin postura)'}</label>
        <textarea class="u-s36" id="debate-body" rows="4" maxlength="${LARGO_MSG}" placeholder="Defendé tu postura con un ejemplo…"></textarea>
        <button class="btn-primary u-s37" type="button" data-action="debate-argumentar">Publicar argumento</button>`
        : '<p class="u-s9">Elegí una postura para poder argumentar. La podés cambiar mientras el debate esté abierto.</p>')
      : '<p class="u-s9">El debate está cerrado: se puede leer pero no participar.</p>'}
    </div>
    ${intervenciones.length ? `<div class="u-s18 u-s11"><h3 class="u-s29">Intervenciones del docente</h3>${intervenciones.map(hilo).join('')}</div>` : ''}
    <div class="cv-posturas">${columnas}</div>`;
  const ts = document.getElementById('de-sintesis');
  if (ts) ts.value = d.sintesis || '';
  ca.scrollTop = 0;
}

async function elegirPostura(posturaId) {
  const { error } = await db.from('debate_elecciones')
    .upsert([{ debate_id: debateActual, user_id: currentUser.id, postura_id: posturaId }], { onConflict: 'debate_id,user_id' });
  if (error) { alert('No se pudo elegir la postura: ' + errorAmigable(error)); return; }
  abrirDebate(debateActual);
}

async function argumentar(el) {
  const parent_id = el.dataset.parent || null;
  const ta = document.getElementById(parent_id ? 'resp-' + parent_id : 'debate-body');
  const body = (ta?.value || '').trim();
  if (!validarCuerpo(body)) return;
  el.disabled = true;
  const { error } = await db.from('debate_argumentos').insert([{ debate_id: debateActual, parent_id, body }]);
  if (error) { alert('No se pudo publicar: ' + errorAmigable(error)); el.disabled = false; return; }
  abrirDebate(debateActual);
}

async function actualizarArgumento(id, cambios) {
  const { data, error } = await db.from('debate_argumentos').update(cambios).eq('id', id).select('id');
  if (error) { alert('No se pudo guardar: ' + errorAmigable(error)); return; }
  if (!data || !data.length) alert('No tenés permiso para cambiar este argumento.');
  abrirDebate(debateActual);
}

async function guardarArgumento(el) {
  const body = (document.getElementById('cv-edit-' + el.dataset.id)?.value || '').trim();
  if (validarCuerpo(body)) actualizarArgumento(el.dataset.id, { body });
}

async function borrarArgumento(id) {
  if (!confirm('¿Borrar este argumento? También se borran sus réplicas.')) return;
  const { data, error } = await db.from('debate_argumentos').delete().eq('id', id).select('id');
  if (error || !data || !data.length) { alert('No se pudo borrar: ' + (error ? errorAmigable(error) : 'no tenés permiso.')); return; }
  abrirDebate(debateActual);
}

async function meHizoPensar(el) {
  const ya = el.dataset.on === '1';
  const q = ya
    ? db.from('debate_reacciones').delete().eq('argumento_id', el.dataset.id).eq('user_id', currentUser.id)
    : db.from('debate_reacciones').insert([{ argumento_id: el.dataset.id, user_id: currentUser.id }]);
  const { error } = await q;
  if (error && error.code !== '23505') { alert('No se pudo guardar: ' + errorAmigable(error)); return; }
  abrirDebate(debateActual);
}

async function actualizarDebate(cambios) {
  const { data, error } = await db.from('debates').update(cambios).eq('id', debateActual).select('id');
  if (error || !data || !data.length) { alert('No se pudo guardar: ' + (error ? errorAmigable(error) : 'no tenés permiso.')); return; }
  abrirDebate(debateActual);
}

async function cambiarEstadoDebate(el) {
  const cerrar = el.dataset.on === '1';
  if (cerrar && !confirm('¿Cerrar el debate? Nadie podrá argumentar ni cambiar de postura, y vas a poder escribir la síntesis.')) return;
  if (!cerrar && !confirm('¿Reabrir el debate? Si la síntesis estaba en la portada, se quita.')) return;
  actualizarDebate({ estado: cerrar ? 'cerrado' : 'abierto' });
}

function guardarSintesis() {
  const sintesis = document.getElementById('de-sintesis').value.trim();
  if (sintesis.length > 10000) { alert('La síntesis puede tener hasta 10000 caracteres.'); return; }
  actualizarDebate(sintesis ? { sintesis } : { sintesis: null, sintesis_destacada: false });
}

async function borrarDebate(id) {
  if (!confirm('¿Eliminar el debate con sus argumentos? No se puede deshacer.')) return;
  const { data, error } = await db.from('debates').delete().eq('id', id).select('id');
  if (error || !data || !data.length) { alert('No se pudo eliminar: ' + (error ? errorAmigable(error) : 'no tenés permiso.')); return; }
  navigate('debates');
}

// ─────────────── PORTADA: síntesis destacadas (anon) ───────────────
async function loadLandingSintesis() {
  const seccion = document.getElementById('lp-debates');
  if (!seccion) return;
  // anon solo puede leer estas columnas y solo de debates con síntesis destacada
  const { data, error } = await db.from('debates').select('id, pregunta, sintesis, cerrado_en')
    .eq('sintesis_destacada', true).order('cerrado_en', { ascending: false }).limit(6);
  if (error) { console.warn('No se pudieron cargar las síntesis', error); seccion.classList.add('hidden'); return; }
  if (!data || !data.length) { seccion.classList.add('hidden'); return; }
  document.getElementById('landing-debates').innerHTML = data.map(d => {
    const s = (d.sintesis || '').trim();
    return `
    <article class="lp-card">
      <span class="lp-card-type">Debate</span>
      <h3>${esc(d.pregunta)}</h3>
      <p>${esc(s.slice(0, 280))}${s.length > 280 ? '…' : ''}</p>
    </article>`;
  }).join('');
  seccion.classList.remove('hidden');
}

// ─────────────── Registro en el enrutador y las acciones ───────────────
Object.assign(PAGINAS, { foros: renderForos, debates: renderDebates });
Object.assign(AL_ENTRAR, { foros: cargarForos, debates: cargarDebates });
Object.assign(ACCIONES, {
  'foro-crear':        ()  => crearForo(),
  'foro-abrir':        el  => abrirForo(el.dataset.id),
  'foro-refrescar':    ()  => abrirForo(foroActual),
  'foro-publicar':     el  => publicarEnForo(el),
  'foro-responder':    el  => abrirRespuesta(el),
  'foro-guardar':      el  => guardarMensajeForo(el),
  'foro-fijar':        el  => actualizarMensaje(el.dataset.id, { fijado: el.dataset.on !== '1' }),
  'foro-ocultar':      el  => actualizarMensaje(el.dataset.id, { oculto: el.dataset.on !== '1' }),
  'foro-borrar-msg':   el  => borrarMensajeForo(el.dataset.id),
  'foro-estado':       el  => cambiarEstadoForo(el),
  'foro-borrar':       el  => borrarForo(el.dataset.id),
  'cv-editar':         el  => abrirEdicion(el),
  'debate-crear':      ()  => crearDebate(),
  'debate-abrir':      el  => abrirDebate(el.dataset.id),
  'debate-refrescar':  ()  => abrirDebate(debateActual),
  'debate-elegir':     el  => elegirPostura(el.dataset.id),
  'debate-argumentar': el  => argumentar(el),
  'debate-replicar':   el  => abrirRespuesta(el),
  'debate-guardar':    el  => guardarArgumento(el),
  'debate-ocultar':    el  => actualizarArgumento(el.dataset.id, { oculto: el.dataset.on !== '1' }),
  'debate-borrar-arg': el  => borrarArgumento(el.dataset.id),
  'debate-pensar':     el  => meHizoPensar(el),
  'debate-estado':     el  => cambiarEstadoDebate(el),
  'debate-sintesis':   ()  => guardarSintesis(),
  'debate-destacar':   el  => actualizarDebate({ sintesis_destacada: el.dataset.on !== '1' }),
  'debate-borrar':     el  => borrarDebate(el.dataset.id)
});
