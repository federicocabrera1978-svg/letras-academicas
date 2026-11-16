# Foros y sala de debates (noviembre 2026)

PR `foros-debates` → `master`. **NO mergear ni aplicar en producción sin el OK de Federico.**

## Qué se agrega

**Foros por curso** (menú 💬 Foros)
- El docente del curso (o el admin) abre un foro con título, consigna y estado abierto/cerrado.
- Los miembros del curso publican y responden en hilos de un nivel.
- El docente fija y oculta mensajes, cierra/reabre y elimina el foro. No puede reescribir el texto de un alumno.
- El autor edita (queda "editado") y borra lo suyo mientras el foro está abierto.

**Sala de debates** (menú ⚖️ Debates)
- El docente plantea una pregunta con 2 a 6 posturas (`crear_debate`).
- Cada miembro elige una postura por debate y la puede cambiar mientras esté abierto.
- Argumentos en la columna de su postura y réplicas de un nivel (marcadas "desde «postura»").
- "💭 Me hizo pensar": una por persona y argumento, nunca sobre el propio. No hay conteo por postura,
  ni orden por reacciones, ni ganador. El número solo lo ve el autor del argumento.
- El docente puede intervenir sin postura y ocultar argumentos.
- Al cerrar, el docente escribe una síntesis y la puede destacar. En la portada pública
  ("Lo que dejaron los debates") se ve **solo la pregunta y la síntesis**. Nunca se muestran argumentos, nombres ni posturas elegidas.
  Reabrir el debate quita el destacado.

## Seguridad (mismo modelo que security-fixes-nov)
- RLS en las 7 tablas nuevas. Ve y escribe solo quien es miembro del curso, y el admin puede todo.
  Modera solo el docente **de ese curso** (`private.es_docente_curso`).
- anon no tiene privilegios sobre ninguna tabla nueva. Solo puede hacer `SELECT` de 5 columnas de `debates`
  (`id, pregunta, sintesis, sintesis_destacada, cerrado_en`) y únicamente donde `sintesis_destacada`.
- Helpers `SECURITY DEFINER` en `private` (no expuesto por la API), con `search_path = ''`.
  Los triggers de protección son `SECURITY INVOKER`.
- La autoría la asigna el servidor: `author_id = auth.uid()`, `author_name` sale del perfil, y en los debates
  `postura_id` es la elegida por el autor. El cliente no puede suplantarla ni auto-fijarse u ocultarse.
- Anti-abuso: máximo **10 mensajes por minuto por usuario**, sumando foros y debates (trigger
  `limitar_ritmo_conversacion`). Largos máximos por `CHECK`: título 200, consigna/mensaje/argumento 5000,
  pregunta 300, postura 120, síntesis 10000.
- `crear_debate` es `SECURITY INVOKER`: la autorización la hace RLS. Un trigger diferido exige 2 posturas
  aunque se inserte directo.
- Frontend: todo el contenido es texto plano con `esc()` y nunca se interpreta como HTML (más estricto que
  DOMPurify, que se sigue usando para los textos con formato). No hay estilos ni scripts en línea, así que la CSP de
  `vercel.json` queda **sin cambios**.

## Avisos en vivo
No se implementaron. Hay un botón **↻ Actualizar** en cada foro y debate. Para sumarlos con Supabase Realtime
(`postgres_changes`, que respeta RLS) habría que agregar las tablas a la publicación `supabase_realtime`.
Eso es un cambio aparte en prod y conviene medirlo primero (cada cambio evalúa RLS por suscriptor).
La CSP ya permite `wss://xjrdjesezseuofjoqpzn.supabase.co`.

## Archivos
- `supabase/migrations/20261116200100_fd01_helpers_ritmo.sql`, `…200200_fd02_foros.sql`, `…200300_fd03_debates.sql`
- `supabase/rollback/rollback_foros_debates.sql` (**borra** el contenido de foros y debates)
- `supabase/verify/verificar_foros_debates.sql` (solo lectura: todas las filas deben dar `true`)
- `supabase/tests/40_test_foros_debates.sql` y pasos 7–8 de `supabase/tests/run_local.sh`
- `conversacion.js`, `conversacion.css`, más cambios chicos en `index.js` e `index.html`
- `tests/e2e/e2e_foros.js`

