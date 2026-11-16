-- Foros y sala de debates (2/3): FOROS POR CURSO.
--   * El docente del curso (o el admin) crea el foro: título, consigna, abierto/cerrado.
--   * Los miembros del curso publican y responden en hilos de un nivel (parent_id).
--   * El docente fija, oculta mensajes y cierra/reabre el foro. El autor edita/borra lo suyo.
--   * Nada es visible para anon. La autoría (author_id, author_name) la pone el servidor.
--   * Máximo 10 mensajes por minuto por usuario (compartido con los debates) y largos por CHECK.
-- Idempotente.

-- ── Tablas ──────────────────────────────────────────────────────
create table if not exists public.foros (
  id          uuid primary key default gen_random_uuid(),
  curso_id    uuid not null references public.cursos(id) on delete cascade,
  titulo      text not null,
  consigna    text not null default '',
  estado      text not null default 'abierto',
  creado_por  uuid default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint foros_largos check (char_length(btrim(titulo)) between 1 and 200 and char_length(consigna) <= 5000),
  constraint foros_estado check (estado in ('abierto','cerrado'))
);

create table if not exists public.foro_mensajes (
  id          uuid primary key default gen_random_uuid(),
  foro_id     uuid not null references public.foros(id) on delete cascade,
  parent_id   uuid,
  author_id   uuid not null references auth.users(id),
  author_name text not null,
  body        text not null,
  fijado      boolean not null default false,
  oculto      boolean not null default false,
  editado     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint foro_mensajes_id_foro unique (id, foro_id),
  -- la respuesta tiene que ser del mismo foro
  constraint foro_mensajes_parent_fkey foreign key (parent_id, foro_id)
    references public.foro_mensajes (id, foro_id) on delete cascade,
  constraint foro_mensajes_largos check (char_length(btrim(body)) between 1 and 5000 and char_length(author_name) <= 120)
);

create index if not exists foros_curso_id_idx on public.foros (curso_id, created_at);
create index if not exists foros_creado_por_idx on public.foros (creado_por);
create index if not exists foro_mensajes_foro_idx on public.foro_mensajes (foro_id, created_at);
create index if not exists foro_mensajes_parent_idx on public.foro_mensajes (parent_id, foro_id);
create index if not exists foro_mensajes_autor_fecha on public.foro_mensajes (author_id, created_at);

alter table public.foros enable row level security;
alter table public.foro_mensajes enable row level security;

-- ── Helpers (private, SECURITY DEFINER) ─────────────────────────
create or replace function private.puede_ver_foro(f uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.foros x where x.id = f
        and (private.es_admin() or private.es_miembro_curso(x.curso_id))); $$;

create or replace function private.modera_foro(f uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.foros x where x.id = f and private.es_docente_curso(x.curso_id)); $$;

-- estado del foro si el usuario lo puede ver; null si no existe o no tiene acceso
create or replace function private.foro_estado(f uuid)
returns text language sql stable security definer set search_path = ''
as $$ select x.estado from public.foros x where x.id = f
        and (private.es_admin() or private.es_miembro_curso(x.curso_id)); $$;

-- ── Triggers de protección (SECURITY INVOKER: current_user = rol de la API) ──
create or replace function private.foros_proteger()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    new.creado_por := auth.uid();
    new.estado := 'abierto';
    new.created_at := now();
  else
    new.id := old.id;
    new.curso_id := old.curso_id;
    new.creado_por := old.creado_por;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end $$;

