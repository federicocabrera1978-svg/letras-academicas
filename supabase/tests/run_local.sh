#!/usr/bin/env bash
# Pruebas locales de las migraciones (NO toca producción).
# Requiere un Postgres 17 local: PGHOST/PGPORT/PGUSER (superusuario).
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-letras_test}
P="psql -v ON_ERROR_STOP=1 -q -X"
run(){ $P -d "$DB" "$@" >/dev/null; }
fresh(){ $P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  for f in tests/00_stub_supabase.sql tests/01_baseline_prod.sql tests/02_seed.sql; do run -f "$f"; done; }
snapshot(){ $P -d "$DB" -At -f tests/30_snapshot_catalogo.sql; }

echo "1) baseline (réplica de prod) + verificación previa"; fresh
echo "   tabla|total|sin_autor_identificable"; $P -d "$DB" -At -f verify/verificar_autoria_antes.sql | sed "s/^/   /"
snapshot > /tmp/snap_baseline.txt
echo "2) migraciones en orden"; for f in migrations/*.sql; do run -1 -f "$f" 2>/dev/null; done
echo "   tabla|total|sin_author_id|username_distinto"; $P -d "$DB" -At -f verify/verificar_autoria_despues.sql | sed "s/^/   /"
snapshot > /tmp/snap_migrado.txt
echo "3) segunda pasada completa (idempotencia)"; for f in migrations/*.sql; do run -1 -f "$f" 2>/dev/null; done
snapshot > /tmp/snap_migrado2.txt
diff -u /tmp/snap_migrado.txt /tmp/snap_migrado2.txt || { echo FAIL idempotencia; exit 1; }; echo "   idéntico tras re-aplicar"
echo "4) pruebas de seguridad"; run -f tests/10_helpers.sql
$P -d "$DB" -f tests/20_test_seguridad.sql 2>&1 >/dev/null | grep -E "FAIL|ERROR" && exit 1 || echo "   $(grep -c "tests\.\(ok\|falla\)" tests/20_test_seguridad.sql) asserts OK"
echo "5) rollback desde estado migrado (base nueva)"; fresh
for f in migrations/*.sql; do run -1 -f "$f" 2>/dev/null; done
run -1 -f rollback/rollback_security_fixes_nov.sql 2>/dev/null
snapshot > /tmp/snap_rollback.txt
diff -u /tmp/snap_baseline.txt /tmp/snap_rollback.txt || { echo FAIL rollback; exit 1; }; echo "   rollback deja el catálogo igual al baseline (políticas, funciones, grants, triggers)"
echo "6) fallo controlado: texto con username sin perfil aborta f02 sin cambios"; fresh
$P -d "$DB" -c "insert into public.textos (title, author_username, author_name, type, body) values ('huérfano','nadie','Nadie','otro','x')" >/dev/null
for f in migrations/2026111021010*.sql migrations/2026111021020*.sql migrations/2026111021030*.sql; do run -1 -f "$f" 2>/dev/null; done
if run -1 -f migrations/20261110210400_f02_autoria_por_id.sql 2>/tmp/f02err; then echo "   FAIL: debió abortar"; exit 1; fi
grep -o "f02 abortada.*" /tmp/f02err | head -1
$P -d "$DB" -Atc "select '   columna author_id existe tras abortar: ' || exists(select 1 from information_schema.columns where table_name='textos' and column_name='author_id')"
echo "LISTO"
