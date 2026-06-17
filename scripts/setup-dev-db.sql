-- scripts/setup-dev-db.sql
-- Crea/reinicia la DB de DESARROLLO `mims_dev`, le aplica SOLO el schema de
-- producción (estructura, cero datos) y la siembra con negocios sintéticos.
--
-- ⚠️ DEV, NO PRODUCCIÓN. Esto BORRA y recrea la DB `mims_dev`. No la apuntes a la
--    DB de prod (mims_app). Crea una instancia/credencial de Postgres aparte.
--
-- Cómo correrlo (lo haces TÚ, tras revisarlo; el asistente NO ejecuta nada de DB):
--
--   # desde la RAÍZ del repo, contra tu Postgres local de dev:
--   psql -h localhost -U postgres -f scripts/setup-dev-db.sql
--
-- Usa rutas relativas al propio script (\ir), así no importa el cwd.
-- Requiere permisos para CREATE DATABASE.

\set ON_ERROR_STOP on

\echo '>> Recreando DB mims_dev (DEV, no prod)...'
DROP DATABASE IF EXISTS mims_dev WITH (FORCE);
CREATE DATABASE mims_dev;

-- Conecta a la DB recién creada (el resto corre dentro de mims_dev).
\c mims_dev

\echo '>> Aplicando schema de prod (solo estructura, cero datos)...'
\ir ../db/schema.prod.sql

\echo '>> Sembrando negocios sinteticos (restaurante / clinica / peluqueria)...'
\ir ../db/seed-dev.sql

\echo '>> Listo. DB mims_dev creada, schema aplicado y datos sinteticos sembrados.'
