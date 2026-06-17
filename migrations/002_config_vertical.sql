-- 002_config_vertical.sql — config por negocio para parametrizar el Motor.
--
-- Hoy el Motor lleva la capacidad simultánea y el corte de franja HARDCODEADOS en
-- el código (nodos "3a-2. Calcular huecos" y "3b. Crear reserva": objeto CAPACIDAD
-- y Set RESTAURANTE con el id de La Tasqueta). Estas columnas mueven esa config a
-- la DB, por negocio, para que el flujo sea de verdad multi-negocio sin tocar código.
--
--   capacidad_simultanea: nº de reservas que solapan antes de dar un slot por lleno
--                         (mesas/sillas/salas en paralelo). Default 1 = recurso único.
--   corte_franja:         hora (entera) que parte el día en dos grupos al ofrecer
--                         huecos. 14 = mañana/tarde (default). 18 = mediodía/noche
--                         (restaurantes).
--
-- Idempotente: IF NOT EXISTS. No toca datos existentes (los negocios ya creados
-- quedan con los defaults).

ALTER TABLE public.negocios ADD COLUMN IF NOT EXISTS capacidad_simultanea int DEFAULT 1;
ALTER TABLE public.negocios ADD COLUMN IF NOT EXISTS corte_franja int DEFAULT 14;
