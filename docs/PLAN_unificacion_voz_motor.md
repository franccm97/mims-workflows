# PLAN — Unificar el flujo de voz (WF3 Retell) con el Motor (6Ugau)

> Voz = **adaptador de canal**; Motor = **lógica única**. Arquitectura decidida con Franc.
> ✅ **JSON de WF3 recibido** (id `tUL0VRQKeGBA2Acj`). El refactor YA está construido en
> `workflows/voz/voz.json` (rama `feat/voz-motor-unificado`).
> **NO publicado, NO deploy, NO merge.** Prueba real = **Retell Test Call** (no necesita
> Telnyx) cuando Franc lo importe a DEV.

---

## 0. Contexto (confirmado del JSON)

- **Voz = WF3 `AGENTE-LLAMADA-RESERVAS-DEV` (id `tUL0VRQKeGBA2Acj`)**, cred `DB DEV`.
- **Identificación de negocio (resuelve el [VERIFICAR-JSON] anterior):** voz NO usa
  `account_id` de Chatwoot. Usa **`call.agent_id` → mapa `AGENTES`** en el parser (nodo 2):

  | agent_id (Retell) | negocio_id | negocio |
  |---|---|---|
  | `agent_5efa5c46…` | `11111111-…-1111` | Centre Mèdic |
  | `agent_4cfc376e…` | `22222222-…-2222` | Dentos |
  | `agent_cbd6d8af…` | `b4ac5f7a-e99a-4db8-8336-aef5ea4bfbf5` | Peluquería Canina |
  | `agent_0eea5949…` | `8d0ce837-…-d7d680` | **La Tasqueta (PROD)** |

- **Retell es un agente LLM de voz**: llama estas funciones como *custom functions* y
  habla a partir del `{response}` que devuelve n8n (como Gemini en WhatsApp).

---

## 1. Diff EXACTO: voz (4a–4d) vs Motor (6Ugau)

| Pieza | Voz WF3 (confirmado del JSON) | Motor 6Ugau (confirmado) |
|---|---|---|
| **parser/resolverFecha** (nodo 2) | **MULTILINGÜE ES/CA/EN/FR** (avui/demà, today/tomorrow, demain) + relativas + día del mes. **Más idiomas que el Motor.** | `1. Resolver fecha`: **solo ES**, + propaga `profesional`/`accion` |
| **huecos** (4a-1/4a-2) | `similarity()` (pg_trgm) + unaccent para el servicio · **mono** (cualquier solape = ocupado) · ofrece 2 huecos · frase natural ("las 9 o las 9 y media") | `3a`+`3a-2`: **capacidad_simultanea**, **corte franja restaurante (18h)**, descarta horas pasadas, **modo profesional** |
| **crear** (4b) | **mono** (cualquier confirmado que solape → OCUPADO) · **sin HORA_PASADA** · **sin FALTA_NOMBRE** · `similarity()` servicio | `3b`: capacidad/multireserva · **HORA_PASADA** · **FALTA_NOMBRE** · profesional (`profesional_id`) · notifica al dueño |
| **cancelar** (4c) | match por **`cliente_nombre`** (unaccent + similarity) · **SIN gate de actor** (no comprueba teléfono) · 2 pasos | `3c`: **gate de actor** (dueño cualquiera / cliente solo las suyas por teléfono) · unaccent · 2 pasos |
| **modificar** (4d) | match por nombre (unaccent+similarity) · mono · **sin gate de actor** | `3e`: solape destino · (gate por teléfono) · conserva `profesional_id` |
| **router** (nodo 3) | Switch por `fn` en el propio WF3 | el Motor enruta por `fn` internamente → router de voz **sobra** |

**Hallazgos nuevos del JSON (importantes):**
- 🟢 **Voz tiene `similarity()` (pg_trgm) fuzzy** para servicio y nombre; **el Motor NO**
  (solo `unaccent ILIKE`). Al unificar, voz **pierde** ese match difuso → o se acepta el
  match más estricto, o se añade `similarity()` al Motor. **Decidir.**
- 🟢 **El resolverFecha de voz es MÁS multilingüe** que el del Motor → por eso **se queda
  en el parser** (corrige el plan v1: NO se elimina). Voz resuelve a ISO y el Motor
  re-resuelve ISO (idempotente) → voz conserva su ventaja CA/EN/FR.
- 🔴 **cancelar/modificar de voz NO tienen gate de actor.** El Motor SÍ (por teléfono).
  Al unificar, el `from_number` de voz = `call.from_number` del que llama. Cambia el
  comportamiento: un cliente solo podrá cancelar/mover **sus** reservas (las que tengan su
  teléfono). Reservas con teléfono distinto o sin teléfono → ya no cancelables por voz como
  "cliente". **Regresión obligatoria** (sección 5).

---

## 2. Qué se ELIMINA (hecho en voz.json)

- Nodo **3. Router** (el Motor enruta por `fn`).
- **4a-1/4a-2** (cargar datos + huecos propios), **4b** (crear), **4c** (cancelar),
  **4d** (modificar) — todo el SQL duplicado de voz, **y 4c Fallback**.
- **NO se elimina el `resolverFecha`** del parser (nodo 2) — es del adaptador de canal y
  es multilingüe (ver §1). El SQL propio sí desaparece.

