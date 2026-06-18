# Multi-tenant: matar el `negocio_id` hardcodeado (BLOQUE 1)

**Objetivo:** alta de cliente nuevo = **una fila en la DB, CERO tocar n8n.** Un único
flujo canónico atiende a todos los negocios; el `negocio_id` se resuelve por datos, no
está a fuego en ninguna tool.

> ⚠️ Diseño + fragmentos. **NO desplegado, NO hand-editeado el flujo grande.** Franc
> lo cablea en DEV y reexporta (GitOps).

---

## 1. Dónde estamos (medido en el repo, no de memoria)

El nodo **`4. Cargar negocio + rol`** ya resuelve el negocio por el
`chatwoot_account_id` que entra por Chatwoot:
```sql
... CASE WHEN dueno_telefono = '{{ $('2. Parsear Meta').first().json.from }}'
         THEN 'empresario' ELSE 'cliente' END AS rol ...
FROM negocios
WHERE chatwoot_account_id = '{{ $('2. Parsear Meta').first().json.account_id }}'
```
→ devuelve `negocio_id` (+ rol, horario, etc). **Esa es la pieza clave del multi-tenant,
y ya está.** Solo falta que las tools la usen.

Estado real de las tools (`node` sobre los JSON del repo):

| Flujo | Tools | `negocio_id` |
|---|---|---|
| **canónico** (`workflows/canonico/`) | 9 | ✅ DINÁMICO ya (`={{ $('4. Cargar negocio + rol')… }}`) |
| **tasqueta** (`workflows/tasqueta/`) | 10 | ❌ HARDCODE `8d0ce837…` en las 10 |

**Conclusión:** el **canónico ya es multi-tenant**. Es la plantilla. Los flujos por
cliente (tasqueta) hardcodean → hay que jubilarlos en favor del canónico, o (si se
mantienen) pasar sus tools a la expresión dinámica.

---

## 2. El cambio (por tool)

En CADA tool (nodo `toolWorkflow`), en su **Workflow Inputs**, el campo `negocio_id`
pasa de literal a expresión. **Solo cambia esa línea; el resto del input se queda igual.**

Antes (tasqueta):
```json
"negocio_id": "8d0ce837-82a2-4d0f-bf55-95d581d7d680"
```
Después (multi-tenant):
```json
"negocio_id": "={{ $('4. Cargar negocio + rol').first().json.negocio_id }}"
```

### Las 10 tools de tasqueta a tocar
`CONSULTAR` · `CREAR` · `CANCELAR CITA` · `MODIFICAR` · `MIS_RESERVAS` ·
`EMP crear_reserva1` · `EMP cancelar_reserva1` · `EMP modificar_reserva1` ·
`EMP ver_agenda1` · `EMP estado_agente`.

(En el canónico ya están las 9 así; `EMP estado_agente` no existe aún allí — se añade
con el BLOQUE 3.)

### Fragmento de referencia (cómo queda el Workflow Inputs de una tool)
Ej. `CONSULTAR` (las demás igual, cambiando solo `fn` y los `$fromAI` propios):
```json
"workflowInputs": {
  "mappingMode": "defineBelow",
  "value": {
    "fn": "consultar",
    "negocio_id": "={{ $('4. Cargar negocio + rol').first().json.negocio_id }}",
    "servicio": "={{ $fromAI('servicio', 'tipo de servicio o mesa') }}",
    "fecha": "={{ $fromAI('fecha', 'el dia que pide el cliente tal cual') }}",
    "nombre": "={{ $('2. Parsear Meta').first().json.nombre }}",
    "from_number": "={{ $('2. Parsear Meta').first().json.from }}"
  }
}
```
El `workflows/canonico/canonico.json` del repo ya tiene las 9 tools exactamente así:
**úsalo como fuente** (copia el `negocio_id` de ahí).

---

## 3. ⚠️ Trampa del schema cacheado de las tools (LÉELO)

Las tools `toolWorkflow` guardan un `schema` cacheado de los inputs del sub-workflow.

- **NO pulses el botón 🔄 "sync"/refresh** del schema de la tool. Re-deriva el schema y
  **marca todos los campos como `required`** → el agente se ve forzado a rellenarlos
  todos y las tools **se rompen** (manda basura en campos que deberían ir vacíos).
- Edita el `negocio_id` **a mano** en el Workflow Inputs (modo `defineBelow`), sin tocar
  el schema. Si añades un campo nuevo (p.ej. `accion` del toggle), añádelo a mano al
  schema también, dejándolo `required: false`.
- Tras el cambio, **reexporta** el flujo y pásalo por `scrub` antes de commitear.

---

## 4. Alta de cliente nuevo (el objetivo, una vez hecho esto)

```sql
-- 1 fila + su catálogo. CERO n8n.
INSERT INTO negocios (slug, nombre, tipo_vertical, chatwoot_account_id, dueno_telefono,
                      horario, capacidad_simultanea, corte_franja)   -- + agente_activo def true
VALUES (...);
INSERT INTO servicios (negocio_id, nombre, duracion_minutos, precio) VALUES ...;
-- si usa profesionales:
INSERT INTO profesionales (...);  INSERT INTO profesional_servicios (...);
```
El canónico, al llegar un mensaje de ese negocio (su `chatwoot_account_id`), resuelve el
`negocio_id` y todas las tools operan sobre SUS datos. (Falta conectar el inbox de
Chatwoot del negocio nuevo → eso es Chatwoot, no n8n.)

---

## 5. Checklist de prueba en DEV (demuestra el aislamiento)

Con dos negocios DEV de verticales distintas — p.ej. **Clínica Estética Aura**
(`40000000-0000-0000-0000-000000000004`, migración 003) y un **restaurante**
(`a0000000-0000-0000-0000-000000000001`, migración 004) — cada uno con su
`chatwoot_account_id` (`90004` y `9101`):

1. Cablea el canónico en DEV con las tools dinámicas (o jubila tasqueta y usa canónico).
2. Mensaje simulando el `account_id` de la **estética** → `consultar` un servicio →
   debe ofrecer SUS servicios/profesionales (Botox, Laura…), NO los del restaurante.
3. Mensaje simulando el `account_id` del **restaurante** → `consultar` → mesas, sin
   profesionales. Reserva → cae en el restaurante.
4. **Aislamiento:** crea una reserva en cada uno y verifica en la DB que cada fila tiene
   su `negocio_id` correcto y que ninguno ve las reservas del otro
   (`SELECT negocio_id, count(*) FROM reservas GROUP BY 1`).
5. Repite `agenda` como dueño de cada negocio → solo ve SUS citas (gate de actor ya
   existente).

Si los dos negocios operan cada uno sobre sus datos sin cruzarse → multi-tenant OK.

---

## 6. Relación con otros bloques
- **BLOQUE 2** (prompt dinámico): el System Message también dejará de estar a fuego;
  se arma desde la vertical del negocio + sus datos. Mismo principio "datos, no n8n".
- **BLOQUE 3** (toggle): el canónico necesita que `4. Cargar negocio + rol` traiga
  `agente_activo` (hoy el canónico no lo trae; tasqueta sí). Ver `docs/toggle-bot.md`.
