#!/usr/bin/env bash
# Pruebas locales de las migraciones (NO toca producción).
# Requiere un Postgres 17 local: PGHOST/PGPORT/PGUSER (superusuario).
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
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
PGOPTIONS="-c client_min_messages=notice" $P -d "$DB" -f tests/20_test_seguridad.sql >/tmp/seg_out.txt 2>&1 || { grep -E "FAIL|ERROR" /tmp/seg_out.txt; echo FAIL seguridad; exit 1; }
if grep -qE "FAIL|ERROR" /tmp/seg_out.txt; then grep -E "FAIL|ERROR" /tmp/seg_out.txt; exit 1; fi
echo "   $(grep -c 'NOTICE:  ok' /tmp/seg_out.txt) asserts OK (con todas las migraciones, incluidas foros y debates)"
echo "5) rollback desde estado migrado (base nueva)"; fresh
for f in migrations/2026111021*.sql; do run -1 -f "$f" 2>/dev/null; done
run -1 -f rollback/rollback_security_fixes_nov.sql 2>/dev/null
snapshot > /tmp/snap_rollback.txt
diff -u /tmp/snap_baseline.txt /tmp/snap_rollback.txt || { echo FAIL rollback; exit 1; }; echo "   rollback deja el catálogo igual al baseline (políticas, funciones, grants, triggers)"
echo "6) fallo controlado: texto con username sin perfil aborta f02 sin cambios"; fresh
$P -d "$DB" -c "insert into public.textos (title, author_username, author_name, type, body) values ('huérfano','nadie','Nadie','otro','x')" >/dev/null
for f in migrations/2026111021010*.sql migrations/2026111021020*.sql migrations/2026111021030*.sql; do run -1 -f "$f" 2>/dev/null; done
if run -1 -f migrations/20261110210400_f02_autoria_por_id.sql 2>/tmp/f02err; then echo "   FAIL: debió abortar"; exit 1; fi
grep -o "f02 abortada.*" /tmp/f02err | head -1
$P -d "$DB" -Atc "select '   columna author_id existe tras abortar: ' || exists(select 1 from information_schema.columns where table_name='textos' and column_name='author_id')"
echo "7) foros y sala de debates (20261116200*): estado previo = security-fixes-nov aplicado"; fresh
for f in migrations/2026111021*.sql; do run -1 -f "$f" 2>/dev/null; done
snapshot > /tmp/snap_pre_fd.txt
for f in migrations/2026111620*.sql; do run -1 -f "$f"; done
snapshot > /tmp/snap_fd.txt
for f in migrations/2026111620*.sql; do run -1 -f "$f"; done
snapshot > /tmp/snap_fd2.txt
diff -u /tmp/snap_fd.txt /tmp/snap_fd2.txt || { echo FAIL idempotencia foros/debates; exit 1; }; echo "   idéntico tras re-aplicar"
run -f tests/10_helpers.sql
PGOPTIONS="-c client_min_messages=notice" $P -d "$DB" -f tests/40_test_foros_debates.sql >/tmp/fd_out.txt 2>&1 || { grep -E "FAIL|ERROR" /tmp/fd_out.txt; echo FAIL foros/debates; exit 1; }
if grep -qE "FAIL|ERROR" /tmp/fd_out.txt; then grep -E "FAIL|ERROR" /tmp/fd_out.txt; exit 1; fi
echo "   $(grep -c 'NOTICE:  ok' /tmp/fd_out.txt) asserts OK (admin / profesor / alumnos de GENERAL y de OTRO / anon)"
echo "8) rollback de foros/debates (con datos cargados) y re-aplicación"
run -1 -f rollback/rollback_foros_debates.sql
snapshot > /tmp/snap_rb_fd.txt
diff -u /tmp/snap_pre_fd.txt /tmp/snap_rb_fd.txt || { echo FAIL rollback foros/debates; exit 1; }; echo "   rollback deja el catálogo igual al estado previo"
run -1 -f rollback/rollback_foros_debates.sql; echo "   rollback idempotente"
for f in migrations/2026111620*.sql; do run -1 -f "$f"; done
snapshot > /tmp/snap_fd3.txt
diff -u /tmp/snap_fd.txt /tmp/snap_fd3.txt || { echo FAIL re-aplicar tras rollback; exit 1; }; echo "   se puede volver a aplicar tras el rollback (mismo catálogo)"
echo "LISTO"
