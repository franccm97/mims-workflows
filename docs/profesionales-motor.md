# Profesionales en el Motor de Reservas — diseño

Plan técnico para que el Motor maneje negocios con **profesionales** (clínica
estética, peluquería con varios estilistas, médicos…), donde una reserva no es solo
"hay hueco" sino "hay hueco **con esta persona**".

> ⚠️ Esto es DISEÑO + CONTRATO. NO incluye el SQL final del Motor ni cambios en n8n.
> Implementación = otro encargo, tras revisar este documento.

---

## 0. Estado actual (para entender qué cambia)

Hoy el Motor trata cada negocio como **un único recurso** (o N recursos idénticos vía
`capacidad_simultanea`). El flujo de disponibilidad es:

- **3a. Cargar datos** — trae el servicio (nombre, duración) + `horario` del negocio +
  `ocupadas` = todas las reservas de ese día (intervalos), GLOBALES.
- **3a-2. Calcular huecos** (JS) — genera slots desde el horario, descarta pasados,
  y marca un slot lleno cuando las reservas que solapan alcanzan la capacidad.
- **3b. Crear reserva** — comprueba solape global y hace el INSERT (sin `profesional_id`).

No hay noción de "quién atiende". `reservas.profesional_id` y las tablas
`profesionales` / `profesional_servicios` existen en el schema pero el Motor no las usa.

---

## 1. REGLA DE ORO (no negociable)

**El Motor detecta si un negocio usa profesionales por sus DATOS, NO por un flag.**

Concretamente: para el **servicio pedido**, ¿existen filas en `profesional_servicios`
que liguen a profesionales (activos) de ese negocio con ese servicio?

- **Sí hay filas → MODO PROFESIONAL.** Enseña profesionales y calcula huecos por
  profesional.
- **No hay filas → COMPORTAMIENTO ACTUAL, idéntico.** Huecos globales, exactamente
  como hoy.

Consecuencias (por qué se hace así):
- **Cero flag que mantener.** No hay `usa_profesionales boolean` que alguien olvide
  poner. La capacidad se "enciende" sola en cuanto existen profesionales + sus enlaces.
- **Cero impacto en negocios sin profesionales** (Tasqueta, restaurante, etc.): su
  `profesional_servicios` está vacío → la detección da false → corren por el camino
  actual, byte-idéntico. Nada que migrar, nada que romper.
- **Activación por datos:** añadir profesionales a un negocio = insertar en
  `profesionales` + `profesional_servicios` (como hace la migración 003 para Aura).
  No se toca el Motor para activarlo en un negocio nuevo.

### Cómo se detecta (contrato, NO SQL final)

Predicado de detección, evaluado para el servicio ya resuelto del negocio:

```
modo_profesional :=
  EXISTS filas en profesional_servicios
  donde el servicio = el servicio pedido (match por nombre, unaccent ILIKE, dentro del negocio)
  y el profesional pertenece al negocio y está activo
```

- Si el flujo aún no conoce el servicio (p.ej. una consulta genérica), se usa un
  **fallback a nivel de negocio**: ¿tiene el negocio ALGÚN `profesional_servicios`?
  Pero la detección **preferida es por servicio** (más precisa: un negocio podría tener
  unos servicios con profesional y otros sin).

---

## 2. Contrato de la tool (qué entra / qué sale)

### Parámetro nuevo: `profesional`

- **Nombre:** `profesional` (string, **opcional**).
- **Semántica:** el profesional elegido por el cliente, por su nombre tal cual lo diga
  ("con Laura", "el Dr. Soler"). Vacío = sin preferencia / aún no elegido.
- El Motor lo resuelve a `profesional_id` por match de nombre (`unaccent ILIKE`) dentro
  del negocio **y** restringido a quienes hacen el servicio pedido.
- Se añade al Trigger del Motor (`executeWorkflowTrigger`, junto a `fn/servicio/fecha/…`)
  y a las tools del agente (`CONSULTAR`, `CREAR`, y `MODIFICAR` si aplica) como
  `={{ $fromAI('profesional', 'profesional que pide el cliente, si lo dice; vacio si le da igual') }}`.
- ⚠️ El wiring en n8n NO se hace aquí (toca el Motor). Esto solo fija el contrato.

### Resto de campos: sin cambios

`fn, negocio_id, servicio, fecha, hora, nombre, confirmar, from_number, fecha_nueva,
hora_nueva, servicio_nuevo, fecha_hasta` siguen igual.

### Salida

La salida EXTERNA de la tool sigue siendo el mismo `response` (texto para el agente).
Lo nuevo viaja INTERNO entre nodos (3a → 3a-2): lista de profesionales y ocupadas por
profesional (ver §3). El cliente final ve texto; el contrato externo no cambia de forma.

---

## 3. Cambios por nodo (diseño, NO SQL final)

### 3a. Cargar datos  ·  (consultar)

Hoy: trae servicio + horario + `ocupadas` global. **Añadir, solo en modo profesional:**

1. **Lista de profesionales que hacen el servicio pedido**, con lo necesario para
   calcular huecos: `id`, `nombre`, y su `horario` (jsonb de `profesionales`; si está
   vacío, se usa el `horario` del negocio como fallback).
