-- 006_mensaje_bot_apagado.sql — texto de cortesía cuando el bot está apagado (BLOQUE 3).
--
-- Cuando el empresario apaga el asistente (agente_activo = false) y un cliente escribe,
-- el flujo le responde con un mensaje de cortesía (NUNCA silencio) y hace handoff a
-- Chatwoot. Este texto es configurable por negocio; si queda NULL/vacío, el flujo usa
-- un genérico por defecto (COALESCE en el SELECT de "4. Cargar negocio + rol").
--
-- Idempotente y NO destructivo: ADD COLUMN IF NOT EXISTS. Depende de 001 (tabla
-- negocios). Pertenece a la cadena de migraciones: al mergear, va DESPUÉS de 005.
-- Sin BEGIN/COMMIT (el runner envuelve cada migración).

ALTER TABLE public.negocios ADD COLUMN IF NOT EXISTS mensaje_bot_apagado text;
