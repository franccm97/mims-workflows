// scripts/migrate.mjs — runner de migraciones de schema (Node + pg).
//
//   node scripts/migrate.mjs            # aplica las migraciones pendientes
//   node scripts/migrate.mjs --dry-run  # lista qué aplicaría, NO ejecuta
//
// Config por entorno (NUNCA hardcodeada; ver .env.example):
//   DATABASE_URL   p.ej. postgresql://localhost:5432/mims_dev
//
// Cómo funciona:
//   - Crea la tabla schema_migrations si no existe.
//   - Lista migrations/*.sql en orden (prefijo numerico zero-pad -> orden lexicografico).
//   - Aplica SOLO las que NO estan registradas, EN ORDEN, cada una en su PROPIA
//     transaccion, y la registra. Si una falla -> ROLLBACK de esa y para.
//   - Idempotente: re-ejecutar solo aplica lo pendiente.
//
// Requiere la dependencia `pg` (npm install). Se importa de forma DINAMICA, asi
// los tests de las funciones puras NO necesitan pg instalado.

import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = join(HERE, "..", "migrations");
const MIGRATION_RE = /^\d{3,}_.+\.sql$/i;

const CREATE_TABLE_SQL = `
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  version    text PRIMARY KEY,
  applied_at timestamptz DEFAULT now()
);`;

/** Lista los ficheros de migracion validos, ordenados. Puro (testeable). */
export function listMigrationFiles(dir = MIGRATIONS_DIR) {
  return readdirSync(dir)
    .filter((f) => MIGRATION_RE.test(f))
    .sort();
}

/** Dado todos los ficheros y las versiones ya aplicadas, devuelve las pendientes
 *  EN ORDEN. Puro (testeable, sin DB). */
export function computePending(files, appliedVersions) {
  const applied = new Set(appliedVersions);
  return files.filter((f) => !applied.has(f));
}

async function getClient(url) {
  const pg = (await import("pg")).default; // dinamico: tests no necesitan pg
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  return client;
}

async function main(argv) {
  const dryRun = argv.includes("--dry-run");
  const url = process.env.DATABASE_URL;
  const files = listMigrationFiles();

  if (!files.length) {
    console.log("No hay migraciones en migrations/.");
    return;
  }
  if (!url) {
    console.error("❌ DATABASE_URL no definida. Expórtala (nunca la hardcodees).");
    process.exit(2);
  }

  let client;
  try {
    client = await getClient(url);
  } catch (e) {
    console.error(`❌ No pude conectar a la DB: ${e.message}`);
    console.error("   (¿corriste 'npm install' para tener pg? ¿DATABASE_URL correcta?)");
    process.exit(2);
  }

  try {
    await client.query(CREATE_TABLE_SQL);
    const { rows } = await client.query("SELECT version FROM public.schema_migrations");
    const applied = rows.map((r) => r.version);
    const pending = computePending(files, applied);

    console.log(`\n▸ migrate · ${dryRun ? "DRY-RUN (no aplica)" : "APLICAR"}`);
    console.log(`  total: ${files.length} · aplicadas: ${applied.length} · pendientes: ${pending.length}\n`);

    if (!pending.length) {
      console.log("✔ Nada pendiente. DB al día.");
      return;
    }
    if (dryRun) {
      for (const f of pending) console.log(`  • [dry] aplicaría ${f}`);
      console.log(`\nDry-run OK. Sin --dry-run las aplica en orden.`);
      return;
    }

    for (const f of pending) {
      const sql = readFileSync(join(MIGRATIONS_DIR, f), "utf8");
      try {
        await client.query("BEGIN");
        await client.query(sql);
        await client.query("INSERT INTO public.schema_migrations (version) VALUES ($1)", [f]);
        await client.query("COMMIT");
        console.log(`  ✓ aplicada ${f}`);
      } catch (e) {
        await client.query("ROLLBACK");
        console.error(`  ✗ fallo en ${f}: ${e.message}`);
        console.error("    (rollback de esta migración; las anteriores quedan aplicadas. Arregla y reintenta.)");
        process.exitCode = 1;
        return; // el finally cierra la conexión
      }
    }
    console.log(`\n✔ Hecho. ${pending.length} migración(es) aplicada(s).`);
  } finally {
    if (client) await client.end();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2));
}
