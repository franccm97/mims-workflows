# PLAN DE DESPLIEGUE A DEV — receta paso a paso

> Síguela sin pensar. Orden: **(0) migraciones 005/006 → (1) Motor toggle → (2) flujo
> cliente**. SIEMPRE dry-run antes de cada `--live`. Nada de esto toca producción.
> El guard anti-prod bloquea el Motor PROD `nzjWscGj9DoXKIzG`.

Antes de nada, en `mims-workflows`, activa el guard de commits:
```bash
npm install            # trae 'pg' (lo usa el runner de migraciones)
npm run hooks:install
```

---

## (a) PASO 0 — Migraciones 005 y 006 contra `mims_dev`

### 0.1 Reúne las migraciones 001→006 en el working tree
Están repartidas en ramas (nada mergeado). Júntalas sin mergear:
```bash
git checkout feat/prompt-dinamico                                   # trae 001..005
git checkout feat/toggle-bot-cierre -- migrations/006_mensaje_bot_apagado.sql   # +006
ls migrations/   # debe listar 001..006
```

### 0.2 Averigua cómo llegar a la DB (postgres está dentro de Docker)
```bash
docker ps                       # nombre del contenedor postgres + columna PORTS
# ¿password? cualquiera de estas:
docker exec <PG> env | grep POSTGRES        # POSTGRES_PASSWORD=...
# (o míralo en la credencial "DB DEV" de n8n, o en tu docker-compose)
```
- DB: `mims_dev` · usuario: `n8n`.
- En `docker ps`, mira la columna **PORTS** del contenedor postgres:
  - Si ves `0.0.0.0:5432->5432/tcp` → el puerto está **publicado** → usa **Método A**.
  - Si NO aparece (solo `5432/tcp`) → **interno** → usa **Método B**.

### 0.3 Aplica las migraciones (elige UN método)

> La contraseña va por `PGPASSWORD` (fuera de la URL), así no la pegas en claro en la
> connection string. Si tu DB no pide contraseña, omite `PGPASSWORD`.

**Método A — puerto publicado (corres el runner desde tu PC, con tracking):**
```bash
export PGPASSWORD='<PASS>'
export DATABASE_URL='postgresql://n8n@localhost:5432/mims_dev'   # sin contraseña en la URL
npm run migrate -- --dry-run      # lista 005, 006 (001..004 ya estarán si corriste setup-dev-db)
npm run migrate                   # aplica las pendientes, en orden, cada una en su transacción
```

**Método B — postgres interno (corres el runner DENTRO de la red Docker, con tracking):**
```bash
# <NET> = red del contenedor postgres:  docker inspect <PG> --format '{{json .NetworkSettings.Networks}}'
docker run --rm -it --network <NET> -e PGPASSWORD='<PASS>' -v "$PWD":/app -w /app node:20 sh -lc '
  npm install &&
  DATABASE_URL="postgresql://n8n@<PG>:5432/mims_dev" node scripts/migrate.mjs --dry-run &&
  DATABASE_URL="postgresql://n8n@<PG>:5432/mims_dev" node scripts/migrate.mjs'
```
(`<PG>` = nombre del contenedor postgres; dentro de la red se resuelve por nombre.)

**Método C — atajo sin runner (psql directo; las migraciones son idempotentes):**
```bash
for f in migrations/005_verticales_prompts.sql migrations/006_mensaje_bot_apagado.sql; do
  docker exec -e PGPASSWORD='<PASS>' -i <PG> psql -U n8n -d mims_dev < "$f"
done
```
> Método C no registra en `schema_migrations`, pero 005/006 son idempotentes
> (`IF NOT EXISTS` / `ON CONFLICT DO UPDATE`) → re-aplicarlas no rompe nada. Usa A o B
> si quieres el registro limpio.

