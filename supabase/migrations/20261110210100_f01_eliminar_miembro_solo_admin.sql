-- Hallazgo 1 (crítico): cualquier docente podía borrar perfiles, incluido el del admin;
-- al volver a entrar, la cuenta se recreaba como 'alumno' y se perdía el rol.
-- Arreglo: el borrado directo de perfiles se cierra (sin grant DELETE) y solo se puede
-- eliminar un miembro con la RPC eliminar_miembro(), que exige ser admin y nunca
-- permite borrarse a sí mismo ni a otro admin. Idempotente.
-- Los helpers se resuelven en public (antes de f06) o en private (después de f06).
set search_path = public, private, extensions;


drop policy if exists perfiles_delete on public.perfiles;
-- Defensa en profundidad: aunque alguien vuelva a otorgar DELETE, la política sigue exigiendo admin.
create policy perfiles_delete on public.perfiles
  for delete to authenticated
  using (es_admin() and id <> (select auth.uid()) and rol is distinct from 'admin');

revoke delete on table public.perfiles from anon, authenticated;

create or replace function public.eliminar_miembro(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_rol text;
begin
  if auth.uid() is null or not es_admin() then
    raise exception 'Solo el administrador puede eliminar miembros' using errcode = '42501';
  end if;
  if p_user is null or p_user = auth.uid() then
    raise exception 'No podés eliminar tu propia cuenta' using errcode = '42501';
  end if;
  select rol into v_rol from public.perfiles where id = p_user for update;
  if not found then
    raise exception 'Miembro no encontrado' using errcode = 'P0002';
  end if;
  if v_rol = 'admin' then
    raise exception 'No se puede eliminar a un administrador' using errcode = '42501';
  end if;
  -- Los textos/comentarios del miembro NO se borran (quedan con su autoría).
  delete from public.miembros_curso where user_id = p_user;
  delete from public.perfiles where id = p_user;
end
$$;

revoke all on function public.eliminar_miembro(uuid) from public, anon;
grant execute on function public.eliminar_miembro(uuid) to authenticated, service_role;

reset search_path;