## Pruebas (locales, no tocan producción)
- `supabase/tests/run_local.sh` sobre Postgres 17:
  - 99 asserts de foros y debates por rol: admin, profesor de su curso y de otro curso, alumnos de GENERAL y de OTRO, ex miembro y anon. Cubren lo permitido y lo denegado.
  - Siguen pasando los 69 asserts de seguridad anteriores con todo aplicado.
  - Las migraciones son idempotentes (el catálogo queda idéntico al re-aplicar).
  - El rollback deja el catálogo igual al estado previo, es idempotente y se puede volver a migrar.
  - Se arregló un detalle del paso 4: con `pipefail`, un FAIL podía informarse como OK.
- E2E en Chrome headless (PostgREST 12 local):
  - `e2e_foros.js`: 58 ok contra la base con foros y 8 ok contra la base como prod hoy (Foros/Debates muestran un aviso y nada se rompe).
  - `e2e.js` (regresión): 38 ok en las dos bases.
  - Sin violaciones de CSP ni errores JS. El HTML inyectado se muestra como texto. Se probó en 390 px sin scroll horizontal.
- **No probado**: login real con Google, Supabase Auth y PostgREST reales de prod, datos reales, celulares
  físicos, carga con muchos usuarios a la vez.

## Orden de despliegue (cuando Federico dé el OK)
Las migraciones son aditivas: no cambian nada de lo existente y el frontend actual las ignora. Por eso conviene
**migrar primero y publicar el código después**, así nadie ve la sección a medias.
1. Backup de la base (como en el PR #9).
2. Confirmar en Supabase → Settings → API que `private` sigue **sin** estar en los schemas expuestos.
3. Aplicar en orden, cada una en su transacción (SQL editor / `apply_migration`):
   `20261116200100_fd01_helpers_ritmo.sql` → `20261116200200_fd02_foros.sql` → `20261116200300_fd03_debates.sql`.
4. Correr `supabase/verify/verificar_foros_debates.sql`: todas las filas en `true`. Correr también los advisors de seguridad.
5. Merge del PR → deploy de Vercel. Verificar el deploy (Ready) y que la portada cargue sin errores.
6. Prueba de humo: como admin, abrir un foro y un debate de prueba en General. Como alumno, escribir, elegir postura
   y argumentar. Después cerrar, sintetizar y destacar, y ver la portada sin sesión. Al final, borrar el foro y el debate de prueba.
7. Si algo falla: revertir el merge en Vercel/GitHub y correr `rollback_foros_debates.sql` en una transacción (antes de que haya contenido real; si ya hay, backup primero).

## Riesgos y decisiones
- En prod hoy hay un solo curso (General) y **todos** los usuarios se unen a él al entrar. En la práctica,
  cualquiera con cuenta participa de los foros y debates de General. El límite real es quién puede iniciar sesión,
  igual que hoy con los textos.
- Quien se une a General con Google puede leer los foros y debates de General (mismo riesgo que ya está anotado:
  el alta no está restringida).
- `author_id` apunta a `auth.users` sin cascada, igual que en `textos`. Borrar un usuario de Supabase Auth que tenga
  mensajes falla hasta borrar o reasignar sus mensajes. `eliminar_miembro` no se ve afectado (borra el perfil y conserva los mensajes).
- La síntesis destacada es pública. Si el docente nombra alumnos ahí, esos nombres quedan visibles en la portada. La UI lo avisa al lado del botón.
- Borrar un mensaje o un argumento principal borra sus respuestas (cascada). La UI lo avisa en la confirmación.
- El límite de 10 por minuto es por usuario. No frena a muchas cuentas distintas (eso lo cubre el rate limit de Vercel, que hoy es de 1000/min).
