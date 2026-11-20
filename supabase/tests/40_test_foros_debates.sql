-- SOLO PRUEBAS LOCALES: foros y sala de debates (migraciones 20261116200100..200300).
-- Roles: admin (Federico, docente de GENERAL), profesor (Carla, docente de OTRO), alumnos de
-- GENERAL (Ana, Beto), alumnos de OTRO (Dani, Eva) y anon. Cubre lo permitido y lo denegado.
\set ON_ERROR_STOP 1
\set A '''00000000-0000-0000-0000-00000000000a'''
\set ANA '''00000000-0000-0000-0000-000000000001'''
\set BETO '''00000000-0000-0000-0000-000000000002'''
\set CARLA '''00000000-0000-0000-0000-000000000003'''
\set DANI '''00000000-0000-0000-0000-000000000004'''
\set EVA '''00000000-0000-0000-0000-000000000006'''
\set GEN '''20000000-0000-0000-0000-000000000001'''
\set OTRO '''20000000-0000-0000-0000-000000000002'''

-- falla con los checks diferidos evaluados en el momento (mínimo de posturas)
create or replace function tests.falla_inmediato(q text, msg text) returns void language plpgsql as $$
begin
  begin set constraints all immediate; execute q; exception when others then raise notice 'ok (falla como se espera): % -> %', msg, sqlerrm; return; end;
  raise exception 'FAIL: % (no falló)', msg;
end $$;
grant execute on function tests.falla_inmediato(text, text) to anon, authenticated;

-- Eva: alumna de OTRO (usuario 6, sin perfil en el seed)
select tests.su();
insert into perfiles (id, name, username, rol) values (:EVA, 'Eva', 'eva', 'alumno') on conflict (id) do nothing;
insert into miembros_curso (curso_id, user_id, rol) values (:OTRO, :EVA, 'alumno') on conflict do nothing;

-- ═════════════ FOROS ═════════════
select tests.login(:CARLA);
insert into foros (curso_id, titulo, consigna, estado, creado_por) values (:OTRO, 'Foro Otro', 'Consigna', 'cerrado', :A);
select tests.ok((select creado_por from foros where titulo = 'Foro Otro') = :CARLA, 'foros: profesor crea foro en SU curso; creado_por lo fija el servidor');
select tests.ok((select estado from foros where titulo = 'Foro Otro') = 'abierto', 'foros: el foro nace abierto');
select tests.falla($$insert into foros (curso_id, titulo) values ('20000000-0000-0000-0000-000000000001', 'x')$$, 'foros: profesor NO crea foro en un curso ajeno');
select tests.login(:DANI);
select tests.falla($$insert into foros (curso_id, titulo) values ('20000000-0000-0000-0000-000000000002', 'x')$$, 'foros: alumno no crea foros');
select tests.login(:A);
insert into foros (curso_id, titulo, consigna) values (:GEN, 'Foro General', '¿Qué leyeron esta semana?');
select tests.ok(tests.n($$select 1 from foros$$) = 2, 'foros: admin ve los foros de todos los cursos');
select tests.falla($$insert into foros (curso_id, titulo) values ('20000000-0000-0000-0000-000000000001', '')$$, 'foros: título vacío rechazado (CHECK)');
select tests.falla($$insert into foros (curso_id, titulo) values ('20000000-0000-0000-0000-000000000001', repeat('x', 201))$$, 'foros: título > 200 rechazado (CHECK)');

select tests.su();
select id as fg from foros where titulo = 'Foro General' \gset
select id as fo from foros where titulo = 'Foro Otro' \gset