2. **Ocupadas POR profesional**, no global: las reservas de ese día (estado en
   `confirmado`/`pendiente_confirmacion_cliente`) agrupadas por `profesional_id`.

Forma de los campos internos nuevos que salen de 3a (contrato hacia 3a-2):

```
profesionales            : [ { id, nombre, horario } ]          # los que hacen el servicio
ocupadas_por_profesional : { "<profesional_id>": [ {ini, fin}, ... ], ... }
modo_profesional         : true | false
```

Si `modo_profesional = false`: 3a devuelve EXACTAMENTE lo de hoy (servicio, horario,
`ocupadas` global). Sin campos nuevos en juego.

### 3a-2. Calcular huecos  ·  (JS)

- **Modo global (false):** sin cambios. Misma lógica de capacidad/`corte_franja`/pasados.
- **Modo profesional (true):**
  - **Capacidad = 1 por profesional** (cada profesional es un recurso). En modo
    profesional NO se usa `capacidad_simultanea` (esa es para recursos globales
    idénticos); aquí el límite es 1 por persona.
  - **Si `profesional` elegido** → calcular huecos SOLO de ese profesional: su horario
    (∩ horario del negocio si procede) menos sus `ocupadas`. Mismo descarte de horas
    pasadas si es hoy. Mismo agrupado mañana/tarde por `corte_franja`.
  - **Si modo profesional pero SIN `profesional` elegido** → no inventar un hueco
    "global". Devolver la **lista de profesionales** que hacen el servicio (y, si se
    quiere, marcar quién tiene hueco ese día) y pedir al cliente que elija. Una vez
    elija, segunda llamada con `profesional` → se calculan sus huecos.
  - **"Me da igual / cualquiera"** (cliente sin preferencia): el agente pasa
    `profesional` vacío; el Motor elige el profesional con MÁS huecos ese día (o el
    primero con hueco). ← decisión a confirmar; alternativa: ofrecer huecos de todos.

### 3b. Crear reserva

- **Resolver `profesional_id`** desde `profesional` (nombre → id, `unaccent ILIKE`,
  dentro del negocio y entre quienes hacen el servicio).
- **Comprobación de solape POR profesional**: en vez del solape global, contar las
  reservas de ESE `profesional_id` que pisan la franja (capacidad 1). Si solapa → ese
  profesional está ocupado a esa hora.
- **INSERT** con `profesional_id` (uuid) **y** `profesional` (nombre, para el texto de
  confirmación / la notificación al dueño).
- **Guardas nuevas (modo profesional):**
  - Sin `profesional` resuelto y el servicio lo hacen VARIOS → no crear; devolver
    "elige profesional" (lista).
  - Si lo hace UNO solo → auto-seleccionar ese profesional (no hace falta preguntar).
  - Nombre del cliente sigue siendo obligatorio (igual que hoy).
- **Modo global:** INSERT sin `profesional_id` (NULL), exactamente como hoy.

### 3c. Cancelar / 3e. Actualizar  ·  (nota, no en alcance ahora)

- Cancelar: puede seguir igual (busca por negocio+fecha+hora±nombre). En modo
  profesional convendría poder desambiguar por profesional si hay varias a la misma
  hora con distinto profesional.
- Actualizar (mover): el re-chequeo de solape del destino debe ser **por profesional**
  (mismo principio que 3b). Cambiar de profesional = otro caso a diseñar.
- Se detalla cuando se implemente el núcleo (consultar/crear).

---

## 4. Casos a cubrir (cuando se implemente + se teste)

| Caso | Esperado |
|---|---|
| Negocio SIN profesionales (Tasqueta) | Camino actual, byte-idéntico. Cero cambios visibles |
| Servicio que hace 1 solo profesional | Auto-selección; no se pregunta |
| Servicio que hacen varios, cliente elige | Huecos del elegido |
| Servicio que hacen varios, "me da igual" | Profesional con más hueco (a confirmar) / o huecos de todos |
| Profesional ocupado a esa hora, otro libre | Ofrece el libre / avisa |
| Nombre de profesional que no existe o no hace el servicio | Pide aclarar; no inventa |
| Crear sin elegir profesional (varios) | No crea; pide elegir |

---

## 5. Datos que requiere

- `profesionales` (activos) del negocio + `profesional_servicios` (quién hace qué) +
  `reservas.profesional_id` poblado en las reservas con profesional.
- Banco de pruebas ya preparado: **migración 003** (Clínica Estética Aura) siembra
  exactamente esto (5 servicios, 3 profesionales, el cruce y 2 reservas con
  `profesional_id`). Es el negocio contra el que validar el modo profesional.

---

## 6. Fuera de alcance de este documento

- SQL final de 3a / 3a-2 / 3b.
- Cambios en n8n (Trigger, tools del agente, prompts).
- Cancelar/mover en modo profesional (solo esbozado).
- Horario por profesional avanzado (vacaciones, ausencias) — el `horario` jsonb por
  profesional ya está en el schema; su uso fino se diseña al implementar.
