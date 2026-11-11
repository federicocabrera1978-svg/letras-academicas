-- Hallazgo 2 (alto): la autoría/permisos dependían de author_username (texto). Si se borraba
-- un perfil, otra persona que se registrara con el mismo username "heredaba" sus textos.
-- Arreglo:
--   * textos.author_id, comentarios.author_id y likes.user_id (uuid, FK a auth.users) con
--     backfill desde perfiles.username, default auth.uid() y NOT NULL.
--   * Las políticas usan el id (auth.uid()), no el username.
--   * author_username / user_username se CONSERVAN (no se borran) como dato visible, pero los
--     fija el servidor (trigger) y ya no son llave de permisos.
--   * El username del perfil lo fija el servidor al crear el perfil (derivado del email de
--     auth.users), único con sufijo numérico y sin reutilizar usernames que aparezcan en
--     textos/comentarios/likes de otra cuenta.
-- La migración ABORTA (sin cambiar nada, si se corre en una transacción) si quedara alguna
-- fila sin autor identificable. Idempotente.
-- Los helpers se resuelven en public (antes de f06) o en private (después de f06).
set search_path = public, private, extensions;


-- 0) Schema privado (no expuesto por la API) para helpers SECURITY DEFINER.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- 1) Columnas nuevas (nullable hasta terminar el backfill)
alter table public.textos      add column if not exists author_id uuid;
alter table public.comentarios add column if not exists author_id uuid;
alter table public.likes       add column if not exists user_id   uuid;

-- 2) Backfill desde perfiles.username (único)
update public.textos t      set author_id = p.id from public.perfiles p where t.author_id is null and p.username = t.author_username;
update public.comentarios c set author_id = p.id from public.perfiles p where c.author_id is null and p.username = c.author_username;
update public.likes l       set user_id   = p.id from public.perfiles p where l.user_id   is null and p.username = l.user_username;

-- 3) Verificación: 0 filas sin autor. Si falla, se aborta todo.
do $$
declare a int; b int; c int;
begin
  select count(*) into a from public.textos      where author_id is null;
  select count(*) into b from public.comentarios where author_id is null;
  select count(*) into c from public.likes       where user_id   is null;
  if a + b + c > 0 then
    raise exception 'f02 abortada: % textos, % comentarios y % likes sin autor identificable (username sin perfil). Resolver a mano antes de reintentar.', a, b, c;
  end if;
end $$;

-- 4) Default, NOT NULL, FK e índices
alter table public.textos      alter column author_id set default auth.uid();
alter table public.comentarios alter column author_id set default auth.uid();
alter table public.likes       alter column user_id   set default auth.uid();
alter table public.textos      alter column author_id set not null;
alter table public.comentarios alter column author_id set not null;
alter table public.likes       alter column user_id   set not null;

do $$
begin
  -- Sin ON DELETE CASCADE a propósito: borrar un usuario de auth con textos falla en vez de
  -- borrar sus textos en silencio.
  if not exists (select 1 from pg_constraint where conname = 'textos_author_id_fkey') then
    alter table public.textos add constraint textos_author_id_fkey foreign key (author_id) references auth.users(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'comentarios_author_id_fkey') then
    alter table public.comentarios add constraint comentarios_author_id_fkey foreign key (author_id) references auth.users(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'likes_user_id_fkey') then
    alter table public.likes add constraint likes_user_id_fkey foreign key (user_id) references auth.users(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'likes_unico_user') then
    alter table public.likes add constraint likes_unico_user unique (texto_id, user_id);
  end if;
end $$;

create index if not exists textos_author_id_fecha      on public.textos (author_id, created_at);
create index if not exists comentarios_author_id_fecha on public.comentarios (author_id, created_at);
create index if not exists likes_user_id_idx           on public.likes (user_id);

