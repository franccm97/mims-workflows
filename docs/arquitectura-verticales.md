# Arquitectura de verticales — modelo de recursos del Motor

Modelo único y escalable para TODAS las verticales de reserva de mims/HeyDiga. Un
solo Motor, parametrizado por **datos en la DB**, cubre restaurante, peluquería,
clínica, taller, gimnasio, pádel, estética y fisio. **Inmobiliaria queda fuera** (es
visitas + leads, no reservas con cupo/agenda — otro modelo).

> Doctrina: **IA para criterio, código para fiabilidad.** Toda validación
> (solapes, capacidad, horario, pasado) vive en SQL determinista, nunca en el prompt.
> **La verdad está en Postgres.** Y la **REGLA DE ORO**: el Motor decide por los
> DATOS del negocio, nunca por flags hardcodeados por negocio. Todo cambio es
> ADITIVO: un negocio que no usa una función se comporta EXACTAMENTE igual que antes.

---

## 1. El modelo: RECURSOS genéricos

Toda reserva ocupa un **recurso** durante una franja `[hora_inicio, hora_fin)`. Un
recurso es cualquier cosa con agenda y un cupo de ocupación simultánea:

| Tipo de recurso | Ejemplos | Cupo simultáneo |
|---|---|---|
| **Persona con agenda** (profesional) | peluquero, doctor, fisio, esteticista | 1 por agenda (cada uno) |
| **Espacio/objeto con cupo** | mesa, pista, bahía de taller, plaza de clase | N (cuántos hay) |

La clave: **un profesional es un recurso con capacidad 1 en SU propia agenda.** Eso
unifica los dos mundos. El Motor solo necesita saber, para el servicio pedido:
1. ¿contra qué agenda(s) compruebo el solape?
2. ¿cuántas reservas simultáneas caben antes de dar "lleno"?

La respuesta sale de los datos, vía **3 palancas independientes** (§2).

---

## 2. Las 3 palancas independientes

Cada una se activa sola por datos. Son ortogonales: un negocio puede usar 0, 1, 2 o
las 3.

### Palanca A — `capacidad_simultanea` (int, default 1)
Columna en `negocios`. Cuántas reservas que solapan caben en el **recurso global**
antes de marcar la franja como llena.
- `1` → recurso único (un peluquero solo, una camilla). Comportamiento de siempre.
- `N` → varios recursos idénticos en paralelo (10 mesas, 4 pistas, aforo 30).
- Hoy está **hardcodeada** en el JS del Motor (`const CAPACIDAD = {<id Tasqueta>: 10}`).
  El plan (TAREA 3) la mueve a la columna; el Motor la leería de la DB. Mientras no se
  migre, los negocios fuera del map valen 1 (idéntico a hoy).

### Palanca B — `corte_franja` (int, default 14)
Columna en `negocios`. Hora entera que parte el día en dos grupos al ofrecer huecos:
- `14` → "Por la mañana" / "Por la tarde" (peluquería, clínica, taller, gym, pádel…).
- `18` → "Mediodía" / "Por la noche" (restaurante).
- Hoy hardcodeada (`const RESTAURANTE = new Set([<id Tasqueta>])` + corte 18). Mismo
  plan: a columna.

### Palanca C — Profesionales con agenda (por DATOS, sin flag)
**Regla de oro en acción.** El Motor mira si, para el servicio pedido, hay filas en
`profesional_servicios` (profesionales activos del negocio que hacen ese servicio):
- **Hay filas → modo profesional.** El solape y el cupo se calculan **por agenda de
  cada profesional** (capacidad 1 por persona). Se ofrece elegir profesional y se
  guarda `reservas.profesional_id`. (Ya implementado en `3a`/`3a-2`/`3b` del Motor DEV
  — ver `docs/profesionales-motor.md`.)
- **No hay filas → comportamiento global.** Se usa `capacidad_simultanea` y las
  ocupadas globales. **Idéntico a hoy.** Cero impacto en Tasqueta.

> Prioridad cuando coexisten: en modo profesional la capacidad efectiva es **1 por
> profesional** (ignora `capacidad_simultanea`, que es para recursos globales). Si el
> negocio no usa profesionales, manda `capacidad_simultanea`.

---

## 3. Las verticales

Recurso, palancas y vocabulario por vertical. **Inmobiliaria excluida.**

| Vertical | Recurso | `capacidad_simultanea` | `corte_franja` | Profesionales | Vocabulario | Servicios típicos |
|---|---|---|---|---|---|---|
| **Estética** (primaria) | profesional | 1 (por agenda) | 14 | ✅ sí | cita / profesional | limpieza facial, antiedad, depilación, masaje, manicura |
| **Peluquería / Barbería** | profesional | 1 (por agenda) | 14 | ✅ sí | cita / profesional | corte, tinte, peinado, barba |
| **Clínica / Dental** | profesional (doctor) | 1 (por agenda) | 14 | ✅ sí | cita / doctor | revisión, limpieza, empaste, ortodoncia |
| **Fisioterapia** | profesional/camilla | 1 (por agenda) | 14 | ✅ sí | cita / fisio | sesión, primera visita, punción seca |
| **Taller mecánico** | bahía / elevador | N (nº bahías) | 14 | ⚠️ opcional | cita / vehículo | revisión, neumáticos, ITV, diagnosis |
| **Restaurante** | mesa | N (cupo del local) | **18** | ❌ no | mesa / comensales | comida, cena (tipos de mesa por nº personas) |
| **Gimnasio** | plaza en clase | N (aforo) | 14 | ❌ no | plaza / clase | clase dirigida (spinning, yoga…) |
| **Pádel** | pista | N (nº pistas) | 14 | ✅ sí (pista = recurso) | pista | reserva de pista 60/90 min |

