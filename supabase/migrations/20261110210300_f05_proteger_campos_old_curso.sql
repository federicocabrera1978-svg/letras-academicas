-- Hallazgo 5 (medio): textos_proteger_campos calculaba "puede destacar" con new.curso_id,
-- un valor que manda el cliente. Arreglo: en UPDATE se usa old.curso_id (el curso real
-- del texto). También se compara autoría con IS DISTINCT FROM para que un NULL no
-- deje pasar cambios de título/cuerpo. Idempotente (create or replace).
-- Los helpers se resuelven en public (antes de f06) o en private (después de f06).
set search_path = public, private, extensions;


create or replace function public.textos_proteger_campos()
returns trigger
language plpgsql
set search_path = public, private
as $function$
declare puede_destacar boolean;
begin
  if current_user not in ('anon','authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    new.likes := 0;
    new.destacado := false;
    new.entregada_tarde := false;
    new.author_name := coalesce((select name from perfiles where id = auth.uid()), new.author_name);
    if new.curso_id is not null and not es_miembro_curso(new.curso_id) then
      raise exception 'No sos miembro de ese curso';
    end if;
    return new;
  end if;
  -- UPDATE: decidir con el curso REAL (old), nunca con lo que manda el cliente.
  puede_destacar := es_admin() or (old.curso_id is not null and es_docente_curso(old.curso_id));
  new.likes := old.likes;
  new.author_username := old.author_username;
  new.author_name := old.author_name;
  new.curso_id := old.curso_id;
  new.consigna_id := old.consigna_id;
  new.entregada_tarde := old.entregada_tarde;
  if not puede_destacar then new.destacado := old.destacado; end if;
  if old.author_username is distinct from mi_username() then
    new.title := old.title; new.body := old.body; new.type := old.type;
  end if;
  return new;
end $function$;

reset search_path;
