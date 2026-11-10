-- SOLO PARA PRUEBAS LOCALES: réplica del esquema de producción (xjrdjesezseuofjoqpzn)
-- leída del catálogo el 2026-11-10 (pg_policies, pg_proc, pg_trigger, pg_constraint, grants).
create table public.instituciones (id uuid primary key default gen_random_uuid(), nombre text not null, slug text not null unique, creado_en timestamptz default now());
create table public.cursos (
  id uuid primary key default gen_random_uuid(),
  institucion_id uuid not null references public.instituciones(id) on delete cascade,
  nombre text not null, descripcion text,
  codigo_invitacion text not null unique default upper(substr(md5(random()::text),1,6)),
  invitacion_activa boolean not null default true, archivado boolean not null default false,
  creado_por uuid default auth.uid() references auth.users(id), creado_en timestamptz default now());
create table public.miembros_curso (
  curso_id uuid not null references public.cursos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rol text not null check (rol in ('docente','alumno')), unido_en timestamptz default now(),
  primary key (curso_id, user_id));
create table public.perfiles (
  id uuid primary key references auth.users(id), name text, username text unique,
  color text default '#2d5a8e', rol text default 'alumno', created_at timestamp default now(), avatar_url text,
  constraint perfiles_largos check ((char_length(coalesce(name,'')) <= 120) and (char_length(username) <= 40) and (char_length(coalesce(avatar_url,'')) <= 1000) and ((color is null) or (color ~ '^#[0-9a-fA-F]{6}$'))),
  constraint perfiles_rol_valido check (rol in ('alumno','profesor','admin')));
create table public.textos (
  id uuid primary key default gen_random_uuid(), title text not null, author_username text not null, author_name text not null,
  type text not null, body text not null, destacado boolean default false, likes integer default 0,
  created_at timestamptz default now(), date timestamptz default now(),
  curso_id uuid references public.cursos(id) on delete set null, consigna_id uuid, entregada_tarde boolean not null default false,
  constraint textos_largos check (((char_length(title) >= 1) and (char_length(title) <= 200)) and (char_length(body) <= 200000) and (char_length(coalesce(type,'')) <= 30) and (char_length(coalesce(author_name,'')) <= 120)));
create table public.comentarios (
  id uuid primary key default gen_random_uuid(), texto_id uuid references public.textos(id) on delete cascade,
  author_username text not null, author_name text not null, body text not null, created_at timestamptz default now(),
  constraint comentarios_largos check (((char_length(body) >= 1) and (char_length(body) <= 5000)) and (char_length(coalesce(author_name,'')) <= 120)));
create table public.likes (
  id uuid primary key default gen_random_uuid(), texto_id uuid references public.textos(id) on delete cascade,
  user_username text not null, created_at timestamptz default now(), constraint likes_unico unique (texto_id, user_username));
create index comentarios_autor_fecha on public.comentarios (author_username, created_at);
create index comentarios_texto_id_idx on public.comentarios (texto_id);
create index cursos_creado_por_idx on public.cursos (creado_por);
create index cursos_institucion_id_idx on public.cursos (institucion_id);
create index miembros_curso_user_id_idx on public.miembros_curso (user_id);
create index textos_curso_id_idx on public.textos (curso_id);
create index textos_autor_fecha on public.textos (author_username, created_at);

alter table public.instituciones enable row level security;
alter table public.cursos enable row level security;
alter table public.miembros_curso enable row level security;
alter table public.perfiles enable row level security;
alter table public.textos enable row level security;
alter table public.comentarios enable row level security;
alter table public.likes enable row level security;

-- Funciones (copiadas de pg_get_functiondef)
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

create trigger trg_perfiles_proteger_rol before insert or update on public.perfiles for each row execute function perfiles_proteger_rol();
create trigger trg_textos_proteger_campos before insert or update on public.textos for each row execute function textos_proteger_campos();
create trigger trg_likes_recontar after insert or delete on public.likes for each row execute function likes_recontar();
create trigger trg_comentarios_proteger_autor before insert or update on public.comentarios for each row execute function comentarios_proteger_autor();
create trigger trg_cursos_creador_docente after insert on public.cursos for each row execute function cursos_creador_docente();
create trigger trg_textos_ritmo before insert on public.textos for each row execute function limitar_ritmo();
create trigger trg_comentarios_ritmo before insert on public.comentarios for each row execute function limitar_ritmo();

