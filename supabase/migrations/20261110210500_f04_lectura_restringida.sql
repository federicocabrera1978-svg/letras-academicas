-- Hallazgo 4 (alto): cualquier cuenta logueada (cualquier Gmail) veía todos los textos,
-- comentarios, likes y perfiles de todos los cursos.
-- Arreglo:
--   * textos: los ve el autor, los miembros del curso (incluye docentes), el admin; y los
--     destacados (que ya son públicos en la home sin login) siguen visibles para todos.
--   * comentarios y likes: solo los de textos que el usuario puede ver.
--   * perfiles: uno mismo, quienes comparten curso con uno, y el admin; y solo las columnas
--     que usa la UI (id, name, username, avatar_url, rol).
-- Idempotente.
-- Los helpers se resuelven en public (antes de f06) o en private (después de f06).
set search_path = public, private, extensions;


create or replace function private.comparte_curso(p_otro uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.miembros_curso a
    join public.miembros_curso b on b.curso_id = a.curso_id
    where a.user_id = auth.uid() and b.user_id = p_otro
  );
$$;
revoke all on function private.comparte_curso(uuid) from public, anon;
grant execute on function private.comparte_curso(uuid) to authenticated, service_role;

drop policy if exists textos_select_auth on public.textos;
create policy textos_select_auth on public.textos for select to authenticated
  using (
    author_id = (select auth.uid())
    or destacado = true
    or es_admin()
    or (curso_id is not null and es_miembro_curso(curso_id))
  );

drop policy if exists comentarios_select on public.comentarios;
create policy comentarios_select on public.comentarios for select to authenticated
  using (exists (select 1 from public.textos t where t.id = comentarios.texto_id));  -- RLS de textos aplica

drop policy if exists likes_select on public.likes;
create policy likes_select on public.likes for select to authenticated
  using (exists (select 1 from public.textos t where t.id = likes.texto_id));

-- Comentar / dar like solo en textos que uno puede ver
drop policy if exists comentarios_insert on public.comentarios;
create policy comentarios_insert on public.comentarios for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and exists (select 1 from public.textos t where t.id = comentarios.texto_id)
  );

drop policy if exists likes_insert on public.likes;
create policy likes_insert on public.likes for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.textos t where t.id = likes.texto_id)
    and not exists (select 1 from public.textos t where t.id = likes.texto_id and t.author_id = (select auth.uid()))
  );

drop policy if exists perfiles_select on public.perfiles;
create policy perfiles_select on public.perfiles for select to authenticated
  using (
    id = (select auth.uid())
    or es_admin()
    or private.comparte_curso(id)
  );

-- Columnas mínimas (la UI pide columnas explícitas, nunca select=*)
revoke select on table public.perfiles from anon, authenticated;
grant select (id, name, username, avatar_url, rol) on public.perfiles to authenticated;

reset search_path;
