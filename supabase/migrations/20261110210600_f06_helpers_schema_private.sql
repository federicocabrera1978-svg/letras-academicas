-- Hallazgo 6 (medio): los helpers SECURITY DEFINER (es_admin, es_profesor, es_docente_curso,
-- es_miembro_curso, mi_username) estaban en public y se podían llamar como RPC
-- (/rest/v1/rpc/...), lo que permite sondear roles/membresías.
-- Arreglo: se mueven al schema `private` (no expuesto por la API). Las políticas siguen
-- funcionando porque referencian las funciones por OID. Se reescriben con search_path=''
-- y nombres calificados, y se actualizan las funciones que los llaman.
-- Quedan en public (son RPC que usa la app): habilitar_docente, unirse_a_curso, eliminar_miembro.
-- Idempotente.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

do $$
declare f text;
begin
  foreach f in array array['es_admin()', 'es_profesor()', 'es_docente_curso(uuid)', 'es_miembro_curso(uuid)', 'mi_username()'] loop
    if to_regprocedure('public.' || f) is not null and to_regprocedure('private.' || f) is null then
      execute format('alter function public.%s set schema private', f);
    end if;
  end loop;
end $$;

create or replace function private.es_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((select p.rol = 'admin' from public.perfiles p where p.id = auth.uid()), false); $$;

create or replace function private.es_profesor()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((select p.rol in ('profesor','admin') from public.perfiles p where p.id = auth.uid()), false); $$;

