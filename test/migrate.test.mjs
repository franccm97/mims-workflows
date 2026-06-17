import { test } from "node:test";
import assert from "node:assert/strict";
import { computePending, listMigrationFiles } from "../scripts/migrate.mjs";

// Solo funciones PURAS (sin pg / sin DB), para que el CI no necesite pg instalado.

test("migrate: computePending devuelve solo lo no aplicado, en orden", () => {
  const files = ["001_init.sql", "002_config_vertical.sql", "003_x.sql"];
  assert.deepEqual(computePending(files, ["001_init.sql"]), [
    "002_config_vertical.sql",
    "003_x.sql",
  ]);
  assert.deepEqual(computePending(files, files), []);
  assert.deepEqual(computePending(files, []), files);
});

test("migrate: idempotencia — si todo está aplicado, no queda nada pendiente", () => {
  const files = ["001_init.sql", "002_config_vertical.sql"];
  assert.deepEqual(computePending(files, ["002_config_vertical.sql", "001_init.sql"]), []);
});

test("migrate: listMigrationFiles lee las migraciones reales y van en orden", () => {
  const files = listMigrationFiles();
  assert.ok(files.includes("001_init.sql"), "debe estar 001_init.sql");
  assert.ok(files.includes("002_config_vertical.sql"), "debe estar 002_config_vertical.sql");
  assert.deepEqual(files, [...files].sort(), "orden lexicográfico = orden numérico");
});
