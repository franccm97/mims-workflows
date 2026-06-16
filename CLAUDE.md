# CLAUDE.md — mims-workflows

Fuente de verdad (Git) de los **workflows de n8n** de mims (agentes de reserva,
self-hosted en Hetzner). Relación: **el repo manda, n8n recibe**. Los flujos viven
aquí versionados y LIMPIOS de secretos; el deploy a n8n es otro paso (2-B).

## Reglas (no negociable)

1. **NUNCA commitear secretos.** Los JSON que exporta n8n traen secretos EN CLARO
   dentro del propio archivo (sobre todo el token del Agent Bot de Chatwoot, en el
   header `api_access_token` de los nodos HTTP). Un `.gitignore` NO basta: el
   secreto está DENTRO del JSON. Hay que pasarlo por `scrub` ANTES de commitear.
2. **Todo JSON va LIMPIO.** Antes de commitear un flujo: `node scripts/scrub.mjs <archivo>`
   → reemplaza el token por `={{ $env.CHATWOOT_API_TOKEN }}`.
3. **El guard manda.** Un hook de pre-commit (`scripts/check-secrets.mjs`) BLOQUEA
   el commit si detecta un token. Si salta, NO lo fuerces: limpia el JSON.
4. **NO tocar producción desde aquí.** Este repo no despliega ni se conecta a n8n
   ni a la DB. Solo versiona JSON. (El deploy GitHub→n8n es el paso 2-B.)
5. **Lo que NO es secreto:** las REFERENCIAS a credenciales de n8n
   (`{"id","name"}` de Postgres/Groq/Gemini) NO contienen el valor → son seguras,
   no se tocan. Solo se limpian los VALORES hardcodeados (token de Chatwoot, etc.).
6. **Disciplina:** si cambias un flujo en la UI de n8n, actualízalo también aquí
   (export → scrub → commit), o repo y n8n divergen.

## Estructura

```
workflows/   JSON LIMPIOS de los flujos (canonico/ motor/ voz/)
clientes/    config de referencia por cliente (datos NO sensibles)
scripts/     scrub.mjs (limpia secretos) · check-secrets.mjs (guard)
.githooks/   pre-commit (corre el guard)
```

## Comandos

```bash
npm run scrub -- <archivo.json>   # limpia un export de n8n
npm run hooks:install             # activa el guard de pre-commit
npm test                          # tests del scrub + guard
```

## Qué es 2-B (todavía NO está aquí)

Hacer los JSON limpios DESPLEGABLES: poner las env vars (`CHATWOOT_API_TOKEN`...)
en la instancia de n8n + un script de deploy GitHub→n8n. Un JSON con
`={{ $env.CHATWOOT_API_TOKEN }}` NO funciona re-importado hasta que esa env var
exista en n8n. Este repo (2-A) es solo la fuente de verdad versionada y limpia.