create or replace function private.es_docente_curso(c uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select private.es_admin() or exists (select 1 from public.miembros_curso m where m.curso_id = c and m.user_id = auth.uid() and m.rol = 'docente'); $$;

create or replace function private.es_miembro_curso(c uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.miembros_curso m where m.curso_id = c and m.user_id = auth.uid()); $$;

create or replace function private.mi_username()
returns text language sql stable security definer set search_path = ''
as $$ select p.username from public.perfiles p where p.id = auth.uid() $$;

revoke all on function private.es_admin(), private.es_profesor(), private.es_docente_curso(uuid),
  private.es_miembro_curso(uuid), private.mi_username() from public, anon;
-- authenticated necesita EXECUTE porque las políticas RLS se evalúan con su rol;
-- no son invocables por la API porque `private` no está en los schemas expuestos.
grant execute on function private.es_admin(), private.es_profesor(), private.es_docente_curso(uuid),
  private.es_miembro_curso(uuid), private.mi_username() to authenticated, service_role;

-- Funciones que los llaman: nombres calificados y search_path fijo
create or replace function public.habilitar_docente(p_user uuid, p_habilitar boolean default true)
returns void language plpgsql security definer set search_path = ''
as $function$
declare g uuid;
begin
  if not private.es_admin() then raise exception 'Solo el administrador habilita docentes'; end if;
  if p_user = auth.uid() then raise exception 'No podés cambiar tu propio rol'; end if;
  update public.perfiles set rol = case when p_habilitar then 'profesor' else 'alumno' end
   where id = p_user and rol <> 'admin';
  select id into g from public.cursos where codigo_invitacion = 'GENERAL';
  if g is not null then
    insert into public.miembros_curso (curso_id, user_id, rol)
      values (g, p_user, case when p_habilitar then 'docente' else 'alumno' end)
      on conflict (curso_id, user_id) do update set rol = excluded.rol;
  end if;
end $function$;

create or replace function public.eliminar_miembro(p_user uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_rol text;
begin
  if auth.uid() is null or not private.es_admin() then
    raise exception 'Solo el administrador puede eliminar miembros' using errcode = '42501';
  end if;
  if p_user is null or p_user = auth.uid() then
    raise exception 'No podés eliminar tu propia cuenta' using errcode = '42501';
  end if;
  select rol into v_rol from public.perfiles where id = p_user for update;
  if not found then raise exception 'Miembro no encontrado' using errcode = 'P0002'; end if;
  if v_rol = 'admin' then raise exception 'No se puede eliminar a un administrador' using errcode = '42501'; end if;
  delete from public.miembros_curso where user_id = p_user;
  delete from public.perfiles where id = p_user;
end $$;

create or replace function public.textos_proteger_campos()
returns trigger language plpgsql set search_path = ''
as $function$
declare puede_destacar boolean; v_username text;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_username := private.mi_username();
    if v_username is null then raise exception 'Tu perfil no existe todavía'; end if;
    new.author_id := auth.uid();
    new.author_username := v_username;
    new.likes := 0;
    new.destacado := false;
    new.entregada_tarde := false;
    new.author_name := coalesce((select p.name from public.perfiles p where p.id = auth.uid()), new.author_name);
    if new.curso_id is not null and not private.es_miembro_curso(new.curso_id) then
      raise exception 'No sos miembro de ese curso';
    end if;
    return new;
  end if;
  puede_destacar := private.es_admin() or (old.curso_id is not null and private.es_docente_curso(old.curso_id));
  new.author_id := old.author_id;
  new.likes := old.likes;
  new.author_username := old.author_username;
  new.author_name := old.author_name;
  new.curso_id := old.curso_id;
  new.consigna_id := old.consigna_id;
  new.entregada_tarde := old.entregada_tarde;
  if not puede_destacar then new.destacado := old.destacado; end if;
  if old.author_id is distinct from auth.uid() then
    new.title := old.title; new.body := old.body; new.type := old.type;
  end if;
  return new;
end $function$;

create or replace function public.comentarios_proteger_autor()
returns trigger language plpgsql set search_path = ''
as $function$
declare v_username text;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_username := private.mi_username();
    if v_username is null then raise exception 'Tu perfil no existe todavía'; end if;
    new.author_id := auth.uid();
    new.author_username := v_username;
    new.author_name := coalesce((select p.name from public.perfiles p where p.id = auth.uid()), new.author_name);
  else
    new.author_id := old.author_id;
    new.author_username := old.author_username;
    new.author_name := old.author_name;
    new.texto_id := old.texto_id;
  end if;
  return new;
end $function$;

create or replace function public.likes_fijar_usuario()
returns trigger language plpgsql set search_path = ''
as $function$
declare v_username text;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_username := private.mi_username();
    if v_username is null then raise exception 'Tu perfil no existe todavía'; end if;
    new.user_id := auth.uid();
    new.user_username := v_username;
  else
    new.user_id := old.user_id;
    new.user_username := old.user_username;
    new.texto_id := old.texto_id;
  end if;
  return new;
end $function$;

create or replace function public.perfiles_proteger_rol()
returns trigger language plpgsql set search_path = ''
as $function$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if new.avatar_url is not null and new.avatar_url !~ '^https://[^\s"''<>]+$' then
    raise exception 'avatar_url inválida';
  end if;
  if tg_op = 'INSERT' then
    new.rol := 'alumno';
    new.username := private.username_para_mi(new.username);
  elsif new.rol is distinct from old.rol then
    raise exception 'No está permitido cambiar el rol';
  end if;
  if tg_op = 'UPDATE' and new.username is distinct from old.username then
    raise exception 'No está permitido cambiar el username';
  end if;
  if tg_op = 'UPDATE' and new.id is distinct from old.id then
    raise exception 'No está permitido cambiar el id';
  end if;
  return new;
end $function$;

create or replace function public.limitar_ritmo()
returns trigger language plpgsql set search_path = ''
as $function$
declare n int; tope int;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  tope := case tg_table_name when 'textos' then 5 else 10 end;
  execute format('select count(*) from public.%I where author_id = $1 and created_at > now() - interval ''1 minute''', tg_table_name)
    into n using auth.uid();
  if n >= tope then raise exception 'Demasiadas publicaciones seguidas: esperá un minuto'; end if;
  return new;
end $function$;

create or replace function public.unirse_a_curso(codigo text)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare c public.cursos;
begin
  if auth.uid() is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  select * into c from public.cursos where codigo_invitacion = upper(trim(codigo)) and invitacion_activa and not archivado;
  if not found then raise exception 'Código inválido'; end if;
  insert into public.miembros_curso (curso_id, user_id, rol) values (c.id, auth.uid(), 'alumno') on conflict do nothing;
  return c.id;
end $function$;

create or replace function public.cursos_creador_docente()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if new.creado_por is not null then
    insert into public.miembros_curso (curso_id, user_id, rol) values (new.id, new.creado_por, 'docente')
    on conflict (curso_id, user_id) do update set rol = 'docente';
  end if;
  return new;
end $function$;

create or replace function public.likes_recontar()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare v_id uuid := coalesce(new.texto_id, old.texto_id);
begin
  update public.textos set likes = (select count(*) from public.likes where texto_id = v_id) where id = v_id;
  return null;
end $function$;

-- Trigger functions no deben ser invocables por la API
revoke all on function public.cursos_creador_docente(), public.likes_recontar() from public, anon, authenticated;
