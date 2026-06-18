// deploy.mjs — empuja los workflows LIMPIOS del repo a una instancia de n8n
// (GitHub -> n8n) vía la REST API pública. Es el paso 2-B.
//
//   node scripts/deploy.mjs                 # DRY-RUN: enseña qué haría, NO escribe
//   node scripts/deploy.mjs --live          # aplica de verdad (PUT a n8n)
//   node scripts/deploy.mjs --live --activate   # además activa cada workflow
//   node scripts/deploy.mjs --only motor    # filtra por nombre de archivo/carpeta
//   node scripts/deploy.mjs --minimal-settings  # manda settings mínimos (si n8n 400ea)
//
// SEGURIDAD: empujar al Motor PROD (id nzjWscGj9DoXKIzG) está BLOQUEADO salvo que
// pases --allow-prod (no deberías necesitarlo nunca desde aquí). Antes de cada PUT
// real se imprime "→ actualizar <id> (<nombre>) en <base>" para que veas el destino.
//
// Config por entorno (NO en el repo; ver .env.example):
//   N8N_BASE_URL   p.ej. https://n8n.mims.studio   (sin barra final)
//   N8N_API_KEY    API key de n8n (Settings -> n8n API). Va en header X-N8N-API-KEY.
//
// IMPORTANTE
// - ACTUALIZA por ID (PUT /workflows/{id}); conserva el id del JSON. Es clave: las
//   tools del agente referencian el Motor por id (nzjWscGj9DoXKIzG). Crear en vez
//   de actualizar generaría ids nuevos y rompería esas referencias.
// - La API pública es estricta: solo acepta {name, nodes, connections, settings,
//   staticData}. Se ELIMINAN campos read-only (id, active, tags, pinData, meta,
//   versionId...). El id solo se usa en la URL.
// - El placeholder ={{ $env.CHATWOOT_API_TOKEN }} NO se toca: n8n lo resuelve en
//   runtime desde la env var del host (hay que ponerla allí; ver docs/deploy-2b.md).
// - Las credenciales (Postgres/Groq/Gemini) son REFERENCIAS por id: deben existir
//   ya en la instancia destino (la misma de Franc). Este script no las crea.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, basename } from "node:path";
import { fileURLToPath } from "node:url";

// Campos que la API pública acepta en el body de un workflow.
const ALLOWED = ["name", "nodes", "connections", "settings", "staticData"];

// ── Red de seguridad: IDs de PRODUCCIÓN que jamás se tocan por error. ──
// El nombre del workflow NO distingue prod de dev (ambos "TOOLS MOTOR DE RESERVAS");
// el ID sí. Por eso el guard es por ID. Escribir sobre uno de estos exige el flag
// explícito --allow-prod (que nunca deberías necesitar desde este repo).
export const PROD_WORKFLOW_IDS = new Set([
  "nzjWscGj9DoXKIzG", // Motor PROD
]);

/** ¿Se permite desplegar a este id? Puro (testeable). */
export function deployGuard(id, { allowProd = false } = {}) {
  if (PROD_WORKFLOW_IDS.has(id) && !allowProd) {
    return {
      allowed: false,
      reason: `id de PRODUCCIÓN ${id} — BLOQUEADO. Si es a propósito (no debería), usa --allow-prod.`,
    };
  }
  return { allowed: true, reason: "" };
}

/**
 * Construye el payload que acepta la REST API a partir del JSON exportado.
 * Pura y testeable (sin red). Devuelve { id, payload }.
 * `minimalSettings` reduce settings a lo mínimo por si la instancia rechaza
 * claves nuevas (availableInMCP, timeSavedMode...).
 */
export function buildDeployPayload(wf, { minimalSettings = false } = {}) {
  const id = wf.id;
  const payload = {};
  for (const k of ALLOWED) {
    if (wf[k] === undefined) continue;
    payload[k] = wf[k];
  }
  // pinData es data de TEST: no debe ir a la instancia desplegada.
  // (no está en ALLOWED, así que ya queda fuera; explícito por claridad)
  delete payload.pinData;

  if (payload.settings && minimalSettings) {
    const s = payload.settings;
    payload.settings = {
      ...(s.executionOrder ? { executionOrder: s.executionOrder } : {}),
      ...(s.errorWorkflow ? { errorWorkflow: s.errorWorkflow } : {}),
      ...(s.callerPolicy ? { callerPolicy: s.callerPolicy } : {}),
    };
  }
  if (!payload.settings) payload.settings = { executionOrder: "v1" };
  return { id, payload };
}

/** Encuentra recursivamente los *.json bajo un directorio. */
function discoverWorkflows(dir) {
  const out = [];
  const walk = (d) => {
    for (const name of readdirSync(d)) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.json$/i.test(name)) out.push(p);
    }
  };
  walk(dir);
  return out;
}

