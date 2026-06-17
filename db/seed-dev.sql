-- db/seed-dev.sql
-- Semilla SINTÉTICA para la DB DEV (mims_dev). CERO datos reales / CERO PII:
-- nombres y teléfonos son inventados y evidentes ("Cliente Demo", 34600000xxx).
--
-- 3 negocios de verticales distintas (restaurante / clínica / peluquería), cada uno
-- con sus servicios y un par de reservas de prueba. Las FECHAS son RELATIVAS
-- (CURRENT_DATE + n) para que NUNCA caduquen (anti time-bomb).
--
-- Re-ejecutable: borra primero los 3 negocios dev por id (cascade limpia servicios
-- y reservas). NUNCA tocar otros negocios.
--
-- horario (jsonb): claves dom/lun/mar/mie/jue/vie/sab; valor = tramos en horas
-- decimales separados por coma ("13-16.5,20-23") o "cerrado". Mismo formato que
-- lee el Motor (nodo "3a-2. Calcular huecos": split(',') -> split('-').map(Number)).

-- prod tiene esta columna y los flujos la usan; el dump limpio no la traía.
-- Idempotente: no falla si ya existe.
ALTER TABLE public.negocios ADD COLUMN IF NOT EXISTS agente_activo boolean DEFAULT true;

BEGIN;

-- Limpieza de los negocios DEV (cascade -> servicios + reservas).
DELETE FROM public.negocios WHERE id IN (
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000003'
);

-- ============================ NEGOCIOS ============================
INSERT INTO public.negocios
  (id, slug, nombre, tipo_vertical, direccion, phone_number_id, dueno_telefono,
   horario, zona_horaria, activo, agente_activo, chatwoot_account_id, telefono_contacto)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'dev-restaurante', 'La Parrilla (DEV)', 'restaurante',
   'Carrer Demo 1, Barcelona', 'DEV_PNID_RESTAURANTE', '34600000010',
   '{"dom":"13-16.5","lun":"cerrado","mar":"cerrado","mie":"cerrado","jue":"cerrado","vie":"13-16.5,20-23","sab":"13-16.5,20-23"}'::jsonb,
   'Europe/Madrid', true, true, '90001', '34600000010'),

  ('20000000-0000-0000-0000-000000000002', 'dev-clinica', 'Clínica Dental Sonrisa (DEV)', 'clinica',
   'Avinguda Demo 2, Girona', 'DEV_PNID_CLINICA', '34600000020',
   '{"dom":"cerrado","lun":"9-14,16-20","mar":"9-14,16-20","mie":"9-14,16-20","jue":"9-14,16-20","vie":"9-14,16-20","sab":"cerrado"}'::jsonb,
   'Europe/Madrid', true, true, '90002', '34600000020'),

  ('30000000-0000-0000-0000-000000000003', 'dev-peluqueria', 'Peluquería Estilo (DEV)', 'peluqueria',
   'Plaça Demo 3, Lleida', 'DEV_PNID_PELUQUERIA', '34600000030',
   '{"dom":"cerrado","lun":"cerrado","mar":"9.5-13.5,16-20","mie":"9.5-13.5,16-20","jue":"9.5-13.5,16-20","vie":"9.5-13.5,16-20","sab":"9.5-14"}'::jsonb,
   'Europe/Madrid', true, true, '90003', '34600000030');

-- ============================ SERVICIOS ============================
-- Restaurante: tipos de mesa (precio 0; las mesas no se cobran).
INSERT INTO public.servicios (negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('10000000-0000-0000-0000-000000000001', 'Mesa para 2', 120, 0, 'Mesa'),
  ('10000000-0000-0000-0000-000000000001', 'Mesa para 4', 120, 0, 'Mesa'),
  ('10000000-0000-0000-0000-000000000001', 'Mesa para 6', 120, 0, 'Mesa');

-- Clínica dental.
INSERT INTO public.servicios (negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('20000000-0000-0000-0000-000000000002', 'Limpieza dental', 30, 40, 'Higiene'),
  ('20000000-0000-0000-0000-000000000002', 'Revisión', 20, 30, 'Consulta'),
  ('20000000-0000-0000-0000-000000000002', 'Empaste', 45, 60, 'Tratamiento');

-- Peluquería.
INSERT INTO public.servicios (negocio_id, nombre, duracion_minutos, precio, categoria) VALUES
  ('30000000-0000-0000-0000-000000000003', 'Corte caballero', 30, 15, 'Corte'),
  ('30000000-0000-0000-0000-000000000003', 'Corte y peinado', 45, 25, 'Corte'),
  ('30000000-0000-0000-0000-000000000003', 'Tinte', 90, 50, 'Color');

-- ============================ RESERVAS (prueba) ============================
-- Fechas RELATIVAS. Mezcla de estados (confirmado / pendiente). Nombres falsos.
INSERT INTO public.reservas
  (negocio_id, cliente_telefono, cliente_nombre, servicios_resumen,
   duracion_minutos, precio_total, fecha, hora_inicio, hora_fin, estado)
VALUES
  -- Restaurante
  ('10000000-0000-0000-0000-000000000001', '34600000101', 'Cliente Demo Uno', 'Mesa para 4',
   120, 0, CURRENT_DATE + 3, '14:00', '16:00', 'confirmado'),
  ('10000000-0000-0000-0000-000000000001', '34600000102', 'Cliente Demo Dos', 'Mesa para 2',
   120, 0, CURRENT_DATE + 5, '21:00', '23:00', 'pendiente_confirmacion_cliente'),
  -- Clínica
  ('20000000-0000-0000-0000-000000000002', '34600000201', 'Paciente Demo Uno', 'Limpieza dental',
   30, 40, CURRENT_DATE + 2, '10:00', '10:30', 'confirmado'),
  ('20000000-0000-0000-0000-000000000002', '34600000202', 'Paciente Demo Dos', 'Revisión',
   20, 30, CURRENT_DATE + 4, '17:00', '17:20', 'pendiente_confirmacion_cliente'),
  -- Peluquería
  ('30000000-0000-0000-0000-000000000003', '34600000301', 'Cliente Pelu Uno', 'Corte y peinado',
   45, 25, CURRENT_DATE + 1, '10:00', '10:45', 'confirmado'),
  ('30000000-0000-0000-0000-000000000003', '34600000302', 'Cliente Pelu Dos', 'Tinte',
   90, 50, CURRENT_DATE + 6, '16:30', '18:00', 'pendiente_confirmacion_cliente');

COMMIT;

-- Resumen rápido (no modifica nada).
SELECT n.nombre, n.tipo_vertical,
       (SELECT count(*) FROM public.servicios s WHERE s.negocio_id = n.id) AS servicios,
       (SELECT count(*) FROM public.reservas  r WHERE r.negocio_id = n.id) AS reservas
FROM public.negocios n
WHERE n.id IN ('10000000-0000-0000-0000-000000000001',
               '20000000-0000-0000-0000-000000000002',
               '30000000-0000-0000-0000-000000000003')
ORDER BY n.nombre;