create or replace function private.foro_mensajes_proteger()
returns trigger language plpgsql set search_path = ''
as $$
declare v_estado text; v_nombre text; v_pp uuid;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    v_estado := private.foro_estado(new.foro_id);
    if v_estado is null then raise exception 'El foro no existe o no sos miembro del curso' using errcode = '42501'; end if;
    if v_estado <> 'abierto' then raise exception 'El foro está cerrado' using errcode = '42501'; end if;
    v_nombre := private.mi_nombre();
    if v_nombre is null then raise exception 'Tu perfil no existe todavía' using errcode = '42501'; end if;
    new.author_id := auth.uid();
    new.author_name := left(v_nombre, 120);
    new.fijado := false; new.oculto := false; new.editado := false;
    new.created_at := now(); new.updated_at := now();
    if new.parent_id is not null then
      select m.parent_id into v_pp from public.foro_mensajes m where m.id = new.parent_id and m.foro_id = new.foro_id;
      if not found then raise exception 'El mensaje al que respondés no existe'; end if;
      if v_pp is not null then raise exception 'Solo se puede responder a un mensaje principal'; end if;
    end if;
    return new;
  end if;
  -- UPDATE: nada de cambiar autoría, foro ni hilo
  new.id := old.id; new.foro_id := old.foro_id; new.parent_id := old.parent_id;
  new.author_id := old.author_id; new.author_name := old.author_name; new.created_at := old.created_at;
  if not private.modera_foro(old.foro_id) then
    new.fijado := old.fijado; new.oculto := old.oculto;
  end if;
  if old.author_id is distinct from auth.uid() then
    new.body := old.body; new.editado := old.editado;          -- el docente modera, no reescribe
  elsif new.body is distinct from old.body then
    if private.foro_estado(old.foro_id) is distinct from 'abierto' then
      raise exception 'El foro está cerrado' using errcode = '42501';
    end if;
    new.editado := true;
  else
    new.editado := old.editado;
  end if;
  new.updated_at := now();
  return new;
end $$;

revoke all on function private.puede_ver_foro(uuid), private.modera_foro(uuid), private.foro_estado(uuid),
  private.foros_proteger(), private.foro_mensajes_proteger() from public, anon;
grant execute on function private.puede_ver_foro(uuid), private.modera_foro(uuid), private.foro_estado(uuid),
  private.foros_proteger(), private.foro_mensajes_proteger() to authenticated, service_role;

drop trigger if exists trg_foros_proteger on public.foros;
create trigger trg_foros_proteger before insert or update on public.foros
  for each row execute function private.foros_proteger();
drop trigger if exists trg_foro_mensajes_proteger on public.foro_mensajes;
create trigger trg_foro_mensajes_proteger before insert or update on public.foro_mensajes
  for each row execute function private.foro_mensajes_proteger();
drop trigger if exists trg_foro_mensajes_ritmo on public.foro_mensajes;
create trigger trg_foro_mensajes_ritmo before insert on public.foro_mensajes
  for each row execute function private.limitar_ritmo_conversacion();

-- ── Políticas (solo authenticated; anon no tiene ninguna) ───────
drop policy if exists foros_ver on public.foros;
create policy foros_ver on public.foros for select to authenticated
  using (private.es_admin() or private.es_miembro_curso(curso_id));
drop policy if exists foros_crear on public.foros;
create policy foros_crear on public.foros for insert to authenticated
  with check (private.es_docente_curso(curso_id) and creado_por = (select auth.uid()));
drop policy if exists foros_editar on public.foros;
create policy foros_editar on public.foros for update to authenticated
  using (private.es_docente_curso(curso_id)) with check (private.es_docente_curso(curso_id));
drop policy if exists foros_borrar on public.foros;
create policy foros_borrar on public.foros for delete to authenticated
  using (private.es_docente_curso(curso_id));

drop policy if exists foro_mensajes_ver on public.foro_mensajes;
create policy foro_mensajes_ver on public.foro_mensajes for select to authenticated
  using (private.puede_ver_foro(foro_id)
         and (not oculto or author_id = (select auth.uid()) or private.modera_foro(foro_id)));
drop policy if exists foro_mensajes_crear on public.foro_mensajes;
create policy foro_mensajes_crear on public.foro_mensajes for insert to authenticated
  with check (author_id = (select auth.uid()) and private.foro_estado(foro_id) = 'abierto');
drop policy if exists foro_mensajes_editar on public.foro_mensajes;
create policy foro_mensajes_editar on public.foro_mensajes for update to authenticated
  using ((author_id = (select auth.uid()) and private.puede_ver_foro(foro_id)) or private.modera_foro(foro_id))
  with check (private.puede_ver_foro(foro_id));
drop policy if exists foro_mensajes_borrar on public.foro_mensajes;
create policy foro_mensajes_borrar on public.foro_mensajes for delete to authenticated
  using ((author_id = (select auth.uid()) and private.puede_ver_foro(foro_id)) or private.modera_foro(foro_id));

-- ── Grants (Supabase da ALL por defecto a anon/authenticated en tablas nuevas: se recortan) ──
revoke all on table public.foros, public.foro_mensajes from public, anon, authenticated;
grant select, insert, update, delete on table public.foros, public.foro_mensajes to authenticated;
grant all on table public.foros, public.foro_mensajes to service_role;
