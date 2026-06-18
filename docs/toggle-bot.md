# Apagar / encender el asistente por WhatsApp (TAREA 4)

El empresario puede **apagar** el bot ("apaga el bot") para que deje de responder a
sus clientes, y **encenderlo** de nuevo ("activar bot"). Usa la columna
`negocios.agente_activo` (boolean, default true, **ya existe**).

> ⚠️ Diseño + SQL + fragmentos JSON. **NO desplegado.** Franc lo cablea en el Motor/
> flujo DEV, lo prueba y reexporta (GitOps). No se ha hand-editeado el JSON grande del
> Motor para no arriesgar romperlo sin n8n que valide.

Doctrina: la decisión (¿responde el bot?) y el cambio de estado viven en **SQL/datos**,
no en el prompt. Gate de actor: **solo el dueño** puede cambiar el estado.

---

## Cómo funciona (2 piezas)

### (a) Gate: el bot no responde al cliente si está apagado
En el flujo **cliente** (canónico), tras cargar el negocio:
- `4. Cargar negocio + rol` debe traer `agente_activo` (Tasqueta ya lo trae; el
  canónico no — alinearlo). SELECT en [db/toggle-bot.sql](../db/toggle-bot.sql) sección (A).
- Nodo IF `4.5 ¿Bot activo?` con condición booleana:
  ```
  {{ $json.rol === 'empresario' || $json.agente_activo === true }}
  ```
  - **TRUE** → sigue al `5. Switch rol`. El **empresario SIEMPRE pasa** (por eso puede
    reactivarlo aunque esté apagado).
  - **FALSE** (cliente + bot apagado) → rama "bot off": no responder al cliente (o
    handoff a Chatwoot, ver pregunta abajo).

### (b) Tool del empresario `toggle_bot` → UPDATE
El agente Empresario gana una tool que llama al Motor con `fn = toggle_bot` y
`accion ∈ activar | desactivar | estado`. El Motor hace el UPDATE (gateado al dueño).
Query en [db/toggle-bot.sql](../db/toggle-bot.sql) sección (B).

---

## Contrato

Entrada (campos del Motor usados): `fn=toggle_bot`, `negocio_id`, `accion`, `from_number`.
- `accion`: `desactivar` (apagar), `activar` (encender), `estado` (consultar, no cambia).
Salida: `response` (texto para el agente). Solo el dueño puede activar/desactivar; un
no-dueño recibe `NO_AUTORIZADO`.

---

## Fragmentos JSON para cablear en n8n (DEV)

> El parámetro nuevo del Motor es **`accion`**. Hay que declararlo en el Trigger.

**1) Trigger `(desde agente)` → `workflowInputs.values`: añadir**
```json
{ "name": "accion" }
```

**2) `2. Router fn` → nueva regla (outputKey `toggle_bot`)**
```json
{
  "conditions": {
    "options": { "caseSensitive": true, "typeValidation": "strict", "version": 1 },
    "conditions": [
      { "id": "c-toggle", "leftValue": "={{ $json.fn }}", "rightValue": "toggle_bot",
        "operator": { "type": "string", "operation": "contains" } }
    ],
    "combinator": "and"
  },
  "renameOutput": true,
  "outputKey": "toggle_bot"
}
```

**3) Nodo Motor nuevo `3g. Estado agente` (Postgres, cred `DB DEV`)** — pega como
`query` la sección (B) de `db/toggle-bot.sql`:
```json
{
  "parameters": {
    "operation": "executeQuery",
    "query": "<<pega aquí la query (B) de db/toggle-bot.sql>>",
    "options": {}
  },
  "name": "3g. Estado agente",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2.5,
  "credentials": { "postgres": { "id": "UZezTWtSmrQ7w46T", "name": "DB DEV" } }
}
```
Conexión: salida `toggle_bot` del `2. Router fn` → `3g. Estado agente`. (Su output ya
es el `response`, igual que consultar/agenda; no pasa por "Aviso empresario?".)

**4) Tool del agente Empresario `EMP toggle_bot` (toolWorkflow → Motor)**
```json
{
  "parameters": {
    "name": "toggle_bot",
    "description": "Activa, apaga o consulta el asistente automatico que responde a los clientes. accion='desactivar' para apagarlo, 'activar' para encenderlo, 'estado' para consultar. Solo el responsable puede.",
    "workflowId": { "__rl": true, "value": "6UgauiTycOIrC7ES", "mode": "list", "cachedResultName": "TOOLS MOTOR DE RESERVAS" },
    "workflowInputs": {
      "mappingMode": "defineBelow",
      "value": {
        "fn": "toggle_bot",
        "negocio_id": "={{ $('4. Cargar negocio + rol').first().json.negocio_id }}",
        "accion": "={{ $fromAI('accion', \"'activar', 'desactivar' o 'estado'\", 'string') }}",
        "from_number": "={{ $('2. Parsear Meta').first().json.from }}"
      },
      "matchingColumns": [], "schema": [], "attemptToConvertTypes": false, "convertFieldsToString": false
    }
  },
  "name": "EMP toggle_bot",
  "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
  "typeVersion": 2.2
}
```
Conexión: `EMP toggle_bot` → `AI Agent Empresario` (tipo `ai_tool`). La tool **solo**
se conecta al agente Empresario (el agente Cliente NO la tiene).

