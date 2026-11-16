-- ROLLBACK de 20261116200100..20261116200300 (foros y sala de debates).
-- Deja el catálogo exactamente como después de security-fixes-nov (no toca textos, perfiles,
-- cursos ni los helpers existentes). BORRA los foros, mensajes, debates, argumentos y
-- reacciones que se hayan creado: hacer backup antes si ya hay contenido.
-- Correr en UNA transacción:  psql -1 -f rollback_foros_debates.sql   Idempotente.

drop table if exists public.debate_reacciones, public.debate_argumentos, public.debate_elecciones,
  public.debate_posturas, public.debates, public.foro_mensajes, public.foros cascade;

drop function if exists public.crear_debate(uuid, text, text, text[]);
drop function if exists private.puede_ver_debate(uuid), private.modera_debate(uuid), private.debate_estado(uuid),
  private.mi_postura(uuid), private.debates_proteger(), private.debate_min_posturas(), private.debate_posturas_proteger(),
  private.debate_elecciones_proteger(), private.debate_argumentos_proteger(), private.debate_reacciones_proteger();
drop function if exists private.puede_ver_foro(uuid), private.modera_foro(uuid), private.foro_estado(uuid),
  private.foros_proteger(), private.foro_mensajes_proteger();
drop function if exists private.conversacion_recientes(uuid), private.limitar_ritmo_conversacion(), private.mi_nombre();