select tests.login(:ANA);
select tests.ok(tests.n($$select 1 from foros$$) = 1 and (select titulo from foros) = 'Foro General', 'foros: alumna ve solo los foros de su curso');
insert into foro_mensajes (foro_id, body, author_id, author_name, fijado, oculto) values (:'fg', 'Leí a Borges', :BETO, 'Beto falso', true, true);
select tests.ok((select author_id from foro_mensajes where body = 'Leí a Borges') = :ANA, 'mensajes: author_id lo fija el servidor (no se puede suplantar)');
select tests.ok((select author_name from foro_mensajes where body = 'Leí a Borges') = 'Ana', 'mensajes: author_name sale del perfil');
select tests.ok((select not fijado and not oculto from foro_mensajes where body = 'Leí a Borges'), 'mensajes: el alumno no se auto-fija ni oculta al publicar');
select tests.falla(format($$insert into foro_mensajes (foro_id, body) values (%L, 'x')$$, :'fo'), 'mensajes: alumna no publica en el foro de otro curso');
select tests.falla(format($$insert into foro_mensajes (foro_id, body) values (%L, '   ')$$, :'fg'), 'mensajes: cuerpo vacío rechazado');
select tests.falla(format($$insert into foro_mensajes (foro_id, body) values (%L, repeat('x', 5001))$$, :'fg'), 'mensajes: cuerpo > 5000 rechazado');

select tests.su();
select id as m_ana from foro_mensajes where body = 'Leí a Borges' \gset

select tests.login(:BETO);
insert into foro_mensajes (foro_id, parent_id, body) values (:'fg', :'m_ana', 'Yo también');
select tests.ok(tests.n(format($$select 1 from foro_mensajes where parent_id = %L$$, :'m_ana')) = 1, 'mensajes: compañero responde en hilo');
select tests.su();
select id as m_beto from foro_mensajes where body = 'Yo también' \gset
select tests.login(:BETO);
select tests.falla(format($$insert into foro_mensajes (foro_id, parent_id, body) values (%L, %L, 'x')$$, :'fg', :'m_beto'), 'mensajes: no se responde a una respuesta (hilo de un nivel)');
select tests.ok(tests.n(format($$update foro_mensajes set body = 'hackeado' where id = %L returning 1$$, :'m_ana')) = 0, 'mensajes: no se edita el mensaje ajeno');
select tests.ok(tests.n(format($$delete from foro_mensajes where id = %L returning 1$$, :'m_ana')) = 0, 'mensajes: no se borra el mensaje ajeno');

select tests.login(:DANI);
select tests.ok(tests.n($$select 1 from foro_mensajes$$) = 0, 'mensajes: alumno de otro curso no ve mensajes de GENERAL');
select tests.falla(format($$insert into foro_mensajes (foro_id, parent_id, body) values (%L, %L, 'x')$$, :'fo', :'m_ana'), 'mensajes: no se responde a un mensaje de otro foro');

select tests.login(:ANA);
update foro_mensajes set body = 'Leí a Borges y a Cortázar', fijado = true, author_id = :BETO where id = :'m_ana';
select tests.ok((select body = 'Leí a Borges y a Cortázar' and editado and not fijado and author_id = :ANA from foro_mensajes where id = :'m_ana'), 'mensajes: autora edita lo suyo (queda "editado"), sin fijarse ni cambiar autoría');
select tests.ok(tests.n(format($$update foros set estado = 'cerrado' where id = %L returning 1$$, :'fg')) = 0, 'foros: alumna no cierra el foro');

select tests.login(:CARLA);
select tests.ok(tests.n(format($$update foro_mensajes set oculto = true where id = %L returning 1$$, :'m_ana')) = 0, 'mensajes: profesor de OTRO curso no modera GENERAL');
select tests.ok(tests.n(format($$delete from foros where id = %L returning 1$$, :'fg')) = 0, 'foros: profesor de OTRO curso no borra foros de GENERAL');

