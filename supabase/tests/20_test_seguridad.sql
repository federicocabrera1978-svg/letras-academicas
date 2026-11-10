-- SOLO PRUEBAS LOCALES: asserts de los hallazgos 1-6 y 12 tras aplicar las migraciones.
\set ON_ERROR_STOP 1
\set A '''00000000-0000-0000-0000-00000000000a'''
\set ANA '''00000000-0000-0000-0000-000000000001'''
\set BETO '''00000000-0000-0000-0000-000000000002'''
\set CARLA '''00000000-0000-0000-0000-000000000003'''
\set DANI '''00000000-0000-0000-0000-000000000004'''
\set U5 '''00000000-0000-0000-0000-000000000005'''
\set U6 '''00000000-0000-0000-0000-000000000006'''
\set T_ANA '''30000000-0000-0000-0000-000000000001'''
\set T_BETO '''30000000-0000-0000-0000-000000000002'''
\set T_DANI '''30000000-0000-0000-0000-000000000003'''

-- ===== Hallazgo 2: backfill completo
select tests.ok((select count(*) from textos where author_id is null) = 0, 'f02: 0 textos sin author_id');
select tests.ok((select count(*) from comentarios where author_id is null) = 0, 'f02: 0 comentarios sin author_id');
select tests.ok((select count(*) from likes where user_id is null) = 0, 'f02: 0 likes sin user_id');
select tests.ok((select count(*) from textos t join perfiles p on p.id = t.author_id where p.username <> t.author_username) = 0, 'f02: author_id coincide con author_username');
select tests.ok((select count(*) from textos) = 4 and (select count(*) from comentarios) = 2, 'f02: no se perdió ningún texto/comentario');

-- ===== Hallazgo 1: borrado de perfiles
select tests.login(:CARLA);
select tests.falla($$delete from perfiles where id = '00000000-0000-0000-0000-00000000000a'$$, 'f01: profesor no puede DELETE directo del admin');
select tests.falla($$select eliminar_miembro('00000000-0000-0000-0000-00000000000a')$$, 'f01: profesor no puede usar eliminar_miembro');
select tests.falla($$select eliminar_miembro('00000000-0000-0000-0000-000000000004')$$, 'f01: profesor no puede eliminar alumnos');
select tests.login(:A);
select tests.falla($$delete from perfiles where id = '00000000-0000-0000-0000-000000000002'$$, 'f01: ni el admin borra perfiles por DELETE directo');
select tests.falla($$select eliminar_miembro('00000000-0000-0000-0000-00000000000a')$$, 'f01: admin no puede eliminarse a sí mismo');
select tests.su();
insert into auth.users values ('00000000-0000-0000-0000-0000000000a2','otro.admin@gmail.com');
insert into perfiles (id, name, username, rol) values ('00000000-0000-0000-0000-0000000000a2','Admin 2','admin2','admin');
select tests.login(:A);
select tests.falla($$select eliminar_miembro('00000000-0000-0000-0000-0000000000a2')$$, 'f01: admin no puede eliminar a otro admin');
select eliminar_miembro(:BETO);
select tests.su();
select tests.ok(not exists (select 1 from perfiles where id = :BETO), 'f01: admin elimina a un alumno');
select tests.ok((select count(*) from textos where author_id = :BETO) = 1, 'f01: los textos del eliminado se conservan');
select tests.ok((select rol from perfiles where id = :A) = 'admin', 'f01: el admin conserva su rol');
select tests.anon();
select tests.falla($$select eliminar_miembro('00000000-0000-0000-0000-000000000001')$$, 'f01: anon no puede llamar eliminar_miembro');

-- ===== Hallazgo 2: username lo fija el servidor y no se "hereda" autoría
select tests.su();
update auth.users set email = 'beto.alumno@yahoo.com' where id = :U6;
select tests.login(:U6);
insert into perfiles (id, name, username, color, avatar_url) values (:U6, 'Impostor', 'betoalumno', '#2d5a8e', 'https://x.example/a.png');
select tests.ok((select username from perfiles where id = :U6) = 'betoalumno2', 'f02: username ya usado en textos de otra cuenta -> sufijo (betoalumno2)');
select tests.ok(tests.n($$update textos set title = 'robado' where id = '30000000-0000-0000-0000-000000000002' returning 1$$) = 0, 'f02: el nuevo usuario no puede editar textos del eliminado');
select tests.ok(tests.n($$delete from textos where id = '30000000-0000-0000-0000-000000000002' returning 1$$) = 0, 'f02: ni borrarlos');
select tests.login(:U5);
insert into perfiles (id, name, username, color) values (:U5, 'Ana H', 'federicoadmin', '#2d5a8e');
select tests.ok((select username from perfiles where id = :U5) = 'anaalumna2', 'f02: el cliente no elige username (deriva del email y es único)');
select tests.ok((select rol from perfiles where id = :U5) = 'alumno', 'f02: rol forzado a alumno');
select tests.falla($$update perfiles set username = 'admin' where id = '00000000-0000-0000-0000-000000000005'$$, 'f02: no se puede cambiar username');
-- Beto vuelve a entrar (misma cuenta): recupera su username y sus textos
select tests.login(:BETO);
insert into perfiles (id, name, username, color) values (:BETO, 'Beto', 'cualquiera', '#2d5a8e');
select tests.ok((select username from perfiles where id = :BETO) = 'betoalumno', 'f02: misma cuenta recupera su username');
select unirse_a_curso('GENERAL');
select tests.ok(tests.n($$update textos set title = 'Texto Beto (editado)' where id = '30000000-0000-0000-0000-000000000002' returning 1$$) = 1, 'f02: misma cuenta sigue siendo dueña de sus textos');
-- Suplantar autoría en el insert
select tests.login(:ANA);
insert into textos (title, author_username, author_name, author_id, type, body, curso_id)
  values ('Spoof', 'federicoadmin', 'Federico', '00000000-0000-0000-0000-00000000000a', 'ensayo', '<p>s</p>', '20000000-0000-0000-0000-000000000001');
