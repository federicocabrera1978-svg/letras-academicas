-- Hallazgo 12 (medio): el rol anon (cualquiera sin login, con la publishable key) tenía
-- INSERT/UPDATE/DELETE (y MAINTAIN) en textos, comentarios, likes y perfiles. Hoy lo frenaba
-- solo RLS; se quita el privilegio para no depender de una única capa.
-- anon conserva únicamente SELECT de las columnas que usa la home pública sobre textos
-- (y RLS sigue limitando a destacado = true). Idempotente.

revoke all on table public.textos, public.comentarios, public.likes, public.perfiles from anon;
grant select (id, title, type, body, author_name, created_at, destacado) on public.textos to anon;

-- MAINTAIN (PG17) no lo necesita la app
revoke maintain on table public.textos, public.comentarios, public.likes, public.perfiles,
  public.cursos, public.miembros_curso, public.instituciones from authenticated;
-- likes no se editan (solo alta/baja)
revoke update on table public.likes from authenticated;
