# E2E local (no toca producción)

1. Postgres 17 local con dos bases: `e2e` (baseline + seed + migraciones) y `e2e_old`
   (baseline + seed, sin migrar), usando `supabase/tests/00_stub_supabase.sql`,
   `01_baseline_prod.sql` y `02_seed.sql`. Rol `authenticator` (login, noinherit) con
   `grant anon, authenticated to authenticator`.
2. PostgREST 12 en :3000 (e2e) y :3001 (e2e_old), `db-schemas=public`, `db-anon-role=anon`,
   `jwt-secret` = el de `server.js`.
3. `PORT=8080 PGRST=3000 node server.js` y `PORT=8081 PGRST=3001 node server.js`
   (sirve el repo con la CSP de vercel.json, cambiando solo el host de Supabase por localhost).
4. `npm i && BASE=http://localhost:8080 node e2e.js` y `BASE=http://localhost:8081 node e2e.js`
   (usa Chrome headless; la sesión se inyecta en localStorage con un JWT firmado localmente,
   así que el login real con Google NO se prueba acá).

## Foros y sala de debates (`e2e_foros.js`)

- `e2e` = baseline + seed + **todas** las migraciones (incluye 20261116200*); `e2e_old` = baseline + seed +
  security-fixes-nov (como prod hoy, sin foros).
- `BASE=http://localhost:8080 FD=1 node e2e_foros.js` (flujos completos por rol, CSP, XSS como texto, celular 390px)
- `BASE=http://localhost:8081 FD=0 node e2e_foros.js` (frontend nuevo contra la base sin las migraciones nuevas)
- `e2e.js` acepta `MIGRADA=1` para correrlo contra `e2e_old` ya migrada con security-fixes-nov.
- Cada suite se corre sobre una base recién creada (la app une a todos al curso GENERAL al entrar,
  así que los datos de una corrida cambian lo que ve la siguiente).
