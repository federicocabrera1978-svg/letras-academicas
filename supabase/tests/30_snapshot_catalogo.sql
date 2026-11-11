-- Foto del catálogo relevante (para comparar baseline / migrado / rollback)
select 'POL '||tablename||'.'||policyname||' '||cmd||' '||roles::text||' Q='||coalesce(qual,'')||' C='||coalesce(with_check,'') from pg_policies where schemaname='public' order by 1;
select 'FN '||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') def='||p.prosecdef||' cfg='||coalesce(p.proconfig::text,'')||' acl='||coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x),'')||' md5='||md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') order by 1;
select 'TBL '||relname||' acl='||coalesce((select string_agg(x::text, ',' order by x::text) from unnest(relacl) x),'') from pg_class where relnamespace='public'::regnamespace and relkind='r' order by 1;
select 'COLACL '||c.relname||'.'||a.attname||' '||(select string_agg(x::text, ',' order by x::text) from unnest(a.attacl) x) from pg_attribute a join pg_class c on c.oid=a.attrelid where c.relnamespace='public'::regnamespace and c.relkind='r' and a.attacl is not null order by 1;
select 'COL '||table_name||'.'||column_name||' '||data_type||' null='||is_nullable||' def='||coalesce(column_default,'') from information_schema.columns where table_schema='public' order by 1;
select 'CON '||conrelid::regclass::text||'.'||conname||' '||pg_get_constraintdef(oid) from pg_constraint where connamespace='public'::regnamespace order by 1;
select 'IDX '||indexdef from pg_indexes where schemaname='public' order by 1;
select 'TRG '||c.relname||'.'||tg.tgname||' '||pg_get_triggerdef(tg.oid) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid where c.relnamespace='public'::regnamespace and not tg.tgisinternal order by 1;
select 'SCHEMA '||nspname||' acl='||coalesce((select string_agg(x::text, ',' order by x::text) from unnest(nspacl) x),'') from pg_namespace where nspname in ('public','private') order by 1;
