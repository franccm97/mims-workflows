# PLAN — Unificar el flujo de voz (WF3 Retell) con el Motor (6Ugau)

> **Solo análisis y diseño. NO tocar el flujo de voz. NO refactorizar. NO desplegar.**
> Para tener listo cuando llegue Telnyx.

> ⚠️ **El JSON de WF3 (voz) NO llegó adjunto en el encargo.** Este plan se escribe con
> lo que SÍ consta (Motor 6Ugau ya leído a fondo, `docs/profesionales-motor.md`,
> `capability-map`, los comentarios del propio Motor "mismo motor que voz", y el estado
> conocido: voz separada, mono, sin multireserva, resolverFecha propio "Parche 4
> pendiente"). **Todo lo marcado [VERIFICAR-JSON] hay que confirmarlo contra el WF3 real
> antes de ejecutar** — no se inventa el SQL de los nodos de voz. Pásame el JSON y relleno
> el diff nodo-a-nodo exacto.

---

## 0. Contexto

- **Voz = WF3 (Retell), Telnyx → Retell → n8n.** Tiene **lógica propia** (nodos 4a–4d):
  su parser/`resolverFecha`, y su SQL de crear / cancelar / modificar / huecos.
- **Está SEPARADO del Motor `6UgauiTycOIrC7ES`** (el de WhatsApp, fn-based). Hoy hay
  **doble implementación** de la misma lógica de reservas → divergencia.
- Estado conocido de voz: **mono-recurso, sin multireserva**, sin las mejoras que el Motor
  fue acumulando. `resolverFecha` de voz quedó desfasado ("Parche 4 pendiente").
- **Objetivo de la unificación:** voz deja de tener lógica propia y llama al **mismo
  Motor** que WhatsApp → una sola fuente de verdad, un solo sitio que mantener.
  El puente de contrato ya está esbozado en `mims-qa` → `src/drivers/retell.ts`
  (`intentAMotor`: voz → input fn-based del Motor).

---

## 1. Diff conceptual: lógica de voz (4a–4d) vs Motor (6Ugau)

> Columna "Voz (4a–4d)" = [VERIFICAR-JSON] salvo lo ya documentado. Columna "Motor" =
> confirmado (leído del export DEV de 6Ugau).

| Pieza | Voz (4a–4d) — [VERIFICAR-JSON] | Motor 6Ugau (confirmado) |
|---|---|---|
| **resolverFecha** | Copia propia, desfasada (Parche 4 pendiente). Probable: ISO, dd/mm, hoy/mañana, día de semana | `1. Resolver fecha`: ISO · dd/mm(/yyyy) con roll-over de año · hoy/mañana/pasado mañana · "en N días/semanas" · "semana que viene" · día de semana · **día del mes suelto** ("el 12"). Propaga TODOS los campos (incl. `profesional`, `accion`) |
| **crear** | SQL propio de inserción, mono (1 recurso) | `3b`: capacidad por negocio (`capacidad_simultanea`; restaurante 10), **solape por profesional** si aplica, guarda `profesional_id`, **HORA_PASADA** (rechaza pasado), **FALTA_NOMBRE**, dollar-quoting (apóstrofes), notifica al dueño |
| **cancelar** | SQL propio | `3c`: **gate de actor** (dueño cancela cualquiera, cliente solo las suyas), **`unaccent` en el filtro de nombre**, dos pasos (buscar→confirmar), VARIAS/NO_ENCONTRADA |
| **modificar** | SQL propio (si existe en voz) | `3e`: mover fecha/hora/servicio, solape del destino, confirmar, conserva `profesional_id` |
| **huecos / disponibilidad** | Cálculo propio | `3a`+`3a-2`: franjas del horario, **corte mediodía/noche (18h) restaurante vs mañana/tarde (14h)**, descarta horas pasadas si es hoy, **modo profesional** (huecos por agenda), capacidad |
| **negocio / multi-tenant** | [VERIFICAR-JSON] cómo resuelve el negocio | resuelto por datos; tools leen `negocio_id` |
| **idioma / canal** | Voz: TTS, sin Chatwoot, sin historial textual igual que WhatsApp | WhatsApp: Chatwoot, historial en `historial` |

**Resumen del diff:** voz reimplementa (peor y desfasado) lo que el Motor ya hace bien.
La diferencia legítima es de **canal** (voz↔TTS↔Telnyx/Retell vs WhatsApp↔Chatwoot), NO de
**lógica de reservas** — esa debe ser única (el Motor).

---

## 2. Qué se ELIMINA al unificar

- Los nodos **4a–4d** de WF3 (crear/cancelar/modificar/huecos propios de voz).
- El **`resolverFecha` propio de voz** (se usa el `1. Resolver fecha` del Motor).
- Cualquier SQL de reservas duplicado en WF3.
- → WF3 se queda con: **adaptador de canal** (parsear el payload de voz/Retell → `{fn,
  params}`) + **llamada al Motor** + **render de la respuesta a TTS**. Nada de lógica de DB.

---

## 3. Qué GANA voz al usar el Motor (cosas que hoy le faltan)

- **Capacidad / multireserva:** `capacidad_simultanea` por negocio (restaurante cap 10,
  recurso único = 1). Hoy voz es mono → no soporta solapes legítimos.
- **Corte de franjas restaurante:** mediodía/noche (corte 18h) vs mañana/tarde (14h).
- **`unaccent` en cancelar/mover/agenda:** nombres con acento casan (bug que voz arrastra).
- **Profesionales con agenda propia:** modo profesional por datos (`profesional_servicios`).
- **Gate de actor:** dueño vs cliente (agenda solo dueño; cancelar/mover client-vs-owner).
- **Fechas robustas:** "en N días", "el 12", roll-over de año, anti time-bomb.
- **HORA_PASADA + FALTA_NOMBRE + dollar-quoting (apóstrofes) + NULLIF** (fallo seguro).
- **toggle_bot** (apagar/encender) y, si se monta, **prompt dinámico por vertical**.
- **Una sola fuente de verdad** → arreglar un bug una vez, no dos.

---

## 4. Arquitectura de la unificación (objetivo)

```
Telnyx → Retell → WF3 (voz)
                    │  parsea voz → intención {fn, negocio_id, servicio, fecha, hora,
                    │  nombre, confirmar, profesional, accion}   (adaptador de canal)
                    ▼
            Motor 6UgauiTycOIrC7ES  (mismo que WhatsApp, fn-based)
                    │  SQL determinista contra DB → { response, ... }
                    ▼
            WF3 renderiza `response` a TTS y responde la llamada
```
- El **contrato** voz→Motor es el mismo fn-based de WhatsApp. Puente ya tipado en
  `mims-qa/src/drivers/retell.ts` (`intentAMotor`).
- **Fechas:** voz pasa la fecha "tal cual" (igual que WhatsApp); las resuelve el
  `1. Resolver fecha` del Motor. Se borra el resolver de voz.
- **Diferencias de canal a preservar:** no hay Chatwoot ni `account_id` en voz →
  [VERIFICAR-JSON] cómo se identifica el negocio en una llamada (¿número marcado /
  `phone_number_id`?). El historial conversacional de voz [VERIFICAR-JSON].

---

## 5. Riesgos + regresión (CRÍTICO)

**El flujo de voz es COMPARTIDO por 4 agentes:** Centre Mèdic, Dentos, Peluquería Canina
y **Tasqueta (= PRODUCCIÓN)**. Un cambio en WF3 los toca a los 4 → cualquier unificación
debe pasar **regresión de los 4** antes de prod.

Riesgos:
- **Tasqueta es PROD restaurante** → la capacidad (cap 10) y el corte de franja (18h) del
  Motor deben reproducir o mejorar el comportamiento actual de voz, sin romperlo.
- Verticales distintas (médico/dental/pelu/restaurante) → distinto `capacidad_simultanea`,
  `corte_franja`, profesionales sí/no. Hay que tener cada negocio bien configurado en DB
  ANTES de apuntar su voz al Motor (multi-tenant por datos).
- Identificación de negocio en voz (sin `account_id`) [VERIFICAR-JSON] — punto frágil.
- Render a TTS: el `response` del Motor lleva markdown (`*negritas*`, emojis 🗓️) pensado
  para WhatsApp → **hay que limpiarlo para voz** (TTS no lee asteriscos/emojis).

Qué probar en regresión (por cada uno de los 4 agentes, en DEV):
1. Reservar (happy path) por voz → fila correcta en DB (oráculo).
2. Consultar disponibilidad → huecos coherentes con horario/capacidad del negocio.
3. Cancelar (incl. **nombre con acento** → unaccent) → estado='cancelado'.
4. Modificar/mover → sin duplicar, solape correcto.
5. Restaurante (Tasqueta): cap 10 + franja mediodía/noche → igual o mejor que hoy.
6. Fecha relativa ("mañana", "el viernes", "el 12") → misma fecha que el resolver del Motor.
7. Fallo seguro: hora pasada, sin nombre, servicio inexistente → no crea, responde bien.
8. TTS: la respuesta se oye natural (sin markdown/emojis).
9. **Aislamiento:** cada agente opera SOLO sobre su negocio (no cruza datos).

Red de seguridad: la suite `mims-qa` ya cubre el Motor (L0/L1.5) — esos verbos quedan
verificados a nivel DB. Lo que voz añade es el **adaptador de canal**, que es lo nuevo a
testear (contrato voz→Motor: `intentAMotor`, hoy esqueleto en L3).

---

## 6. Bloqueante y condiciones de ejecución

> **EJECUTAR SOLO cuando Telnyx esté activo, en DEV, con regresión de los 4 agentes.**
> No se puede probar la voz end-to-end sin Telnyx → hasta entonces, esto es solo el plan.

Checklist previo a ejecutar (cuando llegue Telnyx):
- [ ] Telnyx activo y enrutando a Retell→n8n en DEV.
- [ ] Pasar el **JSON real de WF3** → completar el diff nodo-a-nodo [VERIFICAR-JSON].
- [ ] Confirmar cómo identifica voz el negocio (sin `account_id`).
- [ ] Los 4 negocios configurados en DB (capacidad/corte/profesionales/vertical).
- [ ] Adaptador de canal voz→`{fn,params}` (sobre `intentAMotor`) + limpieza markdown→TTS.
- [ ] Trabajar en **rama + DEV**, NUNCA prod directo. Tasqueta es PROD: regresión antes.
- [ ] Regresión de los 4 agentes (sección 5) verde en DEV.
- [ ] Deploy con dry-run + guard anti-prod (el Motor PROD `nzjWscGj9DoXKIzG` sigue intocable).

---

## 7. Pendiente para completar este plan
- **JSON de WF3** (no llegó) → diff exacto de 4a–4d, identificación de negocio en voz,
  historial de voz, forma del payload Retell/Telnyx real.
- Decisión de producto: ¿se unifica del todo, o voz mantiene algún matiz de canal?
