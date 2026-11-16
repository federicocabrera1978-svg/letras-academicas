-- Foros y sala de debates (3/3): SALA DE DEBATES.
--   * El docente del curso (o el admin) crea un debate con una pregunta y 2 a 6 posturas
--     (RPC crear_debate; un trigger diferido garantiza el mínimo de 2 aunque se inserte directo).
--   * Cada miembro elige UNA postura por debate y la puede cambiar mientras esté abierto.
--   * Argumentos (ligados a la postura del autor) y réplicas de un nivel.
--   * Reacción "me hizo pensar": una por usuario y argumento, nunca sobre el propio. Sin ranking.
--   * Al cerrar, el docente escribe la síntesis y puede destacarla: anon ve SOLO pregunta +
--     síntesis de los debates destacados (nunca argumentos, posturas elegidas ni nombres).
-- Idempotente.

-- ── Tablas ──────────────────────────────────────────────────────
create table if not exists public.debates (
  id                 uuid primary key default gen_random_uuid(),
  curso_id           uuid not null references public.cursos(id) on delete cascade,
  pregunta           text not null,
  descripcion        text not null default '',
  estado             text not null default 'abierto',
  sintesis           text,
  sintesis_destacada boolean not null default false,
  creado_por         uuid default auth.uid() references auth.users(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  cerrado_en         timestamptz,
  constraint debates_largos check (char_length(btrim(pregunta)) between 1 and 300
    and char_length(descripcion) <= 5000 and char_length(coalesce(sintesis, '')) <= 10000),
  constraint debates_estado check (estado in ('abierto','cerrado')),
  constraint debates_destacar_cerrado check (not sintesis_destacada
    or (estado = 'cerrado' and char_length(btrim(coalesce(sintesis, ''))) > 0))
);

create table if not exists public.debate_posturas (
  id         uuid primary key default gen_random_uuid(),
  debate_id  uuid not null references public.debates(id) on delete cascade,
  nombre     text not null,
  orden      smallint not null default 0,
  constraint debate_posturas_id_debate unique (id, debate_id),
  constraint debate_posturas_nombre_unico unique (debate_id, nombre),
  constraint debate_posturas_largos check (char_length(btrim(nombre)) between 1 and 120)
);

create table if not exists public.debate_elecciones (
  debate_id  uuid not null references public.debates(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  postura_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (debate_id, user_id),
  constraint debate_elecciones_postura_fkey foreign key (postura_id, debate_id)
    references public.debate_posturas (id, debate_id) on delete cascade
);

create table if not exists public.debate_argumentos (
  id          uuid primary key default gen_random_uuid(),
  debate_id   uuid not null references public.debates(id) on delete cascade,
  postura_id  uuid,
  parent_id   uuid,
  author_id   uuid not null references auth.users(id),
  author_name text not null,
  body        text not null,
  oculto      boolean not null default false,
  editado     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint debate_argumentos_id_debate unique (id, debate_id),
  constraint debate_argumentos_postura_fkey foreign key (postura_id, debate_id)
    references public.debate_posturas (id, debate_id) on delete cascade,
  constraint debate_argumentos_parent_fkey foreign key (parent_id, debate_id)
    references public.debate_argumentos (id, debate_id) on delete cascade,
  constraint debate_argumentos_largos check (char_length(btrim(body)) between 1 and 5000 and char_length(author_name) <= 120)
);

create table if not exists public.debate_reacciones (
  argumento_id uuid not null references public.debate_argumentos(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (argumento_id, user_id)
);

create index if not exists debates_curso_idx on public.debates (curso_id, created_at);
create index if not exists debates_creado_por_idx on public.debates (creado_por);
create index if not exists debates_destacados_idx on public.debates (cerrado_en) where sintesis_destacada;
create index if not exists debate_posturas_debate_idx on public.debate_posturas (debate_id, orden);
create index if not exists debate_elecciones_postura_idx on public.debate_elecciones (postura_id, debate_id);
create index if not exists debate_elecciones_user_idx on public.debate_elecciones (user_id);
create index if not exists debate_argumentos_debate_idx on public.debate_argumentos (debate_id, created_at);
create index if not exists debate_argumentos_postura_idx on public.debate_argumentos (postura_id, debate_id);
create index if not exists debate_argumentos_parent_idx on public.debate_argumentos (parent_id, debate_id);
create index if not exists debate_argumentos_autor_fecha on public.debate_argumentos (author_id, created_at);
create index if not exists debate_reacciones_user_idx on public.debate_reacciones (user_id);

alter table public.debates enable row level security;
alter table public.debate_posturas enable row level security;
alter table public.debate_elecciones enable row level security;
alter table public.debate_argumentos enable row level security;
alter table public.debate_reacciones enable row level security;

-- ── Helpers (private, SECURITY DEFINER) ─────────────────────────
create or replace function private.puede_ver_debate(d uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.debates x where x.id = d
        and (private.es_admin() or private.es_miembro_curso(x.curso_id))); $$;

create or replace function private.modera_debate(d uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.debates x where x.id = d and private.es_docente_curso(x.curso_id)); $$;

create or replace function private.debate_estado(d uuid)
returns text language sql stable security definer set search_path = ''
as $$ select x.estado from public.debates x where x.id = d
        and (private.es_admin() or private.es_miembro_curso(x.curso_id)); $$;

create or replace function private.mi_postura(d uuid)
returns uuid language sql stable security definer set search_path = ''
as $$ select e.postura_id from public.debate_elecciones e where e.debate_id = d and e.user_id = auth.uid(); $$;

-- ── Triggers ────────────────────────────────────────────────────
create or replace function private.debates_proteger()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    new.creado_por := auth.uid();
    new.estado := 'abierto'; new.sintesis := null; new.sintesis_destacada := false; new.cerrado_en := null;
    new.created_at := now(); new.updated_at := now();
    return new;
  end if;
  new.id := old.id; new.curso_id := old.curso_id; new.creado_por := old.creado_por; new.created_at := old.created_at;
  if new.estado = 'cerrado' and old.estado = 'abierto' then new.cerrado_en := now();
  elsif new.estado = 'abierto' then new.cerrado_en := null; new.sintesis_destacada := false;
  else new.cerrado_en := old.cerrado_en;
  end if;
  if new.sintesis is distinct from old.sintesis and new.estado <> 'cerrado' then
    raise exception 'La síntesis se escribe cuando el debate está cerrado';
  end if;
  new.updated_at := now();
  return new;
end $$;

-- Mínimo 2 posturas por debate (se chequea al final de la transacción)
create or replace function private.debate_min_posturas()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.debates d where d.id = new.id)
     and (select count(*) from public.debate_posturas p where p.debate_id = new.id) < 2 then
    raise exception 'Un debate necesita al menos 2 posturas' using errcode = '23514';
  end if;
  return null;
end $$;

create or replace function private.debate_posturas_proteger()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'UPDATE' then new.id := old.id; new.debate_id := old.debate_id; end if;
  if private.debate_estado(new.debate_id) is distinct from 'abierto' then
    raise exception 'Las posturas se cambian solo con el debate abierto' using errcode = '42501';
  end if;
  return new;
end $$;

create or replace function private.debate_elecciones_proteger()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    new.user_id := auth.uid(); new.created_at := now();
  else
    new.debate_id := old.debate_id; new.user_id := old.user_id; new.created_at := old.created_at;
  end if;
  if private.debate_estado(new.debate_id) is distinct from 'abierto' then
    raise exception 'El debate está cerrado' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end $$;

create or replace function private.debate_argumentos_proteger()
returns trigger language plpgsql set search_path = ''
as $$
declare v_estado text; v_nombre text; v_pp uuid;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_estado := private.debate_estado(new.debate_id);
    if v_estado is null then raise exception 'El debate no existe o no sos miembro del curso' using errcode = '42501'; end if;
    if v_estado <> 'abierto' then raise exception 'El debate está cerrado' using errcode = '42501'; end if;
    v_nombre := private.mi_nombre();
    if v_nombre is null then raise exception 'Tu perfil no existe todavía' using errcode = '42501'; end if;
    new.author_id := auth.uid();
    new.author_name := left(v_nombre, 120);
    new.postura_id := private.mi_postura(new.debate_id);   -- la del autor, nunca la que mande el cliente
    new.oculto := false; new.editado := false;
    new.created_at := now(); new.updated_at := now();
    if new.parent_id is null then
      if new.postura_id is null and not private.modera_debate(new.debate_id) then
        raise exception 'Elegí una postura antes de argumentar';
      end if;
    else
      select a.parent_id into v_pp from public.debate_argumentos a where a.id = new.parent_id and a.debate_id = new.debate_id;
      if not found then raise exception 'El argumento al que respondés no existe'; end if;
      if v_pp is not null then raise exception 'Solo se puede replicar a un argumento principal'; end if;
    end if;
    return new;
  end if;
  new.id := old.id; new.debate_id := old.debate_id; new.postura_id := old.postura_id; new.parent_id := old.parent_id;
  new.author_id := old.author_id; new.author_name := old.author_name; new.created_at := old.created_at;
  if not private.modera_debate(old.debate_id) then new.oculto := old.oculto; end if;
  if old.author_id is distinct from auth.uid() then
    new.body := old.body; new.editado := old.editado;
  elsif new.body is distinct from old.body then
    if private.debate_estado(old.debate_id) is distinct from 'abierto' then
      raise exception 'El debate está cerrado' using errcode = '42501';
    end if;
    new.editado := true;
  else
    new.editado := old.editado;
  end if;
  new.updated_at := now();
  return new;
end $$;

create or replace function private.debate_reacciones_proteger()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  new.user_id := auth.uid(); new.created_at := now();
  return new;
end $$;

revoke all on function private.puede_ver_debate(uuid), private.modera_debate(uuid), private.debate_estado(uuid),
  private.mi_postura(uuid), private.debates_proteger(), private.debate_min_posturas(), private.debate_posturas_proteger(),
  private.debate_elecciones_proteger(), private.debate_argumentos_proteger(), private.debate_reacciones_proteger()
  from public, anon;
grant execute on function private.puede_ver_debate(uuid), private.modera_debate(uuid), private.debate_estado(uuid),
  private.mi_postura(uuid), private.debates_proteger(), private.debate_min_posturas(), private.debate_posturas_proteger(),
  private.debate_elecciones_proteger(), private.debate_argumentos_proteger(), private.debate_reacciones_proteger()
  to authenticated, service_role;

drop trigger if exists trg_debates_proteger on public.debates;
create trigger trg_debates_proteger before insert or update on public.debates
  for each row execute function private.debates_proteger();
drop trigger if exists trg_debates_min_posturas on public.debates;
create constraint trigger trg_debates_min_posturas after insert on public.debates
  deferrable initially deferred for each row execute function private.debate_min_posturas();
drop trigger if exists trg_debate_posturas_proteger on public.debate_posturas;
create trigger trg_debate_posturas_proteger before insert or update on public.debate_posturas
  for each row execute function private.debate_posturas_proteger();
drop trigger if exists trg_debate_elecciones_proteger on public.debate_elecciones;
create trigger trg_debate_elecciones_proteger before insert or update on public.debate_elecciones
  for each row execute function private.debate_elecciones_proteger();
drop trigger if exists trg_debate_argumentos_proteger on public.debate_argumentos;
create trigger trg_debate_argumentos_proteger before insert or update on public.debate_argumentos
  for each row execute function private.debate_argumentos_proteger();
drop trigger if exists trg_debate_argumentos_ritmo on public.debate_argumentos;
create trigger trg_debate_argumentos_ritmo before insert on public.debate_argumentos
  for each row execute function private.limitar_ritmo_conversacion();
drop trigger if exists trg_debate_reacciones_proteger on public.debate_reacciones;
create trigger trg_debate_reacciones_proteger before insert on public.debate_reacciones
  for each row execute function private.debate_reacciones_proteger();

-- ── RPC para crear el debate con sus posturas en una sola transacción ──
-- SECURITY INVOKER: la autorización la hace RLS (solo docente del curso o admin).
create or replace function public.crear_debate(p_curso uuid, p_pregunta text, p_descripcion text, p_posturas text[])
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare v_id uuid; v_nombres text[]; i int;
begin
  select coalesce(array_agg(n order by o), '{}') into v_nombres
    from (select btrim(x) n, min(o) o from unnest(p_posturas) with ordinality t(x, o)
           where btrim(coalesce(x, '')) <> '' group by btrim(x)) s;
  if array_length(v_nombres, 1) is null or array_length(v_nombres, 1) < 2 or array_length(v_nombres, 1) > 6 then
    raise exception 'Un debate necesita entre 2 y 6 posturas distintas' using errcode = '22023';
  end if;
  insert into public.debates (curso_id, pregunta, descripcion)
    values (p_curso, btrim(coalesce(p_pregunta, '')), coalesce(p_descripcion, '')) returning id into v_id;
  for i in 1 .. array_length(v_nombres, 1) loop
    insert into public.debate_posturas (debate_id, nombre, orden) values (v_id, v_nombres[i], i);
  end loop;
  return v_id;
end $$;
revoke all on function public.crear_debate(uuid, text, text, text[]) from public, anon;
grant execute on function public.crear_debate(uuid, text, text, text[]) to authenticated, service_role;

-- ── Políticas ───────────────────────────────────────────────────
-- debates: miembros/admin ven los de su curso; cualquiera logueado ve los de síntesis destacada;
-- anon solo los destacados (y solo las columnas de la portada, ver grants).
drop policy if exists debates_ver on public.debates;
create policy debates_ver on public.debates for select to authenticated
  using (sintesis_destacada or private.es_admin() or private.es_miembro_curso(curso_id));
drop policy if exists debates_ver_anon on public.debates;
create policy debates_ver_anon on public.debates for select to anon
  using (sintesis_destacada);
drop policy if exists debates_crear on public.debates;
create policy debates_crear on public.debates for insert to authenticated
  with check (private.es_docente_curso(curso_id) and creado_por = (select auth.uid()));
drop policy if exists debates_editar on public.debates;
create policy debates_editar on public.debates for update to authenticated
  using (private.es_docente_curso(curso_id)) with check (private.es_docente_curso(curso_id));
drop policy if exists debates_borrar on public.debates;
create policy debates_borrar on public.debates for delete to authenticated
  using (private.es_docente_curso(curso_id));

drop policy if exists debate_posturas_ver on public.debate_posturas;
create policy debate_posturas_ver on public.debate_posturas for select to authenticated
  using (private.puede_ver_debate(debate_id));
drop policy if exists debate_posturas_crear on public.debate_posturas;
create policy debate_posturas_crear on public.debate_posturas for insert to authenticated
  with check (private.modera_debate(debate_id));
drop policy if exists debate_posturas_editar on public.debate_posturas;
create policy debate_posturas_editar on public.debate_posturas for update to authenticated
  using (private.modera_debate(debate_id)) with check (private.modera_debate(debate_id));

-- la postura elegida por cada uno la ven él mismo y el docente (no hay conteo público)
drop policy if exists debate_elecciones_ver on public.debate_elecciones;
create policy debate_elecciones_ver on public.debate_elecciones for select to authenticated
  using (user_id = (select auth.uid()) or private.modera_debate(debate_id));
drop policy if exists debate_elecciones_crear on public.debate_elecciones;
create policy debate_elecciones_crear on public.debate_elecciones for insert to authenticated
  with check (user_id = (select auth.uid()) and private.puede_ver_debate(debate_id));
drop policy if exists debate_elecciones_editar on public.debate_elecciones;
create policy debate_elecciones_editar on public.debate_elecciones for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and private.puede_ver_debate(debate_id));

drop policy if exists debate_argumentos_ver on public.debate_argumentos;
create policy debate_argumentos_ver on public.debate_argumentos for select to authenticated
  using (private.puede_ver_debate(debate_id)
         and (not oculto or author_id = (select auth.uid()) or private.modera_debate(debate_id)));
drop policy if exists debate_argumentos_crear on public.debate_argumentos;
create policy debate_argumentos_crear on public.debate_argumentos for insert to authenticated
  with check (author_id = (select auth.uid()) and private.debate_estado(debate_id) = 'abierto');
drop policy if exists debate_argumentos_editar on public.debate_argumentos;
create policy debate_argumentos_editar on public.debate_argumentos for update to authenticated
  using ((author_id = (select auth.uid()) and private.puede_ver_debate(debate_id)) or private.modera_debate(debate_id))
  with check (private.puede_ver_debate(debate_id));
drop policy if exists debate_argumentos_borrar on public.debate_argumentos;
create policy debate_argumentos_borrar on public.debate_argumentos for delete to authenticated
  using ((author_id = (select auth.uid()) and private.puede_ver_debate(debate_id)) or private.modera_debate(debate_id));

-- reacciones: se ven/crean solo sobre argumentos visibles (RLS de argumentos aplica) y nunca sobre el propio
drop policy if exists debate_reacciones_ver on public.debate_reacciones;
create policy debate_reacciones_ver on public.debate_reacciones for select to authenticated
  using (exists (select 1 from public.debate_argumentos a where a.id = debate_reacciones.argumento_id));
drop policy if exists debate_reacciones_crear on public.debate_reacciones;
create policy debate_reacciones_crear on public.debate_reacciones for insert to authenticated
  with check (user_id = (select auth.uid())
    and exists (select 1 from public.debate_argumentos a
                 where a.id = debate_reacciones.argumento_id and a.author_id <> (select auth.uid())));
drop policy if exists debate_reacciones_borrar on public.debate_reacciones;
create policy debate_reacciones_borrar on public.debate_reacciones for delete to authenticated
  using (user_id = (select auth.uid()));

-- ── Grants ──────────────────────────────────────────────────────
revoke all on table public.debates, public.debate_posturas, public.debate_elecciones,
  public.debate_argumentos, public.debate_reacciones from public, anon, authenticated;
grant select, insert, update, delete on table public.debates, public.debate_argumentos to authenticated;
grant select, insert, update on table public.debate_posturas, public.debate_elecciones to authenticated;
grant select, insert, delete on table public.debate_reacciones to authenticated;
grant all on table public.debates, public.debate_posturas, public.debate_elecciones,
  public.debate_argumentos, public.debate_reacciones to service_role;
-- anon: solo lo que muestra la portada
grant select (id, pregunta, sintesis, sintesis_destacada, cerrado_en) on public.debates to anon;