select tests.su();
select tests.ok((select author_id = :ANA and author_username = 'anaalumna' and author_name = 'Ana' from textos where title = 'Spoof'), 'f02: author_id/username/name los fija el servidor');

-- ===== Hallazgo 3: moderación por curso
select tests.login(:CARLA);   -- profesora, docente solo de OTRO
select tests.ok(tests.n($$update textos set destacado = true where id = '30000000-0000-0000-0000-000000000001' returning 1$$) = 0, 'f03: docente de otro curso no modera textos de GENERAL');
select tests.ok(tests.n($$delete from textos where id = '30000000-0000-0000-0000-000000000001' returning 1$$) = 0, 'f03: ni los borra');
select tests.ok(tests.n($$delete from comentarios where texto_id = '30000000-0000-0000-0000-000000000001' returning 1$$) = 0, 'f03: ni borra comentarios de GENERAL');
select tests.ok(tests.n($$update textos set destacado = true, title = 'hack' where id = '30000000-0000-0000-0000-000000000003' returning 1$$) = 1, 'f03: docente del curso puede destacar');
select tests.su();
select tests.ok((select destacado and title = 'Texto Dani (otro curso)' from textos where id = :T_DANI), 'f03: destacó pero no cambió el título ajeno');
select tests.login(:ANA);
select tests.ok(tests.n($$update textos set title = 'Ana editado' where id = '30000000-0000-0000-0000-000000000001' returning 1$$) = 1, 'f03: el autor edita lo suyo');
select tests.ok(tests.n($$update textos set destacado = true where id = '30000000-0000-0000-0000-000000000001' returning 1$$) = 1, 'f03/f05: el autor puede hacer UPDATE...');
select tests.su();
select tests.ok((select not destacado from textos where id = :T_ANA), '...pero no autodestacarse');
select tests.login(:A);
select tests.ok(tests.n($$delete from comentarios where texto_id = '30000000-0000-0000-0000-000000000003' returning 1$$) = 1, 'f03: admin modera comentarios en cualquier curso');

-- ===== Hallazgo 5: puede_destacar usa old.curso_id
select tests.login(:CARLA);
select unirse_a_curso('GENERAL');  -- Carla es alumna en GENERAL y docente en OTRO
insert into textos (title, author_username, author_name, type, body, curso_id) values ('Carla en General', 'x', 'x', 'ensayo', '<p>c</p>', '20000000-0000-0000-0000-000000000001');
update textos set destacado = true, curso_id = '20000000-0000-0000-0000-000000000002' where title = 'Carla en General';
select tests.su();
select tests.ok((select not destacado and curso_id = '20000000-0000-0000-0000-000000000001' from textos where title = 'Carla en General'), 'f05: mandar curso_id ajeno no habilita destacar ni mover el texto');

-- ===== Hallazgo 4: lectura restringida
select tests.login(:DANI);  -- alumno solo de OTRO
select tests.ok(not exists (select 1 from textos where id = :T_ANA), 'f04: alumno de otro curso no ve textos de GENERAL');
select tests.ok(exists (select 1 from textos where id = :T_DANI), 'f04: ve los de su curso');
select tests.ok(exists (select 1 from textos where id = :T_BETO), 'f04: ve los destacados (también públicos en la home)');
select tests.ok(not exists (select 1 from comentarios where texto_id = :T_ANA), 'f04: no ve comentarios de textos ajenos');
select tests.ok(not exists (select 1 from likes where texto_id = :T_ANA), 'f04: no ve likes de textos ajenos');
select tests.ok((select count(*) from perfiles) = 2, 'f04: perfiles visibles = él mismo + quienes comparten curso');
select tests.falla($$select created_at from perfiles$$, 'f04: columnas no necesarias de perfiles no son legibles');
select tests.falla($$select * from perfiles$$, 'f04: select * de perfiles rechazado (la UI pide columnas)');
select tests.falla($$insert into comentarios (texto_id, author_username, author_name, body) values ('30000000-0000-0000-0000-000000000001','d','d','x')$$, 'f04: no comenta textos que no ve');
select tests.falla($$insert into likes (texto_id, user_username) values ('30000000-0000-0000-0000-000000000001','d')$$, 'f04: no da like a textos que no ve');
select tests.login(:ANA);
select tests.ok(exists (select 1 from textos where id = :T_BETO) and (select count(*) from comentarios where texto_id = :T_ANA) = 1, 'f04: miembros del curso leen textos y devoluciones del curso');
select tests.ok(not exists (select 1 from textos where id = :T_DANI and not destacado), 'f04: ...pero no los de otro curso');
select tests.login(:A);
select tests.ok((select count(*) from textos) = (select count(*) from textos), 'f04: admin consulta');
select tests.su();
select tests.login(:A);
select tests.ok((select count(*) from perfiles) = 8, 'f04: admin ve todos los perfiles');

