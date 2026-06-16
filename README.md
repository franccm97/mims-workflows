# mims-workflows

**Fuente de verdad (Git) de los workflows de n8n de mims.** Los flujos de los
agentes de reserva viven aquí versionados y **limpios de secretos**. Principio:
**el repo manda, n8n recibe.**

> Hoy los flujos solo existen dentro de n8n: si se borran o rompen, no hay vuelta
> atrás, y "pasar a prod" es copiar/pegar JSON a mano. Este repo arregla eso: da
> historial y una plantilla limpia. El deploy automático GitHub→n8n es el paso 2-B
> (otro encargo); esto (2-A) es el esqueleto + el tooling de limpieza.

## ⚠️ Por qué hace falta limpiar (léelo)

n8n exporta los flujos con **secretos EN CLARO dentro del JSON** — sobre todo el
**token del Agent Bot de Chatwoot**, pegado en el header `api_access_token` de los
nodos HTTP. Un `.gitignore` NO protege esto (el secreto está DENTRO del archivo).
Si commiteas el JSON tal cual, el token queda en el historial de Git **para
siempre**, aunque lo rotes. Por eso: **siempre `scrub` antes de commitear**, y hay
un **guard** que bloquea el commit si algo se cuela.

Lo que **NO** es secreto y se queda igual: las referencias a credenciales de n8n
(`{"id","name"}` de Postgres/Groq/Gemini) — no llevan el valor del secreto.

## Setup (una vez)

```bash
npm run hooks:install   # activa el guard de pre-commit (git config core.hooksPath .githooks)
```

## Flujo de trabajo (export → scrub → commit)

1. **Exportar** el flujo desde n8n: menú `⋯` del workflow → **Download**. Guárdalo
   como `*.raw.json` (el `.gitignore` ya ignora los `.raw.json`, así el crudo con
   secretos nunca se versiona). Ej: `motor.raw.json`.
2. **Limpiar:**
   ```bash
   node scripts/scrub.mjs motor.raw.json
   # -> escribe motor.json (limpio) y dice qué reemplazó
   ```
3. **Colocar** el JSON limpio en su carpeta: `workflows/motor/motor.json`
   (o `canonico/`, `voz/`).
4. **Commitear.** El guard (pre-commit) escanea y, si encuentra un token, **falla**
   el commit. Si pasa, está limpio.
   ```bash
   git add workflows/motor/motor.json
   git commit -m "motor: <qué cambió>"
   ```

> Si el guard te bloquea: NO uses `--no-verify`. Vuelve al paso 2 (scrub) o añade
> la regla que falte en `scripts/scrub.mjs` (lista `RULES`).

## Disciplina

Si tocas un flujo en la UI de n8n, **actualízalo también aquí** (export → scrub →
commit). Si no, el repo y n8n divergen y se pierde la fuente de verdad.

## Comandos

```bash
npm run scrub -- <archivo.json>   # limpia un export
npm run check-secrets             # escanea lo staged (lo que corre el guard)
npm test                          # tests del scrub + guard
```

## Estructura

```
workflows/   JSON limpios (canonico/ · motor/ · voz/)
clientes/    config de referencia por cliente (datos NO sensibles)
scripts/     scrub.mjs · check-secrets.mjs
.githooks/   pre-commit
```

## Qué NO está aquí (es 2-B)

Hacer estos JSON **desplegables**: poner las env vars (`CHATWOOT_API_TOKEN`...) en
la instancia de n8n (Hetzner) + un script de deploy GitHub→n8n. Un JSON con
`={{ $env.CHATWOOT_API_TOKEN }}` **no funciona** re-importado hasta que esa env var
exista en n8n. Aquí solo está la **fuente de verdad limpia** + el tooling.
