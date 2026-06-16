// check-secrets.mjs — guard anti-secretos. Escanea texto en busca de tokens y,
// como hook de pre-commit (--staged), BLOQUEA el commit si encuentra alguno.
//
//   node scripts/check-secrets.mjs --staged   # escanea lo que está en el stage
//   node scripts/check-secrets.mjs <archivo>  # escanea un archivo suelto
//
// Es heurístico (regex), 2ª capa por si un secreto se cuela pese al scrub. Cero
// dependencias externas. Si da un falso positivo legítimo, ajusta las reglas o
// usa el placeholder ={{ $env.* }}.

import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PLACEHOLDER = /^=?\{\{/; // ={{ $env... }} o {{ ... }}

// Para `http_header_token` (regex amplio sobre cualquier "value"): exige que el
// valor PAREZCA un token real, no un slug/identificador legítimo de n8n. Evita
// falsos positivos como nombres de modelo ("whisper-large-v3-turbo") o
// placeholders en mayúsculas ("SELECCIONAR_EN_DROPDOWN"), sin perder el token de
// Chatwoot (mezcla mayús+minús+dígito) ni claves base64/largas.
const looksLikeToken = (s) => {
  if (/[+/=]/.test(s)) return true; // base64-ish (chars que no salen en slugs)
  if (s.length >= 32) return true; // opaco y largo
  return /[a-z]/.test(s) && /[A-Z]/.test(s) && /\d/.test(s); // alfanum mezclado
};

const RULES = [
  {
    id: "meta_token",
    desc: "token permanente de Meta (EAA...)",
    re: /\bEAA[0-9A-Za-z_-]{20,}/g,
  },
  {
    id: "pg_url_password",
    desc: "connection string de Postgres con contraseña",
    re: /\bpostgres(?:ql)?:\/\/[^\s:'"]+:[^\s@'"]+@/gi,
  },
  {
    id: "labeled_secret",
    desc: "clave token/secret/password con valor en claro",
    re: /"(?:[a-zA-Z_]*(?:token|secret|password|passwd|apikey|api_key))"\s*:\s*"([^"]{8,})"/gi,
    group: 1,
  },
  {
    id: "http_header_token",
    desc: "valor de header HTTP con pinta de token",
    re: /"value"\s*:\s*"([A-Za-z0-9+/_=-]{20,})"/g,
    group: 1,
  },
];

const mask = (s) => (s.length <= 8 ? "***" : s.slice(0, 4) + "…" + s.slice(-2));

/** Devuelve [{rule, desc, sample}] de los secretos encontrados en `text`. */
export function scanText(text) {
  const hits = [];
  const seen = new Set();
  for (const rule of RULES) {
    rule.re.lastIndex = 0;
    let m;
    while ((m = rule.re.exec(text)) !== null) {
      const captured = rule.group ? m[rule.group] : m[0];
      if (!captured) continue;
      if (PLACEHOLDER.test(captured)) continue; // ={{ $env... }} es seguro
      if (UUID.test(captured)) continue; // ids de n8n, no secretos
      if (rule.id === "http_header_token" && !looksLikeToken(captured)) continue; // slug/modelo, no token
      const key = rule.id + ":" + captured;
      if (seen.has(key)) continue;
      seen.add(key);
      hits.push({ rule: rule.id, desc: rule.desc, sample: mask(captured) });
    }
  }
  return hits;
}

// Rutas que NO se escanean (fixtures de test, ejemplos, este propio guard).
const SKIP = [
  /(^|\/)tests?\//,
  /\.example$/,
  /\.example\./,
  /(^|\/)\.env\.example$/,
  /(^|\/)scripts\/check-secrets\.mjs$/,
];
const skip = (f) => SKIP.some((re) => re.test(f));

function stagedFiles() {
  const out = execSync("git diff --cached --name-only --diff-filter=ACM", {
    encoding: "utf8",
  });
  return out.split("\n").map((s) => s.trim()).filter(Boolean);
}

function stagedContent(file) {
  try {
    return execSync(`git show :"${file}"`, { encoding: "utf8" });
  } catch {
    return "";
  }
}

function main(argv) {
  let failed = false;

  if (argv[0] === "--staged") {
    for (const file of stagedFiles()) {
      if (skip(file)) continue;
      const hits = scanText(stagedContent(file));
      if (hits.length) {
        failed = true;
        console.error(`\n  ${file}:`);
        for (const h of hits) console.error(`    • ${h.desc} -> ${h.sample}  [${h.rule}]`);
      }
    }
  } else if (argv[0]) {
    const hits = scanText(readFileSync(argv[0], "utf8"));
    if (hits.length) {
      failed = true;
      for (const h of hits) console.error(`  • ${h.desc} -> ${h.sample}  [${h.rule}]`);
    }
  } else {
    console.error("uso: node scripts/check-secrets.mjs --staged | <archivo>");
    process.exit(2);
  }

  if (failed) {
    console.error(
      "\n❌ Posible secreto detectado. Pasa el JSON por 'npm run scrub' y usa ={{ $env.* }}.",
    );
    process.exit(1);
  }
  console.log("✔ sin secretos detectados");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2));
}
