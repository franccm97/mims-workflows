# Migraciones de schema

Evolución del schema **versionada en git**. Cada cambio de estructura es un fichero
SQL numerado en `migrations/`. El runner aplica solo lo pendiente, en orden, y lleva
el registro en la tabla `schema_migrations`.

> Regla de oro: el schema NUNCA se cambia a mano en la DB. Se cambia con una
> migración nueva → así dev, staging y prod convergen y no hay drift.

## Cómo correr el runner

```bash
# 1) Instala dependencias (el runner usa 'pg'):
npm install

# 2) Apunta a tu DB por entorno (NUNCA hardcodees la URL):
export DATABASE_URL='postgresql://localhost:5432/mims_dev'
#    (si tu Postgres pide login, antepón 'usuario:contraseña@' al host)

# 3) Mira qué aplicaría, sin tocar nada:
npm run migrate -- --dry-run

# 4) Aplica las pendientes:
npm run migrate
```

⚠️ Empieza SIEMPRE contra `mims_dev`. Nunca contra prod sin haberlo probado antes.

## Qué hace el runner (`scripts/migrate.mjs`)

- Crea `schema_migrations (version text PK, applied_at timestamptz)` si no existe.
- Lista `migrations/*.sql` en orden (prefijo numérico zero-pad → orden lexicográfico).
- Aplica SOLO las que no estén en `schema_migrations`, **en orden**, cada una en su
  **propia transacción**, y registra la versión (= nombre del fichero).
- Si una falla → `ROLLBACK` de esa migración y para (las anteriores quedan aplicadas).
- Idempotente: re-ejecutar solo aplica lo pendiente. `--dry-run` lista sin ejecutar.

## Cómo crear una migración nueva

1. Crea `migrations/NNN_descripcion.sql` con el **siguiente** número (zero-pad de 3:
   `003_...`, `004_...`). El orden lo da el nombre, así que respeta la numeración.
2. Escríbela **idempotente y no destructiva**:
   - `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`,
     `ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION/TRIGGER`.
   - Para constraints: `DROP CONSTRAINT IF EXISTS x;` + `ADD CONSTRAINT x ...`.
   - NUNCA `DROP TABLE` / `DELETE` de datos en una migración de estructura.
3. **Transaction-safe:** el runner envuelve cada fichero en `BEGIN/COMMIT`. Evita
   sentencias que no pueden ir en transacción (`CREATE DATABASE`,
   `CREATE INDEX CONCURRENTLY`, `VACUUM`). Si necesitas una, márcalo y córrela aparte.
4. Pruébala: `npm run migrate -- --dry-run` y luego `npm run migrate` contra `mims_dev`.
5. Commit del fichero. Una vez aplicada en algún entorno, **no la edites**: crea otra
   migración para corregir (editar una ya aplicada genera divergencia).

## Relación con los otros scripts de DB

- `migrations/` = fuente de verdad de la **estructura** (forward-only, versionada).
- `db/schema.prod.sql` = snapshot plano del schema (referencia / vendored).
  `001_init.sql` es ese snapshot adaptado a migración (sin DROPs, idempotente) +
  `agente_activo`.
- `scripts/setup-dev-db.sql` + `db/seed-dev.sql` = atajo para levantar una `mims_dev`
  fresca con datos sintéticos. Para una DB ya creada, evoluciona con `migrate`.

## Migraciones actuales

| Versión | Qué |
|---|---|
| `001_init.sql` | Baseline: schema de prod completo (idempotente) + `negocios.agente_activo` |
| `002_config_vertical.sql` | `negocios.capacidad_simultanea` (def 1) + `negocios.corte_franja` (def 14) |
| `003_profesionales_seed_estetica.sql` | Seed sintético Clínica Estética Aura: 5 servicios, 3 profesionales, `profesional_servicios` y 2 reservas con `profesional_id` (banco de pruebas del modo profesional) |
| `004_seed_verticales_dev.sql` | Seed por vertical (restaurante/peluquería/clínica/fisio/taller/gimnasio/pádel) con palancas (`capacidad_simultanea`/`corte_franja`) + servicios + profesionales/pistas + reservas. Ids `a0000000-…`, idempotente |
| `005_verticales_prompts.sql` | Tabla `verticales` con plantillas de prompt (cliente+empresario) por vertical (8), marcadores `{NOMBRE_NEGOCIO}/{SERVICIOS}/{PROFESIONALES}/{HORARIO}`. Idempotente (ON CONFLICT DO UPDATE). Ver `docs/prompt-dinamico.md` |
