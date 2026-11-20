-- Foros y sala de debates (1/3): helpers privados y límite de ritmo compartido.
-- Mismo modelo que security-fixes-nov: helpers SECURITY DEFINER en `private` (no expuesto
-- por la API), search_path = '' y nombres calificados. Idempotente.
-- Requiere las migraciones 20261110210100..210700 (schema private, author_id).

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- Límite server-side: como máximo 10 mensajes (foros + argumentos de debate) por usuario
-- por minuto. Cuenta por author_id en ambas tablas. Las tablas se crean en fd02/fd03; la
-- función es plpgsql, así que se resuelven recién al ejecutarse.
create or replace function private.conversacion_recientes(p_uid uuid)
returns integer language plpgsql stable security definer set search_path = ''
as $$
declare n integer := 0; m integer := 0;
begin
  if to_regclass('public.foro_mensajes') is not null then
    select count(*) into n from public.foro_mensajes
     where author_id = p_uid and created_at > now() - interval '1 minute';
  end if;
  if to_regclass('public.debate_argumentos') is not null then
    select count(*) into m from public.debate_argumentos
     where author_id = p_uid and created_at > now() - interval '1 minute';
  end if;
  return n + m;
end $$;

-- Trigger BEFORE INSERT (SECURITY INVOKER a propósito: current_user es el rol de la API)
create or replace function private.limitar_ritmo_conversacion()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if private.conversacion_recientes(auth.uid()) >= 10 then
    raise exception 'Demasiados mensajes seguidos: esperá un minuto' using errcode = '54000';
  end if;
  return new;
end $$;

-- Nombre visible del usuario actual (lo pone el servidor en cada mensaje)
create or replace function private.mi_nombre()
returns text language sql stable security definer set search_path = ''
as $$ select p.name from public.perfiles p where p.id = auth.uid() $$;

revoke all on function private.conversacion_recientes(uuid), private.limitar_ritmo_conversacion(),
  private.mi_nombre() from public, anon;
grant execute on function private.conversacion_recientes(uuid), private.limitar_ritmo_conversacion(),
  private.mi_nombre() to authenticated, service_role;
