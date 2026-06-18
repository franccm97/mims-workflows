# Prompt dinámico por vertical (BLOQUE 2)

**Objetivo:** que el System Message del bot NO esté escrito a fuego en n8n, sino que se
**arme solo** desde la **plantilla de la vertical** (en la DB) + los **datos del negocio**
(nombre, servicios, profesionales, horario). Resultado: cliente nuevo no necesita prompt
escrito a mano — se elige su `tipo_vertical` y el prompt se genera.

> ⚠️ Diseño + fragmentos. **NO desplegado, NO hand-editeado el flujo grande.** Franc lo
> cablea en DEV y reexporta (GitOps). Doctrina: la plantilla manda (criterio), los datos
> salen de la DB (fiabilidad).

---

## 1. Las piezas

1. **Tabla `verticales`** (migración `005_verticales_prompts.sql`): por cada vertical,
   `prompt_cliente` y `prompt_empresario` con marcadores
   `{NOMBRE_NEGOCIO}` `{SERVICIOS}` `{PROFESIONALES}` `{HORARIO}`. El **tono y las reglas**
   de la vertical viven aquí; los **datos** se inyectan en runtime. Enlaza con
   `negocios.tipo_vertical = verticales.vertical`. Idempotente (ON CONFLICT DO UPDATE).
2. **Nodo nuevo `4b. Montar prompt`** (Postgres) tras `4. Cargar negocio + rol`: lee la
   plantilla de la vertical del negocio + agrega sus servicios/profesionales/horario y
   devuelve el **`system_message`** ya montado (los `replace()` se hacen en SQL →
   determinista).
3. **`AI Agent` → Options → System Message** pasa de texto fijo a una **expresión** que
   lee ese `system_message`.

---

## 2. Qué datos se inyectan y de dónde

| Marcador | Origen (DB) |
|---|---|
| `{NOMBRE_NEGOCIO}` | `negocios.nombre` |
| `{SERVICIOS}` | `servicios` activos del negocio (nombre + duración + precio) |
| `{PROFESIONALES}` | `profesionales` activos del negocio (vacío → "(sin profesionales)") |
| `{HORARIO}` | `negocios.horario` |

Todo por `negocio_id` (el que ya resuelve `4. Cargar negocio + rol`). La plantilla
(cliente vs empresario) se elige por el `rol` que ese mismo nodo devuelve.

---

## 3. Fragmento — nodo `4b. Montar prompt` (Postgres, cred `DB DEV`)

Pega como `query` (monta el System Message en SQL; `replace()` anidados por marcador):
```sql
WITH n AS (
  SELECT id, nombre, tipo_vertical, horario
  FROM negocios WHERE id = '{{ $('4. Cargar negocio + rol').first().json.negocio_id }}'
),
svc AS (
  SELECT string_agg(
           nombre || ' (' || duracion_minutos || ' min' ||
           CASE WHEN precio > 0 THEN ', ' || precio::numeric(10,0) || '€' ELSE '' END || ')',
           E'\n- ' ORDER BY nombre) AS lista
  FROM servicios WHERE negocio_id = (SELECT id FROM n) AND activo = true
),
prof AS (
  SELECT string_agg(p.nombre, ', ' ORDER BY p.nombre) AS lista
  FROM profesionales p WHERE p.negocio_id = (SELECT id FROM n) AND p.activo = true
),
v AS (
  SELECT prompt_cliente, prompt_empresario
  FROM verticales WHERE vertical = (SELECT tipo_vertical FROM n)
)
SELECT replace(replace(replace(replace(
  CASE WHEN '{{ $('4. Cargar negocio + rol').first().json.rol }}' = 'empresario'
       THEN v.prompt_empresario ELSE v.prompt_cliente END,
  '{NOMBRE_NEGOCIO}', n.nombre),
  '{SERVICIOS}',     COALESCE((SELECT lista FROM svc), 'consúltanos')),
  '{PROFESIONALES}', COALESCE((SELECT lista FROM prof), '(sin profesionales)')),
  '{HORARIO}',       COALESCE(n.horario::text, '')) AS system_message
FROM n, v;
```

Conexión: `4. Cargar negocio + rol` → (gate/switch como hoy) → `4b. Montar prompt` →
agente. Un solo `4b` sirve a ambos agentes (el CASE por `rol` elige plantilla).

---

## 4. Fragmento — el `AI Agent` (System Message como expresión)

En el nodo `AI Agent` (y `AI Agent Empresario`), en **Options → System Message**:
```
={{ $('4b. Montar prompt').first().json.system_message }}
```

### ⚠️ No confundir los campos del AI Agent
- **Prompt / User Message** (arriba, "Source for Prompt"): es el **turno del usuario**
  (historial + "Mensaje actual"). Se queda como hoy (`Hoy es … / Conversación previa … /
  Mensaje actual …`).
- **Options → System Message**: es la **plantilla montada** (lo nuevo). AQUÍ va la
  expresión del punto 4, NO el historial.
- Meterlos al revés = el bot pierde el rol o pierde el contexto. Cuidado.

---

## 5. Cuidados / preguntas

- **Toda vertical en uso debe tener fila en `verticales`.** La migración 005 siembra las
  8. Si un negocio tiene un `tipo_vertical` sin plantilla → `system_message` saldría
  vacío. Guard recomendado: un `tipo_vertical` por defecto, o validar al dar de alta.
  ¿Quieres un fallback genérico en el SQL (si `v` no existe)? — decisión de Franc.
- **Las plantillas son editables sin tocar n8n:** cambiar el tono de una vertical = UPDATE
  en `verticales` (o nueva migración). El flujo no cambia.
- **Combina con multi-tenant (BLOQUE 1):** con tools dinámicas + prompt dinámico, alta de
  cliente = datos en DB y nada más.
- **No rompe Tasqueta:** mientras su flujo siga con el System Message fijo, igual; cuando
  migre al canónico + 4b, su plantilla de `restaurante` reproduce el mismo tono.
- **Prueba en DEV:** con la estética (003) y un restaurante (004), montar `4b` y verificar
  que el System Message resultante lista los servicios/profesionales correctos de cada uno.
