-- Hallazgo 3 (alto): cualquier docente (rol global 'profesor') podía editar/borrar textos y
-- borrar comentarios de CUALQUIER curso. Arreglo: moderación solo para docentes de ese curso
-- (es_docente_curso) o admin. El autor sigue pudiendo editar/borrar lo suyo. Idempotente.
-- (La autoría pasa a author_id en la migración f02; acá se mantiene author_username.)
-- Los helpers se resuelven en public (antes de f06) o en private (después de f06).
set search_path = public, private, extensions;


drop policy if exists textos_update on public.textos;
create policy textos_update on public.textos
  for update to authenticated
  using (
    author_username = mi_username()
    or es_admin()
    or (curso_id is not null and es_docente_curso(curso_id))
  )
  with check (
    author_username = mi_username()
    or es_admin()
    or (curso_id is not null and es_docente_curso(curso_id))
  );

drop policy if exists textos_delete on public.textos;
create policy textos_delete on public.textos
  for delete to authenticated
  using (
    author_username = mi_username()
    or es_admin()
    or (curso_id is not null and es_docente_curso(curso_id))
  );

drop policy if exists comentarios_delete on public.comentarios;
create policy comentarios_delete on public.comentarios
  for delete to authenticated
  using (
    author_username = mi_username()
    or es_admin()
    or exists (
      select 1 from public.textos t
      where t.id = comentarios.texto_id
        and t.curso_id is not null
        and es_docente_curso(t.curso_id)
    )
  );

reset search_path;