-- ===== Hallazgo 15: like / unlike real
select tests.login(:BETO);
select tests.falla($$insert into likes (texto_id, user_username) values ('30000000-0000-0000-0000-000000000002','b')$$, 'f15: no se puede dar like al propio texto');
select tests.login(:ANA);
insert into likes (texto_id, user_username) values (:T_BETO, 'spoof');
select tests.su();
select tests.ok((select likes from textos where id = :T_BETO) = 1 and exists (select 1 from likes where texto_id = :T_BETO and user_id = :ANA and user_username = 'anaalumna'), 'f15: like guardado con user_id del servidor y contador = 1');
select tests.login(:DANI);
select tests.ok(tests.n($$delete from likes where texto_id = '30000000-0000-0000-0000-000000000002' returning 1$$) = 0, 'f15: no se puede quitar el like de otro');
select tests.login(:ANA);
select tests.ok(tests.n($$delete from likes where texto_id = '30000000-0000-0000-0000-000000000002' and user_id = '00000000-0000-0000-0000-000000000001' returning 1$$) = 1, 'f15: unlike del propio like');
select tests.su();
select tests.ok((select likes from textos where id = :T_BETO) = 0, 'f15: contador vuelve a 0');

-- ===== Hallazgo 6: helpers fuera de la API
select tests.ok(to_regprocedure('public.es_admin()') is null and to_regprocedure('public.es_profesor()') is null and to_regprocedure('public.es_docente_curso(uuid)') is null and to_regprocedure('public.es_miembro_curso(uuid)') is null and to_regprocedure('public.mi_username()') is null, 'f06: ya no hay helpers en public');
select tests.ok(to_regprocedure('public.habilitar_docente(uuid,boolean)') is not null and to_regprocedure('public.unirse_a_curso(text)') is not null and to_regprocedure('public.eliminar_miembro(uuid)') is not null, 'f06: quedan las RPC de la app');
select tests.ok((select bool_and(array_to_string(p.proconfig, ',') = 'search_path=""') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private'), 'f06: search_path vacío y fijo en private');
select tests.ok((select bool_and(p.proconfig is not null) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f'), 'f06: todas las funciones de public tienen search_path fijo');
select tests.anon();
select tests.falla($$select private.es_admin()$$, 'f06: anon no puede ejecutar helpers');
select tests.login(:A);
select habilitar_docente(:DANI, true);
select tests.su();
select tests.ok((select rol from perfiles where id = :DANI) = 'profesor', 'f06: habilitar_docente sigue funcionando');

-- ===== Hallazgo 12: anon sin escrituras
select tests.anon();
select tests.falla($$insert into textos (title, author_username, author_name, type, body) values ('a','a','a','a','a')$$, 'f12: anon no inserta textos');
select tests.falla($$update textos set title = 'x'$$, 'f12: anon no edita textos');
select tests.falla($$delete from comentarios$$, 'f12: anon no borra comentarios');
select tests.falla($$insert into likes (texto_id, user_username) values (null, 'x')$$, 'f12: anon no da likes');
select tests.falla($$select * from perfiles$$, 'f12: anon no lee perfiles');
select tests.falla($$select author_username from textos$$, 'f12: anon no lee columnas internas de textos');
select tests.ok((select count(*) from (select id, title, type, body, author_name, created_at from textos where destacado = true) x) = 2, 'f12: la home pública sigue leyendo destacados');
select tests.ok((select count(*) from textos where not destacado) = 0, 'f12: anon solo ve destacados');

-- ===== Ritmo sigue funcionando (por author_id)
select tests.login(:U6);
select tests.falla($$insert into textos (title, author_username, author_name, type, body, curso_id) values ('x','x','x','ensayo','x','20000000-0000-0000-0000-000000000001')$$, 'no miembro no publica en GENERAL');
select unirse_a_curso('GENERAL');
insert into textos (title, author_username, author_name, type, body, curso_id) select 'r'||g, 'x','x','ensayo','x','20000000-0000-0000-0000-000000000001' from generate_series(1,5) g;
select tests.falla($$insert into textos (title, author_username, author_name, type, body, curso_id) values ('r6','x','x','ensayo','x','20000000-0000-0000-0000-000000000001')$$, 'limitar_ritmo: el 6º texto en un minuto se rechaza');
select tests.su();
\echo TODAS LAS PRUEBAS PASARON