### 0.4 Verifica
```bash
docker exec -e PGPASSWORD='<PASS>' -it <PG> psql -U n8n -d mims_dev -c "\d negocios" | grep -E "agente_activo|mensaje_bot_apagado|capacidad_simultanea|corte_franja"
docker exec -e PGPASSWORD='<PASS>' -it <PG> psql -U n8n -d mims_dev -c "SELECT vertical FROM verticales ORDER BY 1;"
```
Esperado: las columnas existen y la tabla `verticales` tiene las 8 filas.

---

## (b) PASO 1 — Motor DEV: rama `toggle_bot` (fragmentos LISTOS para cablear)

Esto lo cableas TÚ en el Motor DEV (`6UgauiTycOIrC7ES`) en la UI de n8n. Son 4 cambios.

### 1.1 Trigger "Trigger (desde agente)" — añade el input `accion`
En **Workflow Inputs**, añade a la lista (a mano, NO uses el botón 🔄):
```json
{ "name": "accion" }
```

### 1.2 Nodo "2. Router fn" — añade una salida `toggle_bot`
Añade una regla más (queda como la 7ª salida del Switch):
```json
{
  "conditions": {
    "options": { "caseSensitive": true, "typeValidation": "strict", "version": 1 },
    "conditions": [
      { "id": "c-togglebot", "leftValue": "={{ $json.fn }}", "rightValue": "toggle_bot",
        "operator": { "type": "string", "operation": "contains" } }
    ],
    "combinator": "and"
  },
  "renameOutput": true, "outputKey": "toggle_bot"
}
```

### 1.3 Nodo nuevo "3g. Toggle bot" (Postgres, cred `DB DEV`)
`operation: executeQuery`, `query`:
```sql
WITH es_dueno AS (
  SELECT (dueno_telefono = '{{ $json.from_number }}') AS si
  FROM negocios WHERE id = '{{ $json.negocio_id }}'
),
upd AS (
  UPDATE negocios
  SET agente_activo = CASE
        WHEN '{{ $json.accion }}' = 'activar'    THEN true
        WHEN '{{ $json.accion }}' = 'desactivar' THEN false
        ELSE agente_activo END
  WHERE id = '{{ $json.negocio_id }}'
    AND (SELECT si FROM es_dueno) = true
    AND '{{ $json.accion }}' IN ('activar','desactivar')
  RETURNING agente_activo
)
SELECT
  CASE
    WHEN (SELECT si FROM es_dueno) IS NOT TRUE THEN
      'NO_AUTORIZADO: solo el responsable puede activar o apagar el asistente.'
    WHEN EXISTS (SELECT 1 FROM upd) THEN
      CASE WHEN (SELECT agente_activo FROM upd)
           THEN 'ACTIVADO: vuelvo a responder a tus clientes.'
           ELSE 'APAGADO: no responderé a tus clientes hasta que lo reactives.' END
    ELSE
      CASE WHEN (SELECT agente_activo FROM negocios WHERE id = '{{ $json.negocio_id }}')
           THEN 'ESTADO: el asistente está ACTIVADO.'
           ELSE 'ESTADO: el asistente está APAGADO.' END
  END AS response;
```

### 1.4 Conexión
`2. Router fn` (salida **toggle_bot**, la nueva) → `3g. Toggle bot`. El nodo es terminal
(devuelve `response`, igual que `3d`/`3f`).

### 1.5 Probar en n8n (pin manual) y desplegar
- Pin del Trigger: `{ "fn":"toggle_bot", "accion":"desactivar", "negocio_id":"<id estética DEV>", "from_number":"<dueño>" }` → debe devolver "APAGADO". Con `from_number` de un no-dueño → "NO_AUTORIZADO".
- Exporta el Motor → `scrub` → coloca en `workflows/motor/motor.json` → commit. Luego:
```bash
N8N_BASE_URL='https://<n8n-dev>' N8N_API_KEY='<key>' npm run deploy -- --only motor --minimal-settings           # DRY-RUN
N8N_BASE_URL='https://<n8n-dev>' N8N_API_KEY='<key>' npm run deploy -- --only motor --minimal-settings --live    # aplica
```
Dry-run debe decir `PUT .../workflows/6UgauiTycOIrC7ES`. Si dijera `nzjW…` → estás en la
rama equivocada (el guard lo bloquea de todas formas).