Y en el system prompt del agente Empresario, una línea: *"Si te pido apagar/pausar el
asistente para clientes, llama a toggle_bot con accion 'desactivar'; para encenderlo,
'activar'. Tú siempre puedes hablar conmigo aunque esté apagado."*

---

## Seguridad

- **Doble gate:** (1) la tool solo está en el agente Empresario; (2) el UPDATE exige
  `dueno_telefono = from_number`. Un cliente nunca puede apagar el bot ni aunque
  forzara la llamada.
- `accion='estado'` es de solo lectura.
- El empresario SIEMPRE pasa el `4.5 ¿Bot activo?`, así que puede reactivarlo aunque
  esté apagado.

---

## BLOQUE 3 — Cierre: cortesía + handoff (decisión CONFIRMADA de Franc)

Cuando el empresario apaga el bot (`agente_activo = false`) y escribe un **cliente**,
pasan DOS cosas a la vez (**nunca silencio**):
1. El cliente recibe un **mensaje de cortesía** (`negocios.mensaje_bot_apagado`, o un
   genérico si está vacío).
2. La conversación pasa a **handoff en Chatwoot** (`toggle_status` → `open`) para que la
   coja un humano.

El **empresario** sigue operando con normalidad (puede reactivar con "activar bot"),
porque siempre pasa el `4.5 ¿Bot activo?`. **Integrado en el flujo** (no sub-workflow).

### Datos
- Migración **`006_mensaje_bot_apagado.sql`**: `ALTER TABLE negocios ADD COLUMN IF NOT
  EXISTS mensaje_bot_apagado text` (idempotente; NULL → genérico).
- El SELECT de `4. Cargar negocio + rol` ya devuelve `mensaje_apagado` con el COALESCE
  genérico (ver `db/toggle-bot.sql` sección A).

### Rama FALSE del `4.5 ¿Bot activo?` (cliente + bot apagado): 2 nodos en serie

**1) `Cortesia bot off`** — envía el mensaje de cortesía al cliente:
```json
{
  "parameters": {
    "method": "POST",
    "url": "=https://inbox.mims.studio/api/v1/accounts/{{ $('2. Parsear Meta').first().json.account_id }}/conversations/{{ $('2. Parsear Meta').first().json.conversation_id }}/messages",
    "sendHeaders": true,
    "headerParameters": { "parameters": [
      { "name": "Content-Type", "value": "application/json" },
      { "name": "api_access_token", "value": "={{ $env.CHATWOOT_API_TOKEN }}" }
    ]},
    "sendBody": true, "specifyBody": "json",
    "jsonBody": "={\n  \"content\": {{ JSON.stringify($('4. Cargar negocio + rol').first().json.mensaje_apagado) }},\n  \"message_type\": \"outgoing\"\n}",
    "options": {}
  },
  "name": "Cortesia bot off",
  "type": "n8n-nodes-base.httpRequest",
  "typeVersion": 4.4
}
```

**2) `Handoff (bot off)`** — pasa la conversación a un humano (toggle_status → open):
```json
{
  "parameters": {
    "method": "POST",
    "url": "=https://inbox.mims.studio/api/v1/accounts/{{ $('2. Parsear Meta').first().json.account_id }}/conversations/{{ $('2. Parsear Meta').first().json.conversation_id }}/toggle_status",
    "sendHeaders": true,
    "headerParameters": { "parameters": [
      { "name": "Content-Type", "value": "application/json" },
      { "name": "api_access_token", "value": "={{ $env.CHATWOOT_API_TOKEN }}" }
    ]},
    "sendBody": true, "specifyBody": "json",
    "jsonBody": "{ \"status\": \"open\" }",
    "options": {}
  },
  "name": "Handoff (bot off)",
  "type": "n8n-nodes-base.httpRequest",
  "typeVersion": 4.4
}
```
Conexión: `4.5 ¿Bot activo?` (salida FALSE) → `Cortesia bot off` → `Handoff (bot off)`.
(Tasqueta ya tenía un "Pasar a Chatwoot (bot off)" = el nodo 2; solo se añade el 1 antes.)
El token va como `={{ $env.CHATWOOT_API_TOKEN }}` (lo resuelve n8n; ver `docs/deploy-2b.md`).

---

## Decisiones de Franc (confirmadas)
- ✅ Integrar en el **flujo** (no sub-workflow).  ✅ Bot apagado = **cortesía + handoff**.
- ✅ `agente_activo` **default true**.  ✅ Toggle vía Motor `fn=toggle_bot` + `accion`.

## Pregunta abierta
- El texto genérico de cortesía está en el SQL (`db/toggle-bot.sql` A). ¿Lo quieres
  distinto, o por idioma? (hoy es uno en español).
