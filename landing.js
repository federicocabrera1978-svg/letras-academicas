// Inicio público: microescritura local (no se guarda), consignas rotativas y login
(function () {
  const consignas = [
    'Escribí 3 líneas sobre el olor de tu casa un domingo.',
    'Contá en 3 líneas un ruido que te despierta.',
    'Describí tus manos sin usar la palabra "mano".',
    'Escribí 3 líneas a alguien que no ves hace mucho.',
    'Contá el camino a la escuela como si fuera un viaje.',
    'Tres líneas sobre algo que aprendiste equivocándote.'
  ];
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const promptEl = document.getElementById('lp-prompt-text');
  const area = document.getElementById('lp-try');
  const count = document.getElementById('lp-count');
  const publicar = document.getElementById('lp-publicar');
  const otra = document.getElementById('lp-otra');
  if (!promptEl || !area) return;

  let i = 0, timer = null;
  function escribir(txt) {
    clearInterval(timer);
    if (reduce) { promptEl.textContent = txt; return; }
    let n = 0; promptEl.textContent = '';
    timer = setInterval(() => {
      promptEl.textContent = txt.slice(0, ++n);
      if (n >= txt.length) clearInterval(timer);
    }, 32);
  }
  otra.addEventListener('click', () => { i = (i + 1) % consignas.length; escribir(consignas[i]); area.focus(); });
  escribir(consignas[0]);

  area.addEventListener('input', () => {
    const w = area.value.trim() ? area.value.trim().split(/\s+/).length : 0;
    count.textContent = w + (w === 1 ? ' palabra' : ' palabras');
    publicar.disabled = w < 3;
  });

  // Todos los botones "js-login" disparan el login con Google existente
  document.addEventListener('click', (e) => {
    const b = e.target.closest('.js-login');
    if (!b || b.disabled) return;
    document.getElementById('login-google-btn').click();
  });
})();
