# Arreglos de seguridad — noviembre 2026 (rama `security-fixes-nov`)

Base: revisión de código sobre `origin/master` a2a0c66. **Nada de esto está aplicado en producción**:
ni merge, ni deploy, ni migraciones. Todo queda para revisión y OK de Federico.

## Qué arregla cada cambio

| # | Hallazgo | Dónde |
|---|---|---|
| 1 | Cualquier docente podía borrar perfiles (incluido el admin, que volvía como alumno) | `supabase/migrations/…210100_f01_*`; `eliminarMiembro()` y botón en `index.js` |
| 3 | Docentes moderaban textos/comentarios de cualquier curso | `…210200_f03_*`; botones según docente del curso (`puedeModerar`) |
| 5 | `textos_proteger_campos` usaba `new.curso_id` (del cliente) para decidir destacar | `…210300_f05_*` |
| 2 | Autoría por `author_username`: un username reutilizado heredaba textos | `…210400_f02_*` (author_id/user_id + backfill + verificación); `supabase/verify/`; `esMio()` |
| 4 | Cualquier logueado veía todo (textos, comentarios, likes, perfiles) | `…210500_f04_*`; columnas explícitas de perfiles |
| 6 | Helpers SECURITY DEFINER invocables como RPC | `…210600_f06_*` (schema `private`, `search_path=''`) |
| 12 | `anon` tenía INSERT/UPDATE/DELETE | `…210700_f12_*`; la home pide solo columnas públicas |
| 7 | `onAuthStateChange` con await adentro; sin manejo de SIGNED_OUT / cambio de cuenta | `index.js` (`manejarAuth`, `cerrarApp`) |
| 8 | Alta de perfil sin revisar errores; username podía chocar | `index.js` (`obtenerOCrearPerfil`) + username fijado en servidor (f02) |
| 9 | Borrador: un intervalo nuevo por visita, clave compartida entre cuentas | `index.js` (`claveBorrador`, `detenerBorrador`, `borrarBorradores`) |
| 10 | Flujo implícito (tokens en la URL) | `flowType: 'pkce'` en `createClient` |
| 11 | `deleteText` con 3 DELETE sin errores; editar/destacar sin errores | `index.js` |
| 13 | CSP permitía cdn.jsdelivr.net | `vendor/` (mismos hashes SRI), `vercel.json` |
| 15 | Accesibilidad, unlike inexistente, `refreshData` traía todo | `index.html`, `index.css`, `index.js` |
| 14 | Contraseña del login viejo en el historial de git | **No se reescribió el historial** (ver abajo) |

Leaked password protection (advisor): no aplica mientras el único login sea Google; no se tocó.

### PKCE (10)
Según la guía oficial de Supabase (Auth → Sessions → PKCE flow), en el navegador funciona sin
backend: `signInWithOAuth` guarda el *code verifier* en el storage del cliente, Google/Supabase
redirigen a la misma URL con `?code=` y, con `detectSessionInUrl: true`, supabase-js lo canjea
solo. Límites: el canje tiene que ocurrir en el mismo navegador donde se empezó el login, el
código vence a los 5 minutos y es de un solo uso. `redirectTo` no cambió (`window.location.origin`),
así que no hace falta tocar las Redirect URLs de Supabase. La app borra `?code=` de la barra.

### 14 — historial de git
El historial conserva en texto plano la contraseña del login viejo. Reescribirlo
(`git filter-repo` + force-push) es destructivo y rompe los clones existentes, así que **no se
hizo**. Recomendación: si esa contraseña se usa en otro lado, cambiarla ya; reescribir el
historial solo si Federico lo pide explícitamente.

## Orden de despliegue (cuando haya OK)

El frontend nuevo funciona con la base **actual y con la migrada** (probado con E2E contra
ambas), así que conviene: **primero el frontend, después la base**.

1. Revisar y mergear el PR → Vercel despliega. Probar en producción: entrar, publicar, like/unlike,
   comentar. (Con la base sin migrar, "Eliminar miembro" muestra un error porque la RPC todavía no existe.)
2. Respaldo: `supabase db dump` (esquema + datos) o el backup del dashboard.
3. Correr `supabase/verify/verificar_autoria_antes.sql` (solo lectura): `sin_autor_identificable`
   tiene que dar 0 en textos, comentarios y likes. Si no, f02 abortaría: resolver esas filas antes.
4. Confirmar en Dashboard → Settings → API → *Exposed schemas* que `private` **no** está expuesto.
5. Aplicar las 7 migraciones **en orden**, cada una en una transacción (SQL editor o
   `apply_migration` con el mismo nombre). Ojo: `supabase db push` va a quejarse porque las 9
   migraciones previas de prod no están en el repo.
6. Correr `supabase/verify/verificar_autoria_despues.sql`: mismos totales que en el paso 3,
   `sin_author_id = 0` y `username_distinto = 0`.
7. Advisors de seguridad: deberían desaparecer los avisos de `es_admin`, `es_profesor`,
   `es_docente_curso`, `es_miembro_curso` y `mi_username`. Quedan a propósito `habilitar_docente`,
   `unirse_a_curso` y `eliminar_miembro` (RPC de la app, con chequeos adentro).
8. Probar como admin y como alumno.

## Rollback

* Base: `psql -1 -f supabase/rollback/rollback_security_fixes_nov.sql` (o pegarlo en el SQL editor
  dentro de `begin; … commit;`). Deja políticas, funciones, triggers y grants exactamente como
  estaban el 2026-11-10 (verificado comparando el catálogo). No borra textos/comentarios/likes/perfiles;
  quita las columnas nuevas `author_id`/`user_id` (author_username/user_username siguen completos).
* Frontend: *Instant Rollback* de Vercel al deploy anterior. No hace falta para revertir la base
  (el frontend nuevo funciona con las dos).

## Riesgos de bloqueo y cómo se mitigan

* **f02 aborta** si algún texto/comentario/like tiene un username sin perfil (hoy: 0 de 18/12/4).
  Aborta antes de cambiar nada (dentro de la transacción).
* **f04 restringe lecturas por curso**: hoy hay un solo curso (GENERAL) y los 7 perfiles son
  miembros, así que nadie debería notar diferencia. Cada login se une a GENERAL automáticamente.
* Borrar un usuario de `auth.users` que tenga textos ahora **falla** (FK sin cascade) en vez de
  borrar sus textos en silencio.
* "Eliminar miembro" borra el perfil y sus membresías, no sus textos; si esa persona vuelve a
  entrar con Google recupera su cuenta (misma id). Impedir reingresos requeriría restringir
  quién puede registrarse (fuera de este alcance).
* Fonts de Google siguen siendo externas (style-src fonts.googleapis.com / font-src gstatic).

## Qué se probó (local, sin tocar producción)

* `supabase/tests/run_local.sh` (Postgres 17 local): réplica del esquema de prod leída del catálogo
  (diferencia contra prod: solo paréntesis cosméticos en 2 CHECK), 69 asserts por rol, idempotencia
  (aplicar dos veces = mismo catálogo), rollback = catálogo original, aborto controlado de f02.
* `tests/e2e`: Chrome headless + PostgREST 12 local, con la CSP de `vercel.json`; 38 checks contra la
  base migrada y 35 contra la actual. Sin violaciones de CSP ni errores JS.
* **No probado**: el login real con Google/PKCE (en E2E la sesión se inyecta), Supabase Auth real,
  datos reales de producción (se usaron datos sintéticos) y el aspecto visual en móvil.