select tests.login(:A);
update foro_mensajes set fijado = true, body = 'reescrito por admin' where id = :'m_ana';
select tests.ok((select fijado and body = 'Leí a Borges y a Cortázar' from foro_mensajes where id = :'m_ana'), 'mensajes: docente fija; no puede reescribir el texto del alumno');
update foro_mensajes set oculto = true where id = :'m_beto';
select tests.ok((select oculto from foro_mensajes where id = :'m_beto'), 'mensajes: docente oculta un mensaje');
select tests.login(:ANA);
select tests.ok(tests.n(format($$select 1 from foro_mensajes where id = %L$$, :'m_beto')) = 0, 'mensajes: el oculto no lo ven los compañeros');
select tests.login(:BETO);
select tests.ok(tests.n(format($$select 1 from foro_mensajes where id = %L$$, :'m_beto')) = 1, 'mensajes: el autor sigue viendo su mensaje oculto');
select tests.login(:A);
update foros set estado = 'cerrado', curso_id = :OTRO, creado_por = :ANA where id = :'fg';
select tests.ok((select estado = 'cerrado' and curso_id = :GEN and creado_por = :A from foros where id = :'fg'), 'foros: docente cierra; curso y creador no se pueden cambiar');
select tests.login(:ANA);
select tests.falla(format($$insert into foro_mensajes (foro_id, body) values (%L, 'tarde')$$, :'fg'), 'mensajes: foro cerrado no acepta mensajes');
select tests.falla(format($$update foro_mensajes set body = 'cambio' where id = %L$$, :'m_ana'), 'mensajes: con el foro cerrado no se edita');
select tests.login(:A);
update foros set estado = 'abierto' where id = :'fg';
select tests.login(:ANA);
insert into foro_mensajes (foro_id, body) values (:'fg', 'para borrar');
select tests.ok(tests.n($$delete from foro_mensajes where body = 'para borrar' returning 1$$) = 1, 'mensajes: autora borra lo suyo');

-- miembro que sale del curso pierde acceso
select tests.login(:DANI);
select tests.ok(tests.n(format($$select 1 from foros where id = %L$$, :'fo')) = 1, 'foros: alumno de OTRO ve su foro');
delete from miembros_curso where curso_id = :OTRO and user_id = :DANI;
select tests.ok(tests.n($$select 1 from foros$$) = 0, 'foros: al salir del curso deja de ver el foro');
select tests.falla(format($$insert into foro_mensajes (foro_id, body) values (%L, 'x')$$, :'fo'), 'mensajes: ex miembro no publica');
select unirse_a_curso('OTRO01');

select tests.anon();
select tests.falla($$select * from foros$$, 'anon: no lee foros');
select tests.falla($$select * from foro_mensajes$$, 'anon: no lee mensajes');
select tests.falla(format($$insert into foro_mensajes (foro_id, body, author_id, author_name) values (%L, 'x', '00000000-0000-0000-0000-000000000001', 'x')$$, :'fg'), 'anon: no publica');
select tests.falla(format($$select private.puede_ver_foro(%L)$$, :'fg'), 'anon: no ejecuta helpers privados');

