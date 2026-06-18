-- toggle-bot.sql — SQL para apagar/encender el asistente por WhatsApp (TAREA 4).
--
-- NO es una migración (no cambia schema; usa negocios.agente_activo, que YA existe).
-- Son los queries que van DENTRO de los nodos n8n. Pégalos en DEV, prueba y reexporta
-- (GitOps). Ver docs/toggle-bot.md para el cableado completo.
--
-- ⚠️ NO ejecutar a mano contra prod. Esto vive dentro del Motor/flujo de n8n.

-- ============================================================================
-- (A) GATE — nodo "4. Cargar negocio + rol" del flujo CLIENTE (canónico)
-- ----------------------------------------------------------------------------
-- El canónico HOY no trae agente_activo (el de Tasqueta sí). Añádelo al SELECT para
-- que el nodo "4.5 ¿Bot activo?" pueda decidir. (Tasqueta ya lo tiene; esto alinea el
-- canónico.)  Reemplaza el SELECT del nodo por:
SELECT
  id AS negocio_id,
  CASE WHEN dueno_telefono = '{{ $('2. Parsear Meta').first().json.from }}'
       THEN 'empresario' ELSE 'cliente' END AS rol,
  horario,
  zona_horaria,
  agente_activo,          -- <-- NUEVO: lo lee "4.5 ¿Bot activo?"
  dueno_telefono
FROM negocios
WHERE chatwoot_account_id = '{{ $('2. Parsear Meta').first().json.account_id }}'
  AND activo = true
LIMIT 1;
-- Y el nodo IF "4.5 ¿Bot activo?" usa esta condición (booleana, true = sigue):
--   {{ $json.rol === 'empresario' || $json.agente_activo === true }}
-- TRUE  -> sigue al "5. Switch rol" (empresario SIEMPRE pasa; cliente solo si on).
-- FALSE -> rama de "bot apagado": NO responder al cliente (o handoff a Chatwoot).

-- ============================================================================
-- (B) TOGGLE — nodo Motor nuevo "3g. Estado agente" (fn = toggle_bot)
-- ----------------------------------------------------------------------------
-- Campos de entrada usados: negocio_id, accion, from_number.
--   accion ∈ 'activar' | 'desactivar' | 'estado'
-- Gate de actor: SOLO el dueño puede cambiar el estado (defensa en profundidad,
-- aunque la tool solo la tenga el agente Empresario).
WITH es_dueno AS (
  SELECT (dueno_telefono = '{{ $json.from_number }}') AS si
  FROM negocios WHERE id = '{{ $json.negocio_id }}'
),
upd AS (
  UPDATE negocios
  SET agente_activo = CASE
                        WHEN '{{ $json.accion }}' = 'activar'    THEN true
                        WHEN '{{ $json.accion }}' = 'desactivar' THEN false
                        ELSE agente_activo
                      END
  WHERE id = '{{ $json.negocio_id }}'
    AND (SELECT si FROM es_dueno) = true
    AND '{{ $json.accion }}' IN ('activar','desactivar')
  RETURNING agente_activo
)
SELECT
  CASE
    WHEN (SELECT si FROM es_dueno) IS NOT TRUE THEN
      'NO_AUTORIZADO: solo el responsable del negocio puede activar o apagar el asistente.'
    WHEN EXISTS (SELECT 1 FROM upd) THEN
      CASE WHEN (SELECT agente_activo FROM upd)
           THEN '✅ Asistente ACTIVADO. Vuelvo a responder a tus clientes.'
           ELSE '🔕 Asistente APAGADO. No responderé a tus clientes hasta que lo reactives (escríbeme "activar bot"). Tú sigues pudiendo hablar conmigo.'
      END
    ELSE
      -- accion = 'estado' (o no reconocida): informar estado actual, sin cambiar nada
      CASE WHEN (SELECT agente_activo FROM negocios WHERE id = '{{ $json.negocio_id }}')
           THEN 'El asistente está ACTIVADO ahora mismo.'
           ELSE 'El asistente está APAGADO ahora mismo. Escríbeme "activar bot" para encenderlo.'
      END
  END AS response;
