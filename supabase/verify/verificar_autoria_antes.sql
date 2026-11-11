-- Correr ANTES de f02 (solo lectura). Debe dar sin_autor_identificable = 0 en las 3 filas;
-- si no, f02 abortaría: hay textos/comentarios/likes cuyo username no tiene perfil.
select 'textos' as tabla, count(*) as total,
       count(*) filter (where not exists (select 1 from public.perfiles p where p.username = t.author_username)) as sin_autor_identificable
from public.textos t
union all
select 'comentarios', count(*),
       count(*) filter (where not exists (select 1 from public.perfiles p where p.username = c.author_username))
from public.comentarios c
union all
select 'likes', count(*),
       count(*) filter (where not exists (select 1 from public.perfiles p where p.username = l.user_username))
from public.likes l;