-- Políticas (pg_policies)
create policy comentarios_delete on public.comentarios for delete to authenticated using ((author_username = mi_username()) or es_profesor());
create policy comentarios_insert on public.comentarios for insert to authenticated with check (author_username = mi_username());
create policy comentarios_select on public.comentarios for select to authenticated using (true);
create policy comentarios_update on public.comentarios for update to authenticated using (author_username = mi_username()) with check (author_username = mi_username());
create policy cursos_borrar on public.cursos for delete to authenticated using (es_admin());
create policy cursos_crear on public.cursos for insert to authenticated with check (es_profesor() and (creado_por = (select auth.uid())));
create policy cursos_editar on public.cursos for update to authenticated using (es_docente_curso(id)) with check (es_docente_curso(id));
create policy cursos_ver on public.cursos for select to authenticated using (es_miembro_curso(id) or es_admin());
create policy inst_admin_del on public.instituciones for delete to authenticated using (es_admin());
create policy inst_admin_ins on public.instituciones for insert to authenticated with check (es_admin());
create policy inst_admin_upd on public.instituciones for update to authenticated using (es_admin()) with check (es_admin());
create policy inst_ver on public.instituciones for select to authenticated using (true);
create policy likes_delete on public.likes for delete to authenticated using (user_username = mi_username());
create policy likes_insert on public.likes for insert to authenticated with check ((user_username = mi_username()) and (not exists (select 1 from textos t where (t.id = likes.texto_id) and (t.author_username = mi_username()))));
create policy likes_select on public.likes for select to authenticated using (true);
create policy mc_salir_o_quitar on public.miembros_curso for delete to authenticated using ((user_id = (select auth.uid())) or es_docente_curso(curso_id));
create policy mc_ver on public.miembros_curso for select to authenticated using ((user_id = (select auth.uid())) or es_docente_curso(curso_id));
create policy perfiles_delete on public.perfiles for delete to authenticated using (es_profesor() and (id <> (select auth.uid())));
create policy perfiles_insert on public.perfiles for insert to authenticated with check (id = (select auth.uid()));
create policy perfiles_select on public.perfiles for select to authenticated using (true);
create policy perfiles_update on public.perfiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy textos_delete on public.textos for delete to authenticated using ((author_username = mi_username()) or es_profesor());
create policy textos_insert on public.textos for insert to authenticated with check (author_username = mi_username());
create policy textos_select_anon on public.textos for select to anon using (destacado = true);
create policy textos_select_auth on public.textos for select to authenticated using (true);
create policy textos_update on public.textos for update to authenticated using ((author_username = mi_username()) or es_profesor()) with check ((author_username = mi_username()) or es_profesor());

-- Grants (relacl / column_privileges de prod)
grant select, insert, update, delete, maintain on public.comentarios, public.likes, public.textos to anon, authenticated;
grant select, insert, update, delete, maintain on public.cursos, public.miembros_curso, public.instituciones to authenticated;
grant select, delete, maintain on public.perfiles to anon, authenticated;
grant insert (avatar_url, color, id, name, username) on public.perfiles to authenticated;
grant update (avatar_url, color, created_at, id, name, username) on public.perfiles to authenticated;
grant all on all tables in schema public to service_role;
-- funciones: prod revocó EXECUTE a PUBLIC/anon en los helpers SECURITY DEFINER
revoke execute on all functions in schema public from public;
grant execute on function public.es_admin(), public.es_profesor(), public.es_docente_curso(uuid), public.es_miembro_curso(uuid), public.mi_username(),
  public.habilitar_docente(uuid, boolean), public.unirse_a_curso(text), public.perfiles_proteger_rol(), public.textos_proteger_campos() to authenticated;
grant execute on function public.comentarios_proteger_autor() to public, anon, authenticated;
grant execute on all functions in schema public to service_role;
