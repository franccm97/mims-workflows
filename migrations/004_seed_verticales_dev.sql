-- 004_seed_verticales_dev.sql — un seed de ejemplo por VERTICAL para DEV.
--
-- Cubre las 7 verticales restantes (estética ya está en 003): restaurante,
-- peluquería, clínica, fisio, taller, gimnasio, pádel. Cada negocio trae sus
-- PALANCAS configuradas (capacidad_simultanea, corte_franja) + servicios +
-- profesionales/links donde aplica + reservas de prueba.
--
-- Datos SINTÉTICOS (cero PII): nombres/teléfonos evidentes, fechas RELATIVAS
-- (CURRENT_DATE + n) anti time-bomb. Ids propios (rango a0000000-…) para NO chocar
-- con db/seed-dev.sql (10000000/20000000/30000000) ni con estética (40000000-004).
--
-- Idempotente y NO destructivo: borra primero SOLO estos negocios por id (cascade
-- limpia servicios/profesionales/profesional_servicios/reservas) y reinserta.
-- NO toca otros negocios. Sin BEGIN/COMMIT: el runner ya envuelve cada migración.
--
-- Palancas por vertical (ver docs/arquitectura-verticales.md):
--   restaurante: cap 10, corte 18, sin profesionales
--   peluquería : cap 1,  corte 14, con profesionales
--   clínica    : cap 1,  corte 14, con profesionales (doctores)
--   fisio      : cap 1,  corte 14, con profesionales
--   taller     : cap 3,  corte 14, sin profesionales (3 bahías = cupo global)
--   gimnasio   : cap 20, corte 14, sin profesionales (aforo)
--   pádel      : cap 4,  corte 14, pistas modeladas como profesionales (recurso=agenda)

-- ===================== limpieza idempotente (solo estos negocios) =====================
DELETE FROM public.negocios WHERE id IN (
  'a0000000-0000-0000-0000-000000000001', -- restaurante
  'a0000000-0000-0000-0000-000000000002', -- peluquería
  'a0000000-0000-0000-0000-000000000003', -- clínica
  'a0000000-0000-0000-0000-000000000005', -- fisio
  'a0000000-0000-0000-0000-000000000006', -- taller
  'a0000000-0000-0000-0000-000000000007', -- gimnasio
  'a0000000-0000-0000-0000-000000000008'  -- pádel
);

-- ===================== NEGOCIOS (con palancas) =====================
INSERT INTO public.negocios
  (id, slug, nombre, tipo_vertical, direccion, phone_number_id, dueno_telefono,
   horario, zona_horaria, activo, agente_activo, chatwoot_account_id,
   capacidad_simultanea, corte_franja)
VALUES
  ('a0000000-0000-0000-0000-000000000001', 'dev-restaurante-2', 'Braseria Demo (DEV)', 'restaurante',
   'Demo 1', 'DEV_PNID_V_REST', '34600000051',
   '{"dom":"13-16.5","lun":"cerrado","mar":"cerrado","mie":"13-16,20-23","jue":"13-16,20-23","vie":"13-16.5,20-23.5","sab":"13-16.5,20-23.5"}'::jsonb,
   'Europe/Madrid', true, true, '9101', 10, 18),

  ('a0000000-0000-0000-0000-000000000002', 'dev-peluqueria-2', 'Barberia Demo (DEV)', 'peluqueria',
   'Demo 2', 'DEV_PNID_V_PELU', '34600000052',
   '{"dom":"cerrado","lun":"cerrado","mar":"9.5-13.5,16-20","mie":"9.5-13.5,16-20","jue":"9.5-13.5,16-20","vie":"9.5-13.5,16-20","sab":"9.5-14"}'::jsonb,
   'Europe/Madrid', true, true, '9102', 1, 14),

  ('a0000000-0000-0000-0000-000000000003', 'dev-clinica-2', 'Clinica Dental Demo (DEV)', 'clinica',
   'Demo 3', 'DEV_PNID_V_CLIN', '34600000053',
   '{"dom":"cerrado","lun":"9-14,16-20","mar":"9-14,16-20","mie":"9-14,16-20","jue":"9-14,16-20","vie":"9-14","sab":"cerrado"}'::jsonb,
   'Europe/Madrid', true, true, '9103', 1, 14),

  ('a0000000-0000-0000-0000-000000000005', 'dev-fisio', 'Fisio Demo (DEV)', 'fisioterapia',
   'Demo 5', 'DEV_PNID_V_FISIO', '34600000055',
   '{"dom":"cerrado","lun":"8-15","mar":"8-15","mie":"8-15","jue":"8-15","vie":"8-15","sab":"cerrado"}'::jsonb,
   'Europe/Madrid', true, true, '9105', 1, 14),

  ('a0000000-0000-0000-0000-000000000006', 'dev-taller', 'Taller Demo (DEV)', 'taller',
   'Demo 6', 'DEV_PNID_V_TALLER', '34600000056',
   '{"dom":"cerrado","lun":"8-13,15-18","mar":"8-13,15-18","mie":"8-13,15-18","jue":"8-13,15-18","vie":"8-13,15-18","sab":"cerrado"}'::jsonb,
   'Europe/Madrid', true, true, '9106', 3, 14),

  ('a0000000-0000-0000-0000-000000000007', 'dev-gimnasio', 'Gimnasio Demo (DEV)', 'gimnasio',
   'Demo 7', 'DEV_PNID_V_GYM', '34600000057',
   '{"dom":"9-14","lun":"7-22","mar":"7-22","mie":"7-22","jue":"7-22","vie":"7-22","sab":"9-14"}'::jsonb,
   'Europe/Madrid', true, true, '9107', 20, 14),

  ('a0000000-0000-0000-0000-000000000008', 'dev-padel', 'Padel Demo (DEV)', 'padel',
   'Demo 8', 'DEV_PNID_V_PADEL', '34600000058',
   '{"dom":"8-23","lun":"8-23","mar":"8-23","mie":"8-23","jue":"8-23","vie":"8-23","sab":"8-23"}'::jsonb,
   'Europe/Madrid', true, true, '9108', 4, 14);

