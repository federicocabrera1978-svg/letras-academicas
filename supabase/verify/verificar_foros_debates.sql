-- Verificación SOLO LECTURA después de aplicar 20261116200100..200300. Todas las filas deben decir ok = true.
select 'tablas con RLS' chequeo, count(*) = 7 ok from pg_class
 where relnamespace = 'public'::regnamespace and relrowsecurity
   and relname in ('foros','foro_mensajes','debates','debate_posturas','debate_elecciones','debate_argumentos','debate_reacciones')
union all
select 'anon sin privilegios de tabla', not exists (select 1 from information_schema.role_table_grants
 where grantee = 'anon' and table_schema = 'public'
   and table_name in ('foros','foro_mensajes','debates','debate_posturas','debate_elecciones','debate_argumentos','debate_reacciones'))
union all
select 'anon: solo 5 columnas de debates', (select count(*) from information_schema.column_privileges
 where grantee = 'anon' and table_schema = 'public' and table_name = 'debates') = 5
 and not exists (select 1 from information_schema.column_privileges where grantee = 'anon' and table_schema = 'public'
   and table_name in ('foros','foro_mensajes','debate_posturas','debate_elecciones','debate_argumentos','debate_reacciones'))
union all
select 'helpers nuevos en private con search_path vacío', (select count(*) from pg_proc
 where pronamespace = 'private'::regnamespace and proconfig @> array['search_path=""']
   and proname in ('puede_ver_foro','modera_foro','foro_estado','puede_ver_debate','modera_debate','debate_estado','mi_postura','conversacion_recientes','mi_nombre')) = 9
union all
select 'anon no ejecuta funciones nuevas', not exists (select 1 from pg_proc p
 where (p.pronamespace = 'private'::regnamespace or p.proname = 'crear_debate') and has_function_privilege('anon', p.oid, 'execute')
   and p.proname in ('puede_ver_foro','modera_foro','foro_estado','puede_ver_debate','modera_debate','debate_estado','mi_postura',
                     'conversacion_recientes','mi_nombre','limitar_ritmo_conversacion','crear_debate'))
union all
select 'crear_debate es SECURITY INVOKER', (select not prosecdef from pg_proc where proname = 'crear_debate' and pronamespace = 'public'::regnamespace)
union all
select 'triggers de ritmo y protección', (select count(*) from pg_trigger where not tgisinternal and tgname in
 ('trg_foros_proteger','trg_foro_mensajes_proteger','trg_foro_mensajes_ritmo','trg_debates_proteger','trg_debates_min_posturas',
  'trg_debate_posturas_proteger','trg_debate_elecciones_proteger','trg_debate_argumentos_proteger','trg_debate_argumentos_ritmo',
  'trg_debate_reacciones_proteger')) = 10
union all
select 'schema private sigue sin anon', not has_schema_privilege('anon', 'private', 'usage');
