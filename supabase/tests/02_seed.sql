-- SOLO PARA PRUEBAS LOCALES: datos sintéticos con la misma forma que prod (1 admin, alumnos, 1 curso GENERAL).
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-00000000000a','federico.admin@gmail.com'),
 ('00000000-0000-0000-0000-000000000001','ana.alumna@gmail.com'),
 ('00000000-0000-0000-0000-000000000002','beto.alumno@gmail.com'),
 ('00000000-0000-0000-0000-000000000003','carla.profe@gmail.com'),
 ('00000000-0000-0000-0000-000000000004','dani.otro@gmail.com'),
 ('00000000-0000-0000-0000-000000000005','ana-alumna@hotmail.com'),
 ('00000000-0000-0000-0000-000000000006','eva@gmail.com');
insert into public.perfiles (id, name, username, rol) values
 ('00000000-0000-0000-0000-00000000000a','Federico','federicoadmin','admin'),
 ('00000000-0000-0000-0000-000000000001','Ana','anaalumna','alumno'),
 ('00000000-0000-0000-0000-000000000002','Beto','betoalumno','alumno'),
 ('00000000-0000-0000-0000-000000000003','Carla','carlaprofe','profesor'),
 ('00000000-0000-0000-0000-000000000004','Dani','danierotro','alumno');
-- (usuarios 5 y 6 todavía no tienen perfil: se usan para probar el alta)
insert into public.instituciones (id, nombre, slug) values ('10000000-0000-0000-0000-000000000000','IES 9-008','ies9008');
insert into public.cursos (id, institucion_id, nombre, codigo_invitacion, creado_por) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000000','General','GENERAL',null),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000000','Otro curso','OTRO01',null);
insert into public.miembros_curso (curso_id, user_id, rol) values
 ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','docente'),
 ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','alumno'),
 ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','alumno'),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','docente'),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004','alumno');
insert into public.textos (id, title, author_username, author_name, type, body, destacado, curso_id) values
 ('30000000-0000-0000-0000-000000000001','Texto Ana','anaalumna','Ana','ensayo','<p>hola</p>',false,'20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','Texto Beto destacado','betoalumno','Beto','narrativo','<p>x</p>',true,'20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000003','Texto Dani (otro curso)','danierotro','Dani','informe','<p>y</p>',false,'20000000-0000-0000-0000-000000000002'),
 ('30000000-0000-0000-0000-000000000004','Texto Admin','federicoadmin','Federico','otro','<p>z</p>',false,'20000000-0000-0000-0000-000000000001');
insert into public.comentarios (texto_id, author_username, author_name, body) values
 ('30000000-0000-0000-0000-000000000001','betoalumno','Beto','buen texto'),
 ('30000000-0000-0000-0000-000000000003','carlaprofe','Carla','bien');
insert into public.likes (texto_id, user_username) values ('30000000-0000-0000-0000-000000000001','betoalumno');