-- ===================== SERVICIOS =====================
-- Restaurante (sin profesionales): tipos de mesa, precio 0.
INSERT INTO public.servicios (negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Mesa para 2', 120, 0, 'Mesa'),
  ('a0000000-0000-0000-0000-000000000001', 'Mesa para 4', 120, 0, 'Mesa'),
  ('a0000000-0000-0000-0000-000000000001', 'Mesa para 6', 120, 0, 'Mesa');

-- Peluquería (con profesionales): ids fijos para enlazar.
INSERT INTO public.servicios (id, negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000020001', 'a0000000-0000-0000-0000-000000000002', 'Corte caballero', 30, 15, 'Corte'),
  ('a0000000-0000-0000-0000-000000020002', 'a0000000-0000-0000-0000-000000000002', 'Tinte', 90, 45, 'Color');

-- Clínica (con profesionales).
INSERT INTO public.servicios (id, negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000030001', 'a0000000-0000-0000-0000-000000000003', 'Revision', 20, 30, 'Consulta'),
  ('a0000000-0000-0000-0000-000000030002', 'a0000000-0000-0000-0000-000000000003', 'Limpieza dental', 30, 45, 'Higiene');

-- Fisio (con profesionales).
INSERT INTO public.servicios (id, negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000050001', 'a0000000-0000-0000-0000-000000000005', 'Sesion fisioterapia', 45, 40, 'Sesion'),
  ('a0000000-0000-0000-0000-000000050002', 'a0000000-0000-0000-0000-000000000005', 'Primera visita', 60, 55, 'Sesion');

-- Taller (sin profesionales): cupo global por bahías.
INSERT INTO public.servicios (negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000000006', 'Cambio de aceite', 60, 80, 'Mantenimiento'),
  ('a0000000-0000-0000-0000-000000000006', 'Neumaticos', 90, 200, 'Mantenimiento');

-- Gimnasio (sin profesionales): plaza en clase, aforo.
INSERT INTO public.servicios (negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000000007', 'Clase spinning', 45, 0, 'Clase'),
  ('a0000000-0000-0000-0000-000000000007', 'Clase yoga', 60, 0, 'Clase');

-- Pádel: pistas modeladas como profesionales -> servicio = alquiler de pista.
INSERT INTO public.servicios (id, negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('a0000000-0000-0000-0000-000000080001', 'a0000000-0000-0000-0000-000000000008', 'Alquiler de pista', 90, 16, 'Pista');

-- ===================== PROFESIONALES + cruce (verticales con agenda propia) =====================
-- Peluquería: 2 estilistas.
INSERT INTO public.profesionales (id, negocio_id, nombre, servicios, horario, activo) VALUES
  ('a0000000-0000-0000-0000-000000021001', 'a0000000-0000-0000-0000-000000000002', 'Estilista Ana',
   ARRAY['Corte caballero','Tinte'], '{"mar":"9.5-13.5,16-20","mie":"9.5-13.5,16-20","jue":"9.5-13.5,16-20","vie":"9.5-13.5,16-20","sab":"9.5-14"}'::jsonb, true),
  ('a0000000-0000-0000-0000-000000021002', 'a0000000-0000-0000-0000-000000000002', 'Estilista Bea',
   ARRAY['Corte caballero'], '{"mar":"16-20","mie":"9.5-13.5","jue":"16-20","vie":"9.5-13.5,16-20"}'::jsonb, true);
INSERT INTO public.profesional_servicios (profesional_id, servicio_id) VALUES
  ('a0000000-0000-0000-0000-000000021001', 'a0000000-0000-0000-0000-000000020001'), -- Ana - corte
  ('a0000000-0000-0000-0000-000000021001', 'a0000000-0000-0000-0000-000000020002'), -- Ana - tinte
  ('a0000000-0000-0000-0000-000000021002', 'a0000000-0000-0000-0000-000000020001'); -- Bea - corte

-- Clínica: 2 doctores.
INSERT INTO public.profesionales (id, negocio_id, nombre, servicios, horario, activo) VALUES
  ('a0000000-0000-0000-0000-000000031001', 'a0000000-0000-0000-0000-000000000003', 'Dr. Pou',
   ARRAY['Revision','Limpieza dental'], '{"lun":"9-14,16-20","mar":"9-14,16-20","mie":"9-14,16-20","jue":"9-14","vie":"9-14"}'::jsonb, true),
  ('a0000000-0000-0000-0000-000000031002', 'a0000000-0000-0000-0000-000000000003', 'Dra. Vila',
   ARRAY['Revision'], '{"lun":"16-20","mie":"16-20","jue":"9-14"}'::jsonb, true);
INSERT INTO public.profesional_servicios (profesional_id, servicio_id) VALUES
  ('a0000000-0000-0000-0000-000000031001', 'a0000000-0000-0000-0000-000000030001'), -- Pou - revision
  ('a0000000-0000-0000-0000-000000031001', 'a0000000-0000-0000-0000-000000030002'), -- Pou - limpieza
  ('a0000000-0000-0000-0000-000000031002', 'a0000000-0000-0000-0000-000000030001'); -- Vila - revision

-- Fisio: 2 fisios.
INSERT INTO public.profesionales (id, negocio_id, nombre, servicios, horario, activo) VALUES
  ('a0000000-0000-0000-0000-000000051001', 'a0000000-0000-0000-0000-000000000005', 'Fisio Marta',
   ARRAY['Sesion fisioterapia','Primera visita'], '{"lun":"8-15","mar":"8-15","mie":"8-15","jue":"8-15","vie":"8-15"}'::jsonb, true),
  ('a0000000-0000-0000-0000-000000051002', 'a0000000-0000-0000-0000-000000000005', 'Fisio Jordi',
   ARRAY['Sesion fisioterapia','Primera visita'], '{"lun":"8-15","mar":"8-15","mie":"8-15","jue":"8-15","vie":"8-15"}'::jsonb, true);
INSERT INTO public.profesional_servicios (profesional_id, servicio_id) VALUES
  ('a0000000-0000-0000-0000-000000051001', 'a0000000-0000-0000-0000-000000050001'),
  ('a0000000-0000-0000-0000-000000051001', 'a0000000-0000-0000-0000-000000050002'),
  ('a0000000-0000-0000-0000-000000051002', 'a0000000-0000-0000-0000-000000050001'),
  ('a0000000-0000-0000-0000-000000051002', 'a0000000-0000-0000-0000-000000050002');

-- Pádel: 4 pistas como "profesionales" (recurso con agenda, capacidad 1 cada una).
INSERT INTO public.profesionales (id, negocio_id, nombre, servicios, horario, activo) VALUES
  ('a0000000-0000-0000-0000-000000081001', 'a0000000-0000-0000-0000-000000000008', 'Pista 1', ARRAY['Alquiler de pista'], '{"lun":"8-23","mar":"8-23","mie":"8-23","jue":"8-23","vie":"8-23","sab":"8-23","dom":"8-23"}'::jsonb, true),
  ('a0000000-0000-0000-0000-000000081002', 'a0000000-0000-0000-0000-000000000008', 'Pista 2', ARRAY['Alquiler de pista'], '{"lun":"8-23","mar":"8-23","mie":"8-23","jue":"8-23","vie":"8-23","sab":"8-23","dom":"8-23"}'::jsonb, true),
  ('a0000000-0000-0000-0000-000000081003', 'a0000000-0000-0000-0000-000000000008', 'Pista 3', ARRAY['Alquiler de pista'], '{"lun":"8-23","mar":"8-23","mie":"8-23","jue":"8-23","vie":"8-23","sab":"8-23","dom":"8-23"}'::jsonb, true),
  ('a0000000-0000-0000-0000-000000081004', 'a0000000-0000-0000-0000-000000000008', 'Pista 4', ARRAY['Alquiler de pista'], '{"lun":"8-23","mar":"8-23","mie":"8-23","jue":"8-23","vie":"8-23","sab":"8-23","dom":"8-23"}'::jsonb, true);
INSERT INTO public.profesional_servicios (profesional_id, servicio_id) VALUES
  ('a0000000-0000-0000-0000-000000081001', 'a0000000-0000-0000-0000-000000080001'),
  ('a0000000-0000-0000-0000-000000081002', 'a0000000-0000-0000-0000-000000080001'),
  ('a0000000-0000-0000-0000-000000081003', 'a0000000-0000-0000-0000-000000080001'),
  ('a0000000-0000-0000-0000-000000081004', 'a0000000-0000-0000-0000-000000080001');

-- ===================== RESERVAS de prueba (fechas relativas) =====================
-- Globales (sin profesional_id): restaurante, taller, gimnasio.
INSERT INTO public.reservas
  (negocio_id, cliente_telefono, cliente_nombre, servicios_resumen, duracion_minutos, precio_total, fecha, hora_inicio, hora_fin, estado)
VALUES
  ('a0000000-0000-0000-0000-000000000001', '34600000511', 'Comensal Demo', 'Mesa para 4', 120, 0, CURRENT_DATE + 2, '21:00', '23:00', 'confirmado'),
  ('a0000000-0000-0000-0000-000000000006', '34600000561', 'Vehiculo Demo', 'Cambio de aceite', 60, 80, CURRENT_DATE + 1, '09:00', '10:00', 'confirmado'),
  ('a0000000-0000-0000-0000-000000000007', '34600000571', 'Socio Demo', 'Clase spinning', 45, 0, CURRENT_DATE + 1, '18:00', '18:45', 'confirmado');

-- Por profesional (con profesional_id): peluquería, clínica, fisio, pádel.
INSERT INTO public.reservas
  (negocio_id, cliente_telefono, cliente_nombre, servicios_resumen, duracion_minutos, precio_total, fecha, hora_inicio, hora_fin, profesional, profesional_id, estado)
VALUES
  ('a0000000-0000-0000-0000-000000000002', '34600000521', 'Cliente Pelu', 'Corte caballero', 30, 15, CURRENT_DATE + 1, '10:00', '10:30', 'Estilista Ana', 'a0000000-0000-0000-0000-000000021001', 'confirmado'),
  ('a0000000-0000-0000-0000-000000000003', '34600000531', 'Paciente Dental', 'Revision', 20, 30, CURRENT_DATE + 2, '09:00', '09:20', 'Dr. Pou', 'a0000000-0000-0000-0000-000000031001', 'confirmado'),
  ('a0000000-0000-0000-0000-000000000005', '34600000551', 'Paciente Fisio', 'Sesion fisioterapia', 45, 40, CURRENT_DATE + 1, '08:00', '08:45', 'Fisio Marta', 'a0000000-0000-0000-0000-000000051001', 'confirmado'),
  ('a0000000-0000-0000-0000-000000000008', '34600000581', 'Jugador Demo', 'Alquiler de pista', 90, 16, CURRENT_DATE + 1, '19:00', '20:30', 'Pista 1', 'a0000000-0000-0000-0000-000000081001', 'confirmado');

-- ===================== resumen (no modifica nada) =====================
SELECT n.tipo_vertical, n.nombre, n.capacidad_simultanea AS cap, n.corte_franja AS corte,
       (SELECT count(*) FROM public.servicios s WHERE s.negocio_id = n.id) AS servicios,
       (SELECT count(*) FROM public.profesionales p WHERE p.negocio_id = n.id) AS profesionales,
       (SELECT count(*) FROM public.reservas r WHERE r.negocio_id = n.id) AS reservas
FROM public.negocios n
WHERE n.id::text LIKE 'a0000000-%'
ORDER BY n.tipo_vertical;