-- ═════════════ DEBATES ═════════════
select tests.login(:CARLA);
select tests.falla($$select crear_debate('20000000-0000-0000-0000-000000000002', '¿Uniforme?', '', array['Sí'])$$, 'debates: con 1 postura se rechaza');
select tests.falla($$select crear_debate('20000000-0000-0000-0000-000000000002', '¿Uniforme?', '', array['1','2','3','4','5','6','7'])$$, 'debates: más de 6 posturas se rechaza');
select tests.falla($$select crear_debate('20000000-0000-0000-0000-000000000002', '¿Uniforme?', '', array['Sí', ' Sí ', ''])$$, 'debates: posturas repetidas/vacías no cuentan');
select tests.falla($$select crear_debate('20000000-0000-0000-0000-000000000001', '¿Uniforme?', '', array['Sí','No'])$$, 'debates: profesor no crea debate en curso ajeno');
select tests.falla_inmediato($$insert into debates (curso_id, pregunta) values ('20000000-0000-0000-0000-000000000002', 'sin posturas')$$, 'debates: insert directo sin 2 posturas se rechaza');
select crear_debate(:OTRO, '¿Debería ser obligatorio el uniforme?', 'Pensalo con ejemplos', array['Sí', 'No', 'Depende']) as deb \gset
select tests.ok(tests.n(format($$select 1 from debate_posturas where debate_id = %L$$, :'deb')) = 3, 'debates: profesor crea debate con 3 posturas');
select tests.ok((select prosecdef from pg_proc where proname = 'crear_debate') = false, 'debates: crear_debate es SECURITY INVOKER (autoriza RLS)');
select tests.su();
select id as p_si from debate_posturas where debate_id = :'deb' and nombre = 'Sí' \gset
select id as p_no from debate_posturas where debate_id = :'deb' and nombre = 'No' \gset
select tests.login(:DANI);
select tests.falla($$select crear_debate('20000000-0000-0000-0000-000000000002', 'x', '', array['a','b'])$$, 'debates: alumno no crea debates');
select tests.ok(tests.n($$select 1 from debate_posturas$$) = 3, 'debates: alumno del curso ve las posturas');
select tests.falla(format($$insert into debate_argumentos (debate_id, body) values (%L, 'sin postura')$$, :'deb'), 'argumentos: sin elegir postura no se argumenta');
insert into debate_elecciones (debate_id, user_id, postura_id) values (:'deb', :EVA, :'p_si');
select tests.ok((select user_id from debate_elecciones) = :DANI, 'elecciones: user_id lo fija el servidor');
select tests.falla(format($$insert into debate_elecciones (debate_id, postura_id) values (%L, %L)$$, :'deb', :'p_no'), 'elecciones: una sola postura por debate');
update debate_elecciones set postura_id = :'p_no' where debate_id = :'deb';
select tests.ok((select postura_id from debate_elecciones) = :'p_no', 'elecciones: puede cambiar de postura con el debate abierto');
update debate_elecciones set postura_id = :'p_si' where debate_id = :'deb';
insert into debate_argumentos (debate_id, body, postura_id, author_id) values (:'deb', 'El uniforme iguala', :'p_no', :CARLA);
select tests.ok((select postura_id = :'p_si' and author_id = :DANI and author_name = 'Dani' from debate_argumentos where body = 'El uniforme iguala'), 'argumentos: postura y autoría las fija el servidor');
select tests.su();
select id as a_dani from debate_argumentos where body = 'El uniforme iguala' \gset

select tests.login(:EVA);
select tests.ok(tests.n($$select 1 from debate_elecciones$$) = 0, 'elecciones: un compañero no ve la postura que eligió otro');
insert into debate_elecciones (debate_id, postura_id) values (:'deb', :'p_no');
insert into debate_argumentos (debate_id, parent_id, body) values (:'deb', :'a_dani', 'Pero limita la expresión');
select tests.ok(tests.n(format($$select 1 from debate_argumentos where parent_id = %L$$, :'a_dani')) = 1, 'argumentos: réplica a la otra postura');
select tests.su();
select id as a_eva from debate_argumentos where body = 'Pero limita la expresión' \gset
select tests.login(:EVA);
select tests.falla(format($$insert into debate_argumentos (debate_id, parent_id, body) values (%L, %L, 'x')$$, :'deb', :'a_eva'), 'argumentos: no se replica a una réplica');
insert into debate_reacciones (argumento_id, user_id) values (:'a_dani', :DANI);
select tests.ok((select user_id from debate_reacciones) = :EVA, 'reacciones: "me hizo pensar" con user_id del servidor');
select tests.falla(format($$insert into debate_reacciones (argumento_id) values (%L)$$, :'a_dani'), 'reacciones: una sola por usuario y argumento');
select tests.falla(format($$insert into debate_reacciones (argumento_id) values (%L)$$, :'a_eva'), 'reacciones: no sobre el argumento propio');
select tests.ok(tests.n(format($$update debate_argumentos set body = 'x' where id = %L returning 1$$, :'a_dani')) = 0, 'argumentos: no se edita el ajeno');
select tests.ok(tests.n(format($$delete from debate_argumentos where id = %L returning 1$$, :'a_dani')) = 0, 'argumentos: no se borra el ajeno');
select tests.falla($$update debate_reacciones set user_id = user_id$$, 'reacciones: no se editan');