const mask = (s) => (!s ? "(vacío)" : s.length <= 8 ? "***" : s.slice(0, 3) + "…" + s.slice(-2));

async function apiPut(base, key, id, payload) {
  const res = await fetch(`${base}/api/v1/workflows/${id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", "X-N8N-API-KEY": key },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

async function apiActivate(base, key, id) {
  const res = await fetch(`${base}/api/v1/workflows/${id}/activate`, {
    method: "POST",
    headers: { "X-N8N-API-KEY": key },
  });
  return { ok: res.ok, status: res.status };
}

function parseArgs(argv) {
  const a = { live: false, activate: false, minimalSettings: false, allowProd: false, only: null, files: [] };
  for (const x of argv) {
    if (x === "--live") a.live = true;
    else if (x === "--activate") a.activate = true;
    else if (x === "--minimal-settings") a.minimalSettings = true;
    else if (x === "--allow-prod") a.allowProd = true;
    else if (x.startsWith("--only")) a.only = x.includes("=") ? x.split("=")[1] : "__next__";
    else if (a.only === "__next__") a.only = x;
    else if (!x.startsWith("--")) a.files.push(x);
  }
  return a;
}

async function main(argv) {
  const args = parseArgs(argv);
  const base = (process.env.N8N_BASE_URL || "").replace(/\/+$/, "");
  const key = process.env.N8N_API_KEY || "";

  let files = args.files.length ? args.files : discoverWorkflows("workflows");
  if (args.only) files = files.filter((f) => f.toLowerCase().includes(args.only.toLowerCase()));
  if (!files.length) {
    console.error("No hay workflows que desplegar (revisa workflows/ o --only).");
    process.exit(2);
  }

  const modo = args.live ? "LIVE (escribe en n8n)" : "DRY-RUN (no escribe)";
  console.log(`\n▸ Deploy GitHub -> n8n · ${modo}`);
  console.log(`  base: ${base || "(N8N_BASE_URL sin definir)"} · key: ${mask(key)}`);
  console.log(`  workflows: ${files.length}\n`);

  if (args.live && (!base || !key)) {
    console.error("❌ --live requiere N8N_BASE_URL y N8N_API_KEY en el entorno.");
    process.exit(2);
  }

  let fail = 0;
  for (const file of files) {
    let wf;
    try {
      wf = JSON.parse(readFileSync(file, "utf8"));
    } catch (e) {
      console.error(`  ✗ ${file}: JSON inválido (${e.message})`);
      fail++;
      continue;
    }
    const { id, payload } = buildDeployPayload(wf, { minimalSettings: args.minimalSettings });
    const etiqueta = `${basename(file)} (id ${id ?? "—"}, ${payload.nodes?.length ?? 0} nodos)`;

    if (!id) {
      console.error(`  ✗ ${etiqueta}: el JSON no trae id; no puedo actualizar por id.`);
      fail++;
      continue;
    }

    const guard = deployGuard(id, { allowProd: args.allowProd });

    if (!args.live) {
      if (!guard.allowed) {
        console.log(`  ⛔ [dry] BLOQUEADO: ${etiqueta} -> ${guard.reason}`);
      } else {
        console.log(`  • [dry] PUT ${base || "<N8N_BASE_URL>"}/api/v1/workflows/${id}  (${payload.name})  <-  ${etiqueta}`);
      }
      continue;
    }

    // --live: el guard BLOQUEA prod salvo --allow-prod. No se hace el PUT.
    if (!guard.allowed) {
      console.error(`  ⛔ BLOQUEADO: ${etiqueta} -> ${guard.reason}`);
      fail++;
      continue;
    }
    console.log(`  → actualizar ${id} (${payload.name}) en ${base}`);

    const r = await apiPut(base, key, id, payload);
    if (r.ok) {
      console.log(`  ✓ actualizado: ${etiqueta}`);
      if (args.activate) {
        const act = await apiActivate(base, key, id);
        console.log(act.ok ? `    ↳ activado` : `    ↳ ⚠ no se pudo activar (HTTP ${act.status})`);
      }
    } else {
      fail++;
      const hint = r.status === 404 ? " (no existe ese id en la instancia: créalo una vez a mano o revisa el id)"
                 : r.status === 400 ? " (body rechazado: prueba --minimal-settings)"
                 : r.status === 401 ? " (API key inválida)"
                 : "";
      console.error(`  ✗ ${etiqueta}: HTTP ${r.status}${hint}`);
      console.error(`     ${r.text.slice(0, 200)}`);
    }
  }

  if (!args.live) {
    console.log(`\nDry-run OK. Para aplicar: añade --live (y --activate si quieres activarlos).`);
  }
  if (fail) {
    console.error(`\n❌ ${fail} workflow(s) con error.`);
    process.exit(1);
  }
  console.log(`\n✔ Hecho.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2));
}
