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