select tests.login(:DANI);
update debate_argumentos set body = 'El uniforme iguala a todos', oculto = true where id = :'a_dani';
select tests.ok((select editado and not oculto from debate_argumentos where id = :'a_dani'), 'argumentos: autor edita lo suyo; no puede ocultarse');
select tests.ok(tests.n($$update debates set estado = 'cerrado' returning 1$$) = 0, 'debates: alumno no cierra el debate');

select tests.login(:ANA);
select tests.ok(tests.n($$select 1 from debates$$) = 0, 'debates: alumna de otro curso no ve el debate');
select tests.falla(format($$insert into debate_elecciones (debate_id, postura_id) values (%L, %L)$$, :'deb', :'p_si'), 'elecciones: alumna de otro curso no elige postura');
select tests.falla(format($$insert into debate_argumentos (debate_id, body) values (%L, 'x')$$, :'deb'), 'argumentos: alumna de otro curso no argumenta');
select tests.falla(format($$insert into debate_reacciones (argumento_id) values (%L)$$, :'a_dani'), 'reacciones: alumna de otro curso no reacciona');

select tests.login(:CARLA);
select tests.ok(tests.n($$select 1 from debate_elecciones$$) = 2, 'elecciones: el docente ve las posturas elegidas');
insert into debate_argumentos (debate_id, body) values (:'deb', 'Recuerden dar ejemplos');
select tests.ok((select postura_id is null from debate_argumentos where body = 'Recuerden dar ejemplos'), 'argumentos: docente interviene sin postura');
update debate_argumentos set oculto = true where id = :'a_eva';
select tests.login(:DANI);
select tests.ok(tests.n(format($$select 1 from debate_argumentos where id = %L$$, :'a_eva')) = 0, 'argumentos: oculto por el docente no se ve');
select tests.login(:CARLA);
update debate_argumentos set oculto = false where id = :'a_eva';
select tests.falla(format($$update debates set sintesis = 'antes de tiempo' where id = %L$$, :'deb'), 'debates: no hay síntesis con el debate abierto');
update debates set sintesis_destacada = true where id = :'deb';
select tests.ok((select not sintesis_destacada from debates where id = :'deb'), 'debates: no se destaca un debate abierto');
update debates set estado = 'cerrado', curso_id = :GEN where id = :'deb';
select tests.ok((select estado = 'cerrado' and cerrado_en is not null and curso_id = :OTRO from debates where id = :'deb'), 'debates: docente cierra (cerrado_en); el curso no cambia');
select tests.login(:DANI);
select tests.falla(format($$update debate_elecciones set postura_id = %L where debate_id = %L$$, :'p_no', :'deb'), 'elecciones: cerrado, no se cambia de postura');
select tests.falla(format($$insert into debate_argumentos (debate_id, parent_id, body) values (%L, %L, 'x')$$, :'deb', :'a_dani'), 'argumentos: cerrado, no se argumenta');
select tests.falla(format($$update debate_argumentos set body = 'x' where id = %L$$, :'a_dani'), 'argumentos: cerrado, no se edita');
select tests.login(:CARLA);
select tests.falla(format($$update debate_posturas set nombre = 'Quizás' where id = %L$$, :'p_si'), 'posturas: cerrado, no se cambian');
update debates set sintesis = 'La mayoría pensó en la igualdad; otros, en la expresión.', sintesis_destacada = true where id = :'deb';
select tests.ok((select sintesis_destacada from debates where id = :'deb'), 'debates: docente escribe la síntesis y la destaca');
select tests.login(:DANI);
select tests.ok(tests.n($$update debates set sintesis_destacada = false returning 1$$) = 0, 'debates: alumno no cambia la síntesis/destacado');

