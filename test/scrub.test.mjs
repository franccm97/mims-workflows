import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { scrubObject } from "../scripts/scrub.mjs";
import { scanText } from "../scripts/check-secrets.mjs";

const fixturePath = fileURLToPath(
  new URL("./fixtures/ejemplo-export.json", import.meta.url),
);
const loadFixture = () => JSON.parse(readFileSync(fixturePath, "utf8"));

// Helpers para encontrar headers por nodo.
const headers = (wf, nodeName) =>
  wf.nodes.find((n) => n.name === nodeName).parameters.headerParameters.parameters;
const headerVal = (wf, nodeName, headerName) =>
  headers(wf, nodeName).find((h) => h.name === headerName).value;

test("scrub: reemplaza el token de Chatwoot por el placeholder de env var", () => {
  const wf = loadFixture();
  const { stats } = scrubObject(wf);
  assert.equal(
    headerVal(wf, "HTTP Request", "api_access_token"),
    "={{ $env.CHATWOOT_API_TOKEN }}",
  );
  assert.equal(stats.CHATWOOT_API_TOKEN, 1, "debe contar 1 reemplazo");
});

test("scrub: NO toca otras cabeceras (Content-Type)", () => {
  const wf = loadFixture();
  scrubObject(wf);
  assert.equal(headerVal(wf, "HTTP Request", "Content-Type"), "application/json");
});

test("scrub: NO toca las REFERENCIAS a credenciales de n8n (id/name)", () => {
  const wf = loadFixture();
  scrubObject(wf);
  const pg = wf.nodes.find((n) => n.name === "Postgres").credentials.postgres;
  assert.deepEqual(pg, { id: "fakeCredId000", name: "Postgres demo" });
});

test("scrub: idempotente — un valor ya en placeholder se queda igual", () => {
  const wf = loadFixture();
  scrubObject(wf);
  assert.equal(
    headerVal(wf, "HTTP Request (ya limpio)", "api_access_token"),
    "={{ $env.CHATWOOT_API_TOKEN }}",
  );
});

test("guard: scanText DETECTA un token con pinta real", () => {
  // Token de pinta realista (estilo Chatwoot, 24 chars). Vive en test/ (no se
  // escanea en el pre-commit), así que no rompe el commit de este propio test.
  const sample = '{ "name": "api_access_token", "value": "FAKEtoken0123456789ABCDE" }';
  const hits = scanText(sample);
  assert.ok(hits.length > 0, "debería detectar el token");
});

test("guard: scanText NO marca el JSON ya limpio (placeholders)", () => {
  const wf = loadFixture();
  scrubObject(wf);
  const hits = scanText(JSON.stringify(wf, null, 2));
  assert.equal(hits.length, 0, `no debería marcar nada limpio, marcó: ${JSON.stringify(hits)}`);
});

test("guard: scanText NO marca referencias de credenciales ni uuids", () => {
  const cred = '"credentials": { "postgres": { "id": "fakeCredId000", "name": "Postgres demo" } }';
  assert.equal(scanText(cred).length, 0);
});

test("guard: scanText NO marca nombres de modelo ni placeholders (header value)", () => {
  // Falsos positivos reales de los flujos: nombre de modelo y placeholder de
  // dropdown. Son >20 chars pero NO son tokens (slug minúscula / SCREAMING_CASE).
  const modelo = '{ "name": "model", "value": "whisper-large-v3-turbo" }';
  const dropdown = '{ "name": "value", "value": "SELECCIONAR_EN_DROPDOWN" }';
  assert.equal(scanText(modelo).length, 0, "no debería marcar el nombre de modelo");
  assert.equal(scanText(dropdown).length, 0, "no debería marcar el placeholder");
});

test("guard: scanText SÍ marca un token con mezcla mayús+minús+dígito", () => {
  // Forma de un token de Chatwoot (mezcla de clases) -> debe seguir saltando.
  const tok = '{ "name": "api_access_token", "value": "FAKEtoken0123456789ABCDE" }';
  assert.ok(scanText(tok).length > 0, "debería seguir detectando el token real");
});
