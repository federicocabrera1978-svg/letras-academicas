-- SOLO PRUEBAS LOCALES
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;
create or replace function tests.login(p uuid) returns void language plpgsql as $$
begin perform set_config('role','postgres',false); perform set_config('request.jwt.claim.sub', p::text, false); perform set_config('role','authenticated',false); end $$;
create or replace function tests.anon() returns void language plpgsql as $$
begin perform set_config('role','postgres',false); perform set_config('request.jwt.claim.sub', '', false); perform set_config('role','anon',false); end $$;
create or replace function tests.su() returns void language plpgsql as $$
begin perform set_config('role','postgres',false); perform set_config('request.jwt.claim.sub', '', false); end $$;
create or replace function tests.ok(c boolean, msg text) returns void language plpgsql as $$
begin if c is not true then raise exception 'FAIL: %', msg; end if; raise notice 'ok: %', msg; end $$;
create or replace function tests.n(q text) returns bigint language plpgsql as $$
declare r bigint; begin execute 'with x as (' || q || ') select count(*) from x' into r; return r; end $$;
create or replace function tests.falla(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'ok (falla como se espera): % -> %', msg, sqlerrm; return; end;
  raise exception 'FAIL: % (no falló)', msg;
end $$;
grant execute on all functions in schema tests to anon, authenticated;