## 3. Qué GANA voz al usar el Motor

Capacidad/multireserva · corte de franja restaurante (Tasqueta) · HORA_PASADA · FALTA_NOMBRE
· profesionales con agenda · **gate de actor** (seguridad: hoy voz cancela por nombre sin
verificar quién llama) · fechas robustas del Motor · toggle_bot · una sola fuente de verdad.

## 4. Arquitectura construida (`workflows/voz/voz.json`)

```
1. Webhook Retell
   → 2. Parsear funcion Retell   (adaptador: agent_id→negocio_id · resolverFecha ML · fnMap;
                                   + profesional/accion/fecha_hasta vacíos)
   → Motor (Execute Workflow → 6UgauiTycOIrC7ES, mapea los 14 inputs del Trigger)
   → Limpieza TTS                (quita prefijos OCUPADO:/CONFIRMAR:/…, markdown *, emojis,
                                   y la "h" de 09:00h → 09:00)
   → 5. Responder a Retell       ({ response })
```

## 5. Riesgos + regresión (CRÍTICO — 4 agentes comparten el flujo)

Agentes: **Centre Mèdic, Dentos, Peluquería Canina, La Tasqueta (= PROD)**. Tocar WF3 los
afecta a los 4. La regresión va en **DEV (DB DEV)**, NUNCA prod.

- **Tasqueta = PROD restaurante** (negocio `8d0ce837`): la capacidad (cap 10) y el corte
  18h del Motor deben igualar/mejorar el comportamiento de voz, sin romper. En DEV la DB
  DEV debe tener ese negocio configurado (capacidad/corte) para probarlo.
- **Gate de actor (cambio de comportamiento):** cancelar/mover por voz ahora exige que el
  teléfono del que llama coincida (cliente). Probar: reserva hecha por voz desde el mismo
  número → cancelable; reserva sin teléfono / otro número → ya no (esperado, pero validar
  que no rompe casos reales).
- **`similarity()` perdido:** servicios/nombres con typo que antes casaban por trigram
  ahora dependen de `unaccent ILIKE`. Probar nombres de servicio aproximados.
- **TTS verbatim vs interpretado [VERIFICAR Test Call]:** ¿Retell habla el `response`
  casi literal (entonces la Limpieza TTS es esencial y quizá hace falta frase más directa)
  o su LLM lo reformula (entonces los prefijos son señal útil)? El antiguo WF3 devolvía
  texto directo ("Perfecto Ana…"); el Motor devuelve texto orientado a agente
  ("CONFIRMAR: … Pide confirmación al usuario"). La Limpieza TTS mitiga; el Test Call lo
  confirma.
- **Doble resolverFecha** (voz + Motor): idempotente para ISO; sin riesgo, redundancia menor.

Regresión por agente (en DEV, vía Retell Test Call): reservar · consultar huecos ·
cancelar (con nombre acentuado) · modificar · restaurante cap/franja (Tasqueta) · fecha
relativa multilingüe · fallo seguro (hora pasada, sin nombre) · TTS suena natural ·
aislamiento (cada agente solo su negocio).

## 6. Trigger del Motor (verificado)

- `Trigger (desde agente)` = **`executeWorkflowTrigger`** → llamable por **Execute Workflow**.
- **14 inputs declarados:** fn, negocio_id, servicio, fecha, hora, nombre, confirmar,
  from_number, fecha_nueva, hora_nueva, servicio_nuevo, fecha_hasta, profesional, accion.
  → el nodo Motor (Execute Workflow) de voz.json mapea los 14 desde `$json`.
- **`response`** sale por `N3 Salida` (Set) y por todas las ramas terminales (3a-2/3d/3f/3g)
  → la Limpieza TTS lee `$json.response`.
- ⚠️ **[VERIFICAR en n8n/Test Call]:** que el mapeo de inputs del Execute Workflow llega
  bien al Trigger (lo modelé sobre el patrón toolWorkflow ya probado contra 6Ugau). Si n8n
  lo pasa distinto, ajustar `workflowInputs` del nodo Motor.

## 7. QA L3 (puente voz→Motor)

`mims-qa` → `src/drivers/retell.ts` (`intentAMotor`) + `scenarios/l3/` testean el contrato
voz→Motor a nivel DB (determinista, mismo Motor que WhatsApp). Avanza junto al refactor.

## 8. Bloqueante y ejecución

- **Prueba real = Retell Test Call en DEV** (Franc; no necesita Telnyx). Importar voz.json
  a DEV, Test Call por cada agente, regresión §5.
- Telnyx solo hace falta para llamadas telefónicas reales (fase posterior).
- Trabajar en rama + DEV. **NO publicar voz, NO deploy/merge sin OK.** Motor PROD
  `nzjWscGj9DoXKIzG` intocable (guard anti-prod activo).

## 9. TODO / decisiones para Franc
- [ ] Test Call DEV de los 4 agentes (regresión §5) → confirmar TTS + Execute Workflow.
- [ ] Decidir: ¿añadir `similarity()` al Motor (no perder fuzzy de voz) o aceptar `unaccent`?
- [ ] Confirmar el cambio del gate de actor en cancelar/mover por voz.
- [ ] DB DEV con los 4 negocios configurados (capacidad/corte/servicios) para la regresión.
