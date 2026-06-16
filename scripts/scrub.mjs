// scrub.mjs — limpia secretos hardcodeados de un workflow exportado de n8n.
//
//   node scripts/scrub.mjs <entrada.json> [salida.json]
//
// n8n exporta los flujos con algunos secretos EN CLARO dentro del JSON: el más
// importante es el token del Agent Bot de Chatwoot, pegado en el header
// `api_access_token` de los nodos HTTP Request. Este script lo reemplaza por un
// placeholder de variable de entorno (={{ $env.NOMBRE }}) ANTES de commitear.
//
// NO toca las REFERENCIAS a credenciales de n8n (Postgres/Groq/Gemini): esas son
// solo {"id","name"} y NO contienen el valor del secreto -> son seguras.
//
// El JSON limpio es la PLANTILLA / fuente de verdad del repo. Para que funcione
// re-importado a n8n, la env var tiene que existir en la instancia (Hetzner):
// eso es el paso 2-B (deploy), no este script.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// ── Reglas: header (en nodos HTTP) -> nombre de la env var. Ampliable. ──
export const RULES = [
  { header: "api_access_token", env: "CHATWOOT_API_TOKEN" },
  // Añade aquí futuros headers con token hardcodeado, p.ej.:
  // { header: "x-api-key", env: "ALGUN_API_KEY" },
];

const isPlaceholder = (v) => typeof v === "string" && v.trim().startsWith("={{");

/**
 * Recorre el objeto y reemplaza, en pares {name, value} cuyo `name` casa una
 * regla, el `value` hardcodeado por el placeholder de env var. Muta `obj`.
 * Devuelve stats { ENV_VAR: nº_reemplazos } y warnings (valores sospechosos
 * en headers sin regla -> NO se tocan, solo se avisan).
 */
export function scrubObject(obj, rules = RULES) {
  const stats = {};
  const warnings = [];
  const byHeader = new Map(rules.map((r) => [r.header.toLowerCase(), r]));

  const walk = (node) => {
    if (Array.isArray(node)) {
      node.forEach(walk);
      return;
    }
    if (node && typeof node === "object") {
      if (typeof node.name === "string" && "value" in node) {
        const rule = byHeader.get(node.name.toLowerCase());
        if (rule) {
          const ph = `={{ $env.${rule.env} }}`;
          if (typeof node.value === "string" && !isPlaceholder(node.value)) {
            node.value = ph;
            stats[rule.env] = (stats[rule.env] ?? 0) + 1;
          }
        } else if (
          typeof node.value === "string" &&
          !isPlaceholder(node.value) &&
          /^[A-Za-z0-9+/_=-]{20,}$/.test(node.value)
        ) {
          // Header con pinta de token pero sin regla -> avisar (no tocar).
          warnings.push(node.name);
        }
      }
      for (const k of Object.keys(node)) walk(node[k]);
    }
  };

  walk(obj);
  return { stats, warnings };
}

function defaultOut(inPath) {
  if (/\.raw\.json$/i.test(inPath)) return inPath.replace(/\.raw\.json$/i, ".json");
  if (/\.json$/i.test(inPath)) return inPath.replace(/\.json$/i, ".clean.json");
  return inPath + ".clean.json";
}

function main(argv) {
  const inPath = argv[0];
  if (!inPath) {
    console.error("uso: node scripts/scrub.mjs <entrada.json> [salida.json]");
    process.exit(2);
  }
  const outPath = argv[1] ?? defaultOut(inPath);
  let data;
  try {
    data = JSON.parse(readFileSync(inPath, "utf8"));
  } catch (e) {
    console.error(`No pude leer/parsear ${inPath}: ${e.message}`);
    process.exit(2);
  }

  const { stats, warnings } = scrubObject(data);
  writeFileSync(outPath, JSON.stringify(data, null, 2) + "\n", "utf8");

  const total = Object.values(stats).reduce((a, b) => a + b, 0);
  console.log(`✔ scrub: ${inPath} -> ${outPath}`);
  if (total === 0) {
    console.log("  (sin secretos hardcodeados que limpiar)");
  } else {
    for (const [env, n] of Object.entries(stats)) {
      console.log(`  ${n}× -> ={{ $env.${env} }}`);
    }
  }
  if (warnings.length) {
    const uniq = [...new Set(warnings)];
    console.log(
      `  ⚠ headers con pinta de token y SIN regla (revisa manualmente): ${uniq.join(", ")}`,
    );
    console.log("    añade una regla en RULES si son secretos.");
  }
}

// Ejecuta el CLI solo si se invoca directamente (no al importar en tests).
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2));
}
