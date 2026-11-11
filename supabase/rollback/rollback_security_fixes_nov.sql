-- ROLLBACK de las migraciones 20261110210100..20261110210700 (security-fixes-nov).
-- Deja políticas, funciones, triggers y grants EXACTAMENTE como estaban en prod el 2026-11-10
-- (leídos del catálogo). Correr en UNA transacción:  psql -1 -f rollback_security_fixes_nov.sql
-- No borra textos/comentarios/likes/perfiles. Solo quita las columnas nuevas author_id/user_id
-- (author_username/user_username, que el servidor siguió llenando, quedan como estaban).
-- El frontend nuevo funciona también con el esquema viejo, así que no hace falta revertirlo
-- primero; "Eliminar miembro" fallará con un error visible hasta volver a migrar.

set search_path = public;

-- 0) Helpers: volver de private a public (las políticas siguen por OID)
do $$
declare f text;
begin
  foreach f in array array['es_admin()', 'es_profesor()', 'es_docente_curso(uuid)', 'es_miembro_curso(uuid)', 'mi_username()'] loop
    if to_regprocedure('private.' || f) is not null and to_regprocedure('public.' || f) is null then
      execute format('alter function private.%s set schema public', f);
    end if;
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.es_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ select coalesce((select rol = 'admin' from perfiles where id = auth.uid()), false); $function$;
CREATE OR REPLACE FUNCTION public.es_profesor() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ select coalesce((select rol in ('profesor','admin') from perfiles where id = auth.uid()), false); $function$;
CREATE OR REPLACE FUNCTION public.es_docente_curso(c uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ select es_admin() or exists (select 1 from miembros_curso where curso_id = c and user_id = auth.uid() and rol = 'docente'); $function$;
CREATE OR REPLACE FUNCTION public.es_miembro_curso(c uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ select exists (select 1 from miembros_curso where curso_id = c and user_id = auth.uid()); $function$;
CREATE OR REPLACE FUNCTION public.mi_username() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ select username from public.perfiles where id = auth.uid() $function$;

-- 1) Políticas originales
drop policy if exists comentarios_delete on public.comentarios;
create policy comentarios_delete on public.comentarios for delete to authenticated using ((author_username = mi_username()) or es_profesor());
drop policy if exists comentarios_insert on public.comentarios;
create policy comentarios_insert on public.comentarios for insert to authenticated with check (author_username = mi_username());
drop policy if exists comentarios_select on public.comentarios;
create policy comentarios_select on public.comentarios for select to authenticated using (true);
drop policy if exists comentarios_update on public.comentarios;
create policy comentarios_update on public.comentarios for update to authenticated using (author_username = mi_username()) with check (author_username = mi_username());
drop policy if exists likes_delete on public.likes;
create policy likes_delete on public.likes for delete to authenticated using (user_username = mi_username());
drop policy if exists likes_insert on public.likes;
create policy likes_insert on public.likes for insert to authenticated with check ((user_username = mi_username()) and (not exists (select 1 from textos t where (t.id = likes.texto_id) and (t.author_username = mi_username()))));
drop policy if exists likes_select on public.likes;
create policy likes_select on public.likes for select to authenticated using (true);
drop policy if exists perfiles_delete on public.perfiles;
create policy perfiles_delete on public.perfiles for delete to authenticated using (es_profesor() and (id <> (select auth.uid())));
drop policy if exists perfiles_select on public.perfiles;
create policy perfiles_select on public.perfiles for select to authenticated using (true);
drop policy if exists textos_delete on public.textos;
create policy textos_delete on public.textos for delete to authenticated using ((author_username = mi_username()) or es_profesor());
drop policy if exists textos_insert on public.textos;
create policy textos_insert on public.textos for insert to authenticated with check (author_username = mi_username());
drop policy if exists textos_select_auth on public.textos;
create policy textos_select_auth on public.textos for select to authenticated using (true);
drop policy if exists textos_update on public.textos;
create policy textos_update on public.textos for update to authenticated using ((author_username = mi_username()) or es_profesor()) with check ((author_username = mi_username()) or es_profesor());

-- 2) Triggers / funciones originales
drop trigger if exists trg_likes_fijar_usuario on public.likes;
drop function if exists public.likes_fijar_usuario();
drop function if exists public.eliminar_miembro(uuid);

CREATE OR REPLACE FUNCTION public.comentarios_proteger_autor() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    new.author_name := coalesce((select name from public.perfiles where username = public.mi_username()), new.author_name);
  else
    new.author_username := old.author_username; new.author_name := old.author_name; new.texto_id := old.texto_id;
  end if;
  return new;
end $function$;
CREATE OR REPLACE FUNCTION public.cursos_creador_docente() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  if new.creado_por is not null then
    insert into miembros_curso (curso_id, user_id, rol) values (new.id, new.creado_por, 'docente')
    on conflict (curso_id, user_id) do update set rol = 'docente';
  end if;
  return new;
