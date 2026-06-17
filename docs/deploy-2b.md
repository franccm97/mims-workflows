# Deploy GitHub → n8n (paso 2-B)

Hacer **desplegables** los JSON limpios del repo: poner la env var que referencian
y empujarlos a la instancia de n8n. **Repo manda, n8n recibe.**

> ⚠️ Esto toca la instancia de n8n (Hetzner). Lo corres **tú**. El asistente NO
> ejecuta nada contra producción: solo construye el tooling y estos pasos.

---

## Parte A — Env var en la instancia de n8n (una vez)

Los flujos limpios usan `={{ $env.CHATWOOT_API_TOKEN }}` en el header
`api_access_token`. n8n lo resuelve **en runtime** desde una env var del host. Sin
ella, los nodos HTTP que responden a Chatwoot fallan (401).

1. En el host de n8n, define `CHATWOOT_API_TOKEN` con el token del Agent Bot de
   Chatwoot. Según cómo esté montado n8n:

   **docker-compose** (lo típico): en el servicio `n8n`:
   ```yaml
   services:
     n8n:
       environment:
         - CHATWOOT_API_TOKEN=EL_TOKEN_REAL_AQUI
   ```
   Mejor aún, mete el valor en un `.env` del host (NO en el repo) y referencia
   `- CHATWOOT_API_TOKEN=${CHATWOOT_API_TOKEN}`.

2. Reinicia n8n para que tome la variable: `docker compose up -d` (o `restart`).

3. Asegúrate de que n8n permite leer env vars en expresiones. Por defecto sí; si
   alguien puso `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`, ponlo a `false`.

> Rotación: si el token estuvo expuesto (lo estuvo en exports antiguos), rótalo en
> Chatwoot y actualiza solo esta env var. Los JSON del repo no cambian.

---

## Parte B — API key de n8n (una vez)

Para que el script empuje los flujos: n8n → **Settings → n8n API → Create an API
key**. Cópiala. Es secreta: va en tu `.env` local / secrets de CI, **nunca al repo**.

```bash
# en tu máquina (o secrets del runner de CI), NO en el repo:
export N8N_BASE_URL="https://TU-INSTANCIA-n8n"     # sin barra final
export N8N_API_KEY="la-api-key-de-n8n"
```

---

## Parte C — Desplegar

Desde la raíz del repo:

```bash
# 1) DRY-RUN (por defecto): enseña qué actualizaría, NO escribe nada.
npm run deploy

# 2) Aplicar de verdad:
npm run deploy -- --live

# variantes:
npm run deploy -- --live --activate        # además activa cada workflow
npm run deploy -- --only motor             # solo el que matchee "motor"
npm run deploy -- --live --minimal-settings  # si n8n devuelve HTTP 400 por settings
```

El script **actualiza por id** (`PUT /api/v1/workflows/{id}`), conservando el id
del JSON. Empieza SIEMPRE por el dry-run.

---

## Cómo funciona / cuidado con

- **Actualiza, no crea.** Usa el `id` del JSON en la URL. Es crítico: las tools del
  agente referencian el Motor por id (`nzjWscGj9DoXKIzG`); crear nuevos ids las
  rompería. Si un id no existe en la instancia → HTTP 404: créalo una vez a mano
  (importando el JSON desde la UI) y luego ya se actualiza solo.
- **Campos read-only.** La API pública solo acepta `name/nodes/connections/settings`
  (+`staticData`). El script elimina `id, active, tags, pinData, meta, versionId`.
  El `pinData` (datos de test) se quita a propósito.
- **Estado activo.** El update NO cambia si el workflow está activo o no. Usa
  `--activate` para activarlo explícitamente, o hazlo desde la UI.
- **Credenciales.** Los nodos referencian credenciales (Postgres/Groq/Gemini) por
  id. Deben existir YA en la instancia destino; el deploy no las crea ni toca.
- **HTTP 400 por settings.** Algunas claves (`availableInMCP`, `timeSavedMode`)
  pueden no estar en el schema de tu versión de n8n → usa `--minimal-settings`.
- **Rollback.** Es git: `git checkout <commit-anterior> -- workflows/` y re-deploy.

---

## Alternativa: n8n CLI en el host

Si prefieres no usar la API, en el propio host (SSH) puedes importar el JSON con la
CLI de n8n (conserva ids):

```bash
docker compose exec n8n n8n import:workflow --input=/ruta/al/workflow.json
```

Requiere copiar el JSON al contenedor/volumen. La API (Parte C) es más cómoda para
CI porque corre desde fuera con solo la API key.
