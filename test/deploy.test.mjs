import { test } from "node:test";
import assert from "node:assert/strict";
import { buildDeployPayload, deployGuard, PROD_WORKFLOW_IDS } from "../scripts/deploy.mjs";

// Workflow de ejemplo con campos read-only que la API pública NO acepta.
const wf = () => ({
  id: "nzjWscGj9DoXKIzG",
  name: "TOOLS MOTOR DE RESERVAS",
  active: true,
  nodes: [{ name: "n1" }],
  connections: { n1: {} },
  settings: { executionOrder: "v1", availableInMCP: false, timeSavedMode: "fixed", errorWorkflow: "x", callerPolicy: "workflowsFromSameOwner" },
  pinData: { "2. Parsear Meta": [{ json: { from: "34600000001" } }] },
  meta: { instanceId: "abc" },
  versionId: "v-123",
  tags: [{ id: "t", name: "RESERVAS" }],
});

test("deploy: devuelve el id por separado (para la URL), no en el payload", () => {
  const { id, payload } = buildDeployPayload(wf());
  assert.equal(id, "nzjWscGj9DoXKIzG");
  assert.equal(payload.id, undefined);
});

test("deploy: conserva name/nodes/connections/settings", () => {
  const { payload } = buildDeployPayload(wf());
  assert.equal(payload.name, "TOOLS MOTOR DE RESERVAS");
  assert.equal(payload.nodes.length, 1);
  assert.deepEqual(payload.connections, { n1: {} });
  assert.ok(payload.settings);
});

test("deploy: elimina campos read-only (active, tags, pinData, meta, versionId)", () => {
  const { payload } = buildDeployPayload(wf());
  for (const k of ["active", "tags", "pinData", "meta", "versionId"]) {
    assert.equal(payload[k], undefined, `${k} no debería ir en el payload`);
  }
});

test("deploy: --minimal-settings reduce settings a lo aceptado", () => {
  const { payload } = buildDeployPayload(wf(), { minimalSettings: true });
  assert.deepEqual(Object.keys(payload.settings).sort(), ["callerPolicy", "errorWorkflow", "executionOrder"]);
  assert.equal(payload.settings.availableInMCP, undefined);
});

test("deploy: si no hay settings, pone uno por defecto", () => {
  const w = wf();
  delete w.settings;
  const { payload } = buildDeployPayload(w);
  assert.deepEqual(payload.settings, { executionOrder: "v1" });
});

// ===== Red de seguridad: guard anti-producción (TAREA 5) =====

test("guard deploy: BLOQUEA el id de PROD sin --allow-prod", () => {
  const g = deployGuard("nzjWscGj9DoXKIzG");
  assert.equal(g.allowed, false, "el Motor PROD debe quedar bloqueado por defecto");
  assert.match(g.reason, /PRODUCC/i);
});

test("guard deploy: PERMITE el id de PROD solo con --allow-prod explícito", () => {
  const g = deployGuard("nzjWscGj9DoXKIzG", { allowProd: true });
  assert.equal(g.allowed, true);
});

test("guard deploy: PERMITE el Motor DEV (6Ugau) siempre", () => {
  assert.equal(deployGuard("6UgauiTycOIrC7ES").allowed, true);
  assert.equal(deployGuard("6UgauiTycOIrC7ES", { allowProd: false }).allowed, true);
});

test("guard deploy: el id de PROD está en la lista negra", () => {
  assert.ok(PROD_WORKFLOW_IDS.has("nzjWscGj9DoXKIzG"));
  assert.ok(!PROD_WORKFLOW_IDS.has("6UgauiTycOIrC7ES"));
});