---

## (c) PASO 2 — Flujo cliente

> ⚠️ Tu export DEV manda. Cabla A/B/C en TU n8n DEV (usa la rama `feat/flujo-cliente-cableado`
> como referencia del cómo), prueba, **exporta**, `scrub`, commit, y despliega TU export.

Cambios a cablear (referencia: `feat/flujo-cliente-cableado`, ver `docs/multitenant.md`,
`docs/prompt-dinamico.md`, `docs/toggle-bot.md`):
- **A** nodo `4b. Montar prompt` + System Message de ambos agentes = expresión.
- **B** `profesional` (value + schema, required:false) en CONSULTAR/CREAR/MODIFICAR +
  EMP crear_reserva1/EMP modificar_reserva1.
- **C** `4. Cargar` trae `agente_activo`+`mensaje_apagado`; `4.5 ¿Bot activo?`; rama FALSE
  = `Cortesia bot off` + `Handoff (bot off)`; tool `EMP toggle_bot` (fn=toggle_bot).

Desplegar:
```bash
# tras exportar+scrub tu flujo a workflows/<carpeta>/<flujo>.json
N8N_BASE_URL='https://<n8n-dev>' N8N_API_KEY='<key>' npm run deploy -- --only <flujo>            # DRY-RUN -> debe ser tu ID DEV (EA3TJVZb03f1OugA)
N8N_BASE_URL='https://<n8n-dev>' N8N_API_KEY='<key>' npm run deploy -- --only <flujo> --live     # aplica
```

---

## (d) CHECKLIST DE PRUEBAS (en DEV, tras desplegar)

**Migraciones:** columnas `agente_activo`/`mensaje_bot_apagado`/`capacidad_simultanea`/
`corte_franja` existen; `verticales` con 8 filas (paso 0.4).

**Motor toggle:** pin `fn=toggle_bot accion=desactivar` (dueño) → APAGADO; no-dueño →
NO_AUTORIZADO; `accion=estado` → informa sin cambiar.

**Flujo cliente:**
1. Estética, "quiero botox" sin profesional → **pide elegir profesional**.
2. "...con Laura" → huecos de Laura; reservar → fila con `profesional_id` de Laura.
3. Dos clientes, misma hora, profesionales distintos → **ambas reservas** (no choca).
4. "apaga el bot" (empresario) → un cliente escribe → recibe **cortesía** + la conversa
   pasa a **open** (handoff). "activar bot" → vuelve a responder.
5. **Prompt dinámico:** el bot saluda con el **nombre del negocio** y lista **sus**
   servicios/profesionales (no Tasqueta).
6. **Aislamiento:** negocio A no ve reservas/agenda de B.

**Red de seguridad antes de tocar nada:** en `mims-qa`, `npm run test:db` → 221 verde.
Si algo del cableado rompe el contrato del Motor, sale rojo aquí ANTES de producción.

---

## Resumen de IDs y ramas
- Motor DEV: `6UgauiTycOIrC7ES` (cred `DB DEV`). Motor PROD (NO tocar): `nzjWscGj9DoXKIzG`.
- Flujo cliente DEV: `EA3TJVZb03f1OugA`.
- Ramas: `feat/prompt-dinamico` (mig 001-005), `feat/toggle-bot-cierre` (mig 006 + diseño
  toggle), `feat/motor-profesionales` (Motor DEV), `feat/flujo-cliente-cableado` (flujo
  A/B/C de referencia), `feat/deploy-prod-guard` (guard). QA: `feat/qa-multitenant-toggle`.