Notas por vertical:
- **Estética/peluquería/clínica/fisio:** núcleo "modo profesional". Cada
  profesional, una agenda (cap 1). El servicio determina qué profesionales lo hacen.
- **Taller:** recurso = bahía. `capacidad_simultanea` = nº de bahías. "Profesionales
  opcional" = si quieres asignar mecánico concreto, se modela como profesional
  (entonces cap 1 por mecánico); si no, cupo global por bahías.
- **Restaurante:** sin profesionales. `capacidad_simultanea` = mesas simultáneas,
  `corte_franja` = 18. Es el caso de Tasqueta — **debe quedar idéntico**.
- **Gimnasio:** recurso = plaza en una clase con aforo. `capacidad_simultanea` =
  aforo. (Las clases tienen horario fijo; modelable como "servicio con franjas".)
- **Pádel:** cada **pista** es un recurso con agenda (cap 1 por pista). Se modela
  como "profesional" (pista = recurso con agenda propia) → reutiliza el modo
  profesional sin código nuevo. `capacidad_simultanea` global = nº de pistas si se
  prefiere el modelo de cupo en vez de pista-elegida.

---

## 4. Objetivo estrella: alta de cliente = 1 fila en DB, CERO cambios en n8n

Multi-tenant real: dar de alta un negocio nuevo = insertar filas en la DB y nada más.
El Motor y las tools leen `negocio_id` de la DB (resuelto por `chatwoot_account_id`),
no hardcodeado.

### Dónde estamos hoy
- El flujo **canónico** ya resuelve el negocio por `chatwoot_account_id` en el nodo
  `4. Cargar negocio + rol` → devuelve `negocio_id`. Las tools del agente ya pasan
  `={{ $('4. Cargar negocio + rol').first().json.negocio_id }}` (dinámico). ✅
- El flujo **Tasqueta** (demo) tiene el `negocio_id` **hardcodeado** (`8d0ce837…`) en
  las 6 tools. ❌ Eso es lo que hay que eliminar para multi-tenant.
- El **Motor** tiene hardcodeados en JS la `CAPACIDAD` y el set `RESTAURANTE` por id
  de negocio. ❌ Hay que moverlos a columnas (palancas A y B).

### Las 6 tools (operaciones del Motor) que llevan `negocio_id`
`consultar` · `crear` · `cancelar` · `agenda` · `actualizar` (mover) · `mis_reservas`.

### Plan para llegar (concreto)
1. **Un solo flujo canónico multi-negocio.** Jubilar los flujos por-cliente (Tasqueta
   pasa a ser datos, no un flujo). El canónico resuelve `negocio_id` por
   `chatwoot_account_id`. → cada cliente nuevo NO necesita un flujo nuevo.
2. **`negocio_id` dinámico en las 6 tools** = `={{ $('4. Cargar negocio + rol')
   .first().json.negocio_id }}` en TODAS (el canónico ya lo hace; el bug del `==` que
   se corrigió era justo esto). Cero UUID hardcodeado.
3. **Config por DB, no por JS** (palancas A y B): el Motor lee
   `negocios.capacidad_simultanea` y `negocios.corte_franja` en `3a`/`3a-2`/`3b` en vez
   del `const CAPACIDAD`/`RESTAURANTE`. (Columnas = TAREA 3; el cambio del Motor para
   leerlas es un paso posterior, documentado aquí como pendiente.)
4. **Profesionales por DATOS** (palanca C): ya está. Añadir profesionales a un negocio
   = filas en `profesionales` + `profesional_servicios`. Sin tocar el Motor.
5. **Onboarding = un INSERT set.** Alta de negocio:
   ```
   INSERT negocios (slug, nombre, tipo_vertical, chatwoot_account_id, dueno_telefono,
                    horario, capacidad_simultanea, corte_franja, ...)   -- la fila + su id
   INSERT servicios (negocio_id, nombre, duracion_minutos, precio, ...) -- su catálogo
   -- si usa profesionales:
   INSERT profesionales (...)  +  INSERT profesional_servicios (...)
   ```
   Con eso, el flujo canónico ya atiende al negocio nuevo. **Cero cambios en n8n.**

### Qué falta exactamente (checklist)
- [ ] Migrar `capacidad_simultanea` + `corte_franja` a `negocios` (TAREA 3 — columnas listas).
- [ ] Cambiar el Motor para LEER esas columnas (hoy en JS hardcodeado) — paso futuro.
- [ ] Unificar en un único flujo canónico; eliminar `negocio_id` hardcodeado de Tasqueta.
- [ ] Conectar cada negocio nuevo en Chatwoot (su `chatwoot_account_id` en la fila).
- [ ] Onboarding script/checklist que haga los INSERT (datos sintéticos en DEV; reales en prod).

---

## 5. Invariantes que NingúN cambio puede romper

- **Tasqueta idéntica.** Restaurante, sin profesionales, `capacidad_simultanea`=10,
  `corte_franja`=18. Cualquier cambio se valida contra esto (QA — TAREA 2).
- **Aditividad.** Una vertical/negocio que no usa una palanca se comporta como antes.
- **Verdad en Postgres.** Toda decisión (solape, cupo, pasado, horario, autorización)
  en SQL. El prompt nunca valida.
- **Gate de actor.** La agenda (operación `agenda`) es solo del dueño; cancelar/mover
  de cliente solo afectan a sus propias reservas. (Ya en el Motor.)