-- 5) Username fijado por el servidor
create or replace function private.username_para_mi(p_sugerido text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_base  text;
  v_cand  text;
  v_n     int := 1;
begin
  if v_uid is null then
    raise exception 'Sin sesión' using errcode = '42501';
  end if;
  select email into v_email from auth.users where id = v_uid;
  v_base := regexp_replace(lower(coalesce(split_part(v_email, '@', 1), '')), '[^a-z0-9]', '', 'g');
  if v_base = '' then
    v_base := regexp_replace(lower(coalesce(p_sugerido, '')), '[^a-z0-9]', '', 'g');
  end if;
  if v_base = '' then v_base := 'usuario'; end if;
  v_base := left(v_base, 30);
  v_cand := v_base;
  loop
    exit when not exists (select 1 from public.perfiles    where username        = v_cand and id        <> v_uid)
          and not exists (select 1 from public.textos      where author_username = v_cand and author_id <> v_uid)
          and not exists (select 1 from public.comentarios where author_username = v_cand and author_id <> v_uid)
          and not exists (select 1 from public.likes       where user_username   = v_cand and user_id   <> v_uid);
    v_n := v_n + 1;
    if v_n > 9999 then raise exception 'No se pudo generar un username único'; end if;
    v_cand := v_base || v_n::text;
  end loop;
  return v_cand;
end
$$;
revoke all on function private.username_para_mi(text) from public, anon;
grant execute on function private.username_para_mi(text) to authenticated, service_role;

create or replace function public.perfiles_proteger_rol()
returns trigger
language plpgsql
set search_path = public, private
as $function$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if new.avatar_url is not null and new.avatar_url !~ '^https://[^\s"''<>]+$' then
    raise exception 'avatar_url inválida';
  end if;
  if tg_op = 'INSERT' then
    new.rol := 'alumno';
    -- el username lo decide el servidor (único, derivado del email de la cuenta)
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

-- 6) Triggers de autoría: author_id/author_username/author_name los fija el servidor
create or replace function public.textos_proteger_campos()
returns trigger
language plpgsql
set search_path = public, private
as $function$
declare puede_destacar boolean; v_username text;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_username := mi_username();
    if v_username is null then raise exception 'Tu perfil no existe todavía'; end if;
    new.author_id := auth.uid();
    new.author_username := v_username;
    new.likes := 0;
    new.destacado := false;
    new.entregada_tarde := false;
    new.author_name := coalesce((select name from perfiles where id = auth.uid()), new.author_name);
    if new.curso_id is not null and not es_miembro_curso(new.curso_id) then
      raise exception 'No sos miembro de ese curso';
    end if;
    return new;
  end if;
  puede_destacar := es_admin() or (old.curso_id is not null and es_docente_curso(old.curso_id));
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
returns trigger
language plpgsql
set search_path = public, private
as $function$
declare v_username text;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_username := mi_username();
    if v_username is null then raise exception 'Tu perfil no existe todavía'; end if;
    new.author_id := auth.uid();
    new.author_username := v_username;
    new.author_name := coalesce((select name from public.perfiles where id = auth.uid()), new.author_name);
  else
    new.author_id := old.author_id;
    new.author_username := old.author_username;
    new.author_name := old.author_name;
    new.texto_id := old.texto_id;
  end if;
  return new;
end $function$;

create or replace function public.likes_fijar_usuario()
returns trigger
language plpgsql
set search_path = public, private
as $function$
declare v_username text;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_username := mi_username();
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
revoke all on function public.likes_fijar_usuario() from public, anon;
grant execute on function public.likes_fijar_usuario() to authenticated, service_role;

drop trigger if exists trg_likes_fijar_usuario on public.likes;
create trigger trg_likes_fijar_usuario before insert or update on public.likes
  for each row execute function public.likes_fijar_usuario();

-- limitar_ritmo: contar por id (indexado) en vez de username
create or replace function public.limitar_ritmo()
returns trigger
language plpgsql
set search_path = public, private
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

-- 7) Políticas por id
drop policy if exists textos_insert on public.textos;
create policy textos_insert on public.textos for insert to authenticated
  with check (author_id = (select auth.uid()));

drop policy if exists textos_update on public.textos;
create policy textos_update on public.textos for update to authenticated
  using (author_id = (select auth.uid()) or es_admin() or (curso_id is not null and es_docente_curso(curso_id)))
  with check (author_id = (select auth.uid()) or es_admin() or (curso_id is not null and es_docente_curso(curso_id)));

drop policy if exists textos_delete on public.textos;
create policy textos_delete on public.textos for delete to authenticated
  using (author_id = (select auth.uid()) or es_admin() or (curso_id is not null and es_docente_curso(curso_id)));

drop policy if exists comentarios_insert on public.comentarios;
create policy comentarios_insert on public.comentarios for insert to authenticated
  with check (author_id = (select auth.uid()));

drop policy if exists comentarios_update on public.comentarios;
create policy comentarios_update on public.comentarios for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

drop policy if exists comentarios_delete on public.comentarios;
create policy comentarios_delete on public.comentarios for delete to authenticated
  using (
    author_id = (select auth.uid())
    or es_admin()
    or exists (select 1 from public.textos t
               where t.id = comentarios.texto_id and t.curso_id is not null and es_docente_curso(t.curso_id))
  );

drop policy if exists likes_insert on public.likes;
create policy likes_insert on public.likes for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and not exists (select 1 from public.textos t where t.id = likes.texto_id and t.author_id = (select auth.uid()))
  );

-- likes_delete: "ya no me gusta" real, solo el propio like
drop policy if exists likes_delete on public.likes;
create policy likes_delete on public.likes for delete to authenticated
  using (user_id = (select auth.uid()));

reset search_path;
