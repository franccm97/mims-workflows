-- 003_profesionales_seed_estetica.sql — seed de la clínica estética con PROFESIONALES.
--
-- Datos SINTÉTICOS (cero PII): negocio, servicios, profesionales, el cruce
-- profesional_servicios (quién hace qué) y 2 reservas de prueba con profesional_id.
-- Sirve de banco de pruebas para el "modo profesional" del Motor (ver
-- docs/profesionales-motor.md).
--
-- Idempotente: borra primero ESTE negocio por id (cascade limpia servicios,
-- profesionales, profesional_servicios y reservas) y reinserta. NO toca otros negocios.
--
-- NOTA: sin BEGIN/COMMIT — el runner (scripts/migrate.mjs) ya envuelve cada
-- migración en su propia transacción.

-- Limpieza idempotente SOLO de este negocio (cascade -> hijos).
DELETE FROM public.negocios WHERE id = '40000000-0000-0000-0000-000000000004';

-- ============================ NEGOCIO ============================
INSERT INTO public.negocios
  (id, slug, nombre, tipo_vertical, direccion, phone_number_id, dueno_telefono,
   horario, zona_horaria, activo, agente_activo, chatwoot_account_id, telefono_contacto)
VALUES
  ('40000000-0000-0000-0000-000000000004', 'dev-estetica', 'Clínica Estética Aura (DEV)', 'estetica',
   'Carrer Demo 4, Barcelona', 'DEV_PNID_ESTETICA', '34600000040',
   '{"dom":"cerrado","lun":"9-14,16-20","mar":"9-14,16-20","mie":"9-14,16-20","jue":"9-14,16-20","vie":"9-14,16-20","sab":"10-14"}'::jsonb,
   'Europe/Madrid', true, true, '90004', '34600000040');

-- ============================ SERVICIOS (5) ============================
-- Ids fijos para poder enlazarlos en profesional_servicios.
INSERT INTO public.servicios (id, negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('40000000-0000-0000-0000-000000005001', '40000000-0000-0000-0000-000000000004', 'Limpieza facial',       60, 45, 'Facial'),
  ('40000000-0000-0000-0000-000000005002', '40000000-0000-0000-0000-000000000004', 'Tratamiento antiedad',  75, 90, 'Facial'),
  ('40000000-0000-0000-0000-000000005003', '40000000-0000-0000-0000-000000000004', 'Depilación láser',      30, 40, 'Corporal'),
  ('40000000-0000-0000-0000-000000005004', '40000000-0000-0000-0000-000000000004', 'Masaje relajante',      60, 55, 'Corporal'),
  ('40000000-0000-0000-0000-000000005005', '40000000-0000-0000-0000-000000000004', 'Manicura',              45, 25, 'Manos');

-- ============================ PROFESIONALES (3) ============================
-- profesionales.servicios (text[]) se rellena por compat/visualización; la FUENTE
-- DE VERDAD de quién hace qué es la tabla profesional_servicios (de abajo).
INSERT INTO public.profesionales (id, negocio_id, nombre, servicios, horario, activo) VALUES
  ('40000000-0000-0000-0000-000000006001', '40000000-0000-0000-0000-000000000004', 'Dra. Laura Puig',
   ARRAY['Tratamiento antiedad','Depilación láser','Limpieza facial'],
   '{"lun":"9-14,16-20","mar":"9-14,16-20","mie":"9-14,16-20","jue":"9-14,16-20","vie":"9-14,16-20"}'::jsonb, true),
  ('40000000-0000-0000-0000-000000006002', '40000000-0000-0000-0000-000000000004', 'Dr. Marc Soler',
   ARRAY['Tratamiento antiedad','Depilación láser'],
   '{"lun":"16-20","mie":"16-20","vie":"9-14"}'::jsonb, true),
  ('40000000-0000-0000-0000-000000006003', '40000000-0000-0000-0000-000000000004', 'Núria Vidal',
   ARRAY['Limpieza facial','Masaje relajante','Manicura'],
   '{"mar":"9-14","mie":"9-14,16-20","jue":"16-20","vie":"9-14,16-20","sab":"10-14"}'::jsonb, true);

-- ============================ PROFESIONAL_SERVICIOS ============================
-- Quién hace qué (mix: algunos servicios los hacen varios; otros, uno solo).
--   Laura: antiedad, láser, limpieza facial
--   Marc : antiedad, láser
--   Núria: limpieza facial, masaje, manicura
INSERT INTO public.profesional_servicios (profesional_id, servicio_id) VALUES
  ('40000000-0000-0000-0000-000000006001', '40000000-0000-0000-0000-000000005002'), -- Laura - antiedad
  ('40000000-0000-0000-0000-000000006001', '40000000-0000-0000-0000-000000005003'), -- Laura - láser
  ('40000000-0000-0000-0000-000000006001', '40000000-0000-0000-0000-000000005001'), -- Laura - limpieza facial
  ('40000000-0000-0000-0000-000000006002', '40000000-0000-0000-0000-000000005002'), -- Marc  - antiedad
  ('40000000-0000-0000-0000-000000006002', '40000000-0000-0000-0000-000000005003'), -- Marc  - láser
  ('40000000-0000-0000-0000-000000006003', '40000000-0000-0000-0000-000000005001'), -- Núria - limpieza facial
  ('40000000-0000-0000-0000-000000006003', '40000000-0000-0000-0000-000000005004'), -- Núria - masaje
  ('40000000-0000-0000-0000-000000006003', '40000000-0000-0000-0000-000000005005'); -- Núria - manicura

-- ============================ RESERVAS (2, con profesional_id) ============================
-- Fechas RELATIVAS (anti time-bomb). Nombres/teléfonos falsos.
INSERT INTO public.reservas
  (negocio_id, cliente_telefono, cliente_nombre, servicios_resumen,
   duracion_minutos, precio_total, fecha, hora_inicio, hora_fin, profesional, profesional_id, estado)
VALUES
  ('40000000-0000-0000-0000-000000000004', '34600000401', 'Cliente Estetica Uno', 'Limpieza facial',
   60, 45, CURRENT_DATE + 2, '10:00', '11:00', 'Núria Vidal',
   '40000000-0000-0000-0000-000000006003', 'confirmado'),
  ('40000000-0000-0000-0000-000000000004', '34600000402', 'Cliente Estetica Dos', 'Tratamiento antiedad',
   75, 90, CURRENT_DATE + 3, '16:00', '17:15', 'Dra. Laura Puig',
   '40000000-0000-0000-0000-000000006001', 'pendiente_confirmacion_cliente');
