-- Correr DESPUÉS de f02 (solo lectura). Esperado: total igual que "antes", sin_author_id = 0
-- y username_distinto = 0 (author_username sigue coincidiendo con el perfil dueño).
select 'textos' as tabla, count(*) as total,
       count(*) filter (where t.author_id is null) as sin_author_id,
       count(*) filter (where p.id is not null and p.username is distinct from t.author_username) as username_distinto
from public.textos t left join public.perfiles p on p.id = t.author_id
union all
select 'comentarios', count(*), count(*) filter (where c.author_id is null),
       count(*) filter (where p.id is not null and p.username is distinct from c.author_username)
from public.comentarios c left join public.perfiles p on p.id = c.author_id
union all
select 'likes', count(*), count(*) filter (where l.user_id is null),
       count(*) filter (where p.id is not null and p.username is distinct from l.user_username)
from public.likes l left join public.perfiles p on p.id = l.user_id;