end $function$;
CREATE OR REPLACE FUNCTION public.habilitar_docente(p_user uuid, p_habilitar boolean DEFAULT true) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare g uuid;
begin
  if not es_admin() then raise exception 'Solo el administrador habilita docentes'; end if;
  if p_user = auth.uid() then raise exception 'No podés cambiar tu propio rol'; end if;
  update perfiles set rol = case when p_habilitar then 'profesor' else 'alumno' end where id = p_user and rol <> 'admin';
  select id into g from cursos where codigo_invitacion = 'GENERAL';
  if g is not null then
    insert into miembros_curso (curso_id, user_id, rol) values (g, p_user, case when p_habilitar then 'docente' else 'alumno' end)
      on conflict (curso_id, user_id) do update set rol = excluded.rol;
  end if;
end $function$;
CREATE OR REPLACE FUNCTION public.likes_recontar() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_id uuid := coalesce(new.texto_id, old.texto_id);
begin
  update public.textos set likes = (select count(*) from public.likes where texto_id = v_id) where id = v_id;
  return null;
end $function$;
CREATE OR REPLACE FUNCTION public.limitar_ritmo() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
declare n int; tope int;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  tope := case tg_table_name when 'textos' then 5 else 10 end;
  execute format('select count(*) from %I where author_username = $1 and created_at > now() - interval ''1 minute''', tg_table_name)
    into n using new.author_username;
  if n >= tope then raise exception 'Demasiadas publicaciones seguidas: esperá un minuto'; end if;
  return new;
end $function$;
CREATE OR REPLACE FUNCTION public.perfiles_proteger_rol() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if new.avatar_url is not null and new.avatar_url !~ '^https://[^\s"''<>]+$' then raise exception 'avatar_url inválida'; end if;
  if tg_op = 'INSERT' then new.rol := 'alumno';
  elsif new.rol is distinct from old.rol then raise exception 'No está permitido cambiar el rol';
  end if;
  if tg_op = 'UPDATE' and new.username is distinct from old.username then raise exception 'No está permitido cambiar el username'; end if;
  return new;
end $function$;
CREATE OR REPLACE FUNCTION public.textos_proteger_campos() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
declare puede_destacar boolean;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  puede_destacar := es_admin() or (new.curso_id is not null and es_docente_curso(new.curso_id));
  if tg_op = 'INSERT' then
    new.likes := 0; new.destacado := false; new.entregada_tarde := false;
    new.author_name := coalesce((select name from perfiles where id = auth.uid()), new.author_name);
    if new.curso_id is not null and not es_miembro_curso(new.curso_id) then raise exception 'No sos miembro de ese curso'; end if;
    return new;
  end if;
  new.likes := old.likes; new.author_username := old.author_username; new.author_name := old.author_name;
  new.curso_id := old.curso_id; new.consigna_id := old.consigna_id; new.entregada_tarde := old.entregada_tarde;
  if not puede_destacar then new.destacado := old.destacado; end if;
  if old.author_username <> mi_username() then new.title := old.title; new.body := old.body; new.type := old.type; end if;
  return new;
end $function$;
CREATE OR REPLACE FUNCTION public.unirse_a_curso(codigo text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare c cursos;
begin
  select * into c from cursos where codigo_invitacion = upper(trim(codigo)) and invitacion_activa and not archivado;
  if not found then raise exception 'Código inválido'; end if;
  insert into miembros_curso (curso_id, user_id, rol) values (c.id, auth.uid(), 'alumno') on conflict do nothing;
  return c.id;
end $function$;

drop function if exists private.comparte_curso(uuid);
drop function if exists private.username_para_mi(text);

-- 3) Columnas / constraints / índices nuevos
drop index if exists public.textos_author_id_fecha;
drop index if exists public.comentarios_author_id_fecha;
drop index if exists public.likes_user_id_idx;
alter table public.likes       drop constraint if exists likes_unico_user;
alter table public.textos      drop constraint if exists textos_author_id_fkey;
alter table public.comentarios drop constraint if exists comentarios_author_id_fkey;
alter table public.likes       drop constraint if exists likes_user_id_fkey;
alter table public.textos      drop column if exists author_id;
alter table public.comentarios drop column if exists author_id;
alter table public.likes       drop column if exists user_id;

-- 4) Grants originales
revoke select (id, name, username, avatar_url, rol) on public.perfiles from authenticated;
revoke select (id, title, type, body, author_name, created_at, destacado) on public.textos from anon;
grant select, insert, update, delete, maintain on public.textos, public.comentarios, public.likes to anon, authenticated;
grant select, delete, maintain on public.perfiles to anon, authenticated;
grant maintain on public.cursos, public.miembros_curso, public.instituciones to authenticated;
grant update on public.likes to authenticated;
grant execute on function public.es_admin(), public.es_profesor(), public.es_docente_curso(uuid), public.es_miembro_curso(uuid), public.mi_username() to authenticated;
grant execute on function public.cursos_creador_docente(), public.likes_recontar() to service_role;

-- 5) Schema private (vacío ya)
drop schema if exists private;

reset search_path;