select tests.anon();
select tests.ok(tests.n($$select id, pregunta, sintesis, cerrado_en from debates where sintesis_destacada$$) = 1, 'anon: ve la síntesis destacada (pregunta + síntesis)');
select tests.falla($$select descripcion from debates$$, 'anon: no lee otras columnas del debate');
select tests.falla($$select curso_id, creado_por from debates$$, 'anon: no ve curso ni creador');
select tests.falla($$select * from debate_argumentos$$, 'anon: no lee argumentos');
select tests.falla($$select * from debate_posturas$$, 'anon: no lee posturas');
select tests.falla($$select * from debate_elecciones$$, 'anon: no lee elecciones');
select tests.falla($$select * from debate_reacciones$$, 'anon: no lee reacciones');
select tests.falla($$select crear_debate('20000000-0000-0000-0000-000000000002', 'x', '', array['a','b'])$$, 'anon: no crea debates');
select tests.falla($$update debates set sintesis_destacada = false$$, 'anon: no modifica debates');

select tests.login(:ANA);
select tests.ok(tests.n($$select 1 from debates$$) = 1, 'debates: logueado de otro curso ve el debate destacado (como la portada)');
select tests.ok(tests.n($$select 1 from debate_argumentos$$) = 0 and tests.n($$select 1 from debate_posturas$$) = 0, 'debates: pero no sus argumentos ni posturas');

select tests.login(:CARLA);
update debates set estado = 'abierto' where id = :'deb';
select tests.ok((select not sintesis_destacada and cerrado_en is null from debates where id = :'deb'), 'debates: al reabrir se quita el destacado');

select tests.login(:A);
update debate_argumentos set oculto = true where id = :'a_dani';
select tests.ok((select oculto from debate_argumentos where id = :'a_dani'), 'admin: modera debates de cualquier curso');
select crear_debate(:GEN, '¿Leer en papel o en pantalla?', '', array['Papel', 'Pantalla']) as deb_g \gset
select tests.ok(:'deb_g' is not null, 'admin: crea debates en cualquier curso');

select tests.login(:CARLA);
delete from debates where id = :'deb';
select tests.su();
select tests.ok((select count(*) from debate_posturas where debate_id = :'deb') = 0 and (select count(*) from debate_argumentos where debate_id = :'deb') = 0
  and (select count(*) from debate_elecciones where debate_id = :'deb') = 0 and (select count(*) from debate_reacciones) = 0, 'debates: borrar el debate borra posturas, elecciones, argumentos y reacciones');

-- ═════════════ ANTI-ABUSO: 10 mensajes por minuto (foros + debates) ═════════════
select tests.su();
update foro_mensajes set created_at = now() - interval '2 minutes';
select tests.login(:ANA);
do $$ begin for i in 1..10 loop
  insert into public.foro_mensajes (foro_id, body) values ((select id from public.foros where titulo = 'Foro General'), 'ráfaga ' || i);
end loop; end $$;
select tests.ok(tests.n($$select 1 from foro_mensajes where body like 'ráfaga %'$$) = 10, 'ritmo: 10 mensajes en un minuto se aceptan');
select tests.falla(format($$insert into foro_mensajes (foro_id, body) values (%L, 'once')$$, :'fg'), 'ritmo: el mensaje 11 del minuto se rechaza');
select tests.su();
select id as pg_papel from debate_posturas where debate_id = :'deb_g' and nombre = 'Papel' \gset
select tests.login(:ANA);
insert into debate_elecciones (debate_id, postura_id) values (:'deb_g', :'pg_papel');
select tests.falla(format($$insert into debate_argumentos (debate_id, body) values (%L, 'x')$$, :'deb_g'), 'ritmo: el límite es compartido con los debates');
select tests.su();
select tests.ok(tests.n($$select 1 from pg_trigger where tgname in ('trg_foro_mensajes_ritmo','trg_debate_argumentos_ritmo')$$) = 2, 'ritmo: triggers presentes en ambas tablas');
