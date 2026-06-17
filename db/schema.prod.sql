-- db/schema.prod.sql
-- Schema de PRODUCCIÓN `mims_app` (PostgreSQL 16), SOLO estructura (DDL), CERO datos.
--
-- VENDORED: copia byte-fiel de mims-qa/fixtures/schema.sql (la única fuente limpia
-- del schema de prod). Si el schema de prod cambia, re-sincroniza ese archivo y este.
--   * Solo DDL. Se eliminaron TODOS los INSERT del dump original: eran datos REALES
--     de producción (nombres, teléfonos y citas = PII). Jamás datos reales en el repo.
--   * `DELIMITER ;;` (Adminer/MySQL) -> PL/pgSQL. + CREATE EXTENSION unaccent (lo usa
--     el Motor) + función trigger_set_updated_at() (los triggers la referencian).
--
-- Lo aplica scripts/setup-dev-db.sql sobre la DB DEV `mims_dev` (NUNCA sobre prod).
-- Los negocios sintéticos de dev se siembran en db/seed-dev.sql.
--
-- NOTA: prod tiene además la columna negocios.agente_activo (la usan los flujos:
-- nodo "4.5 ¿Bot activo?"), que este dump limpio no traía. setup-dev-db.sql la
-- añade con ALTER. Confirmar contra prod y, si procede, sincronizar aquí.

CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION trigger_set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Limpieza idempotente (permite re-aplicar el schema sobre una DB existente).
DROP TABLE IF EXISTS "public"."agent_alerts" CASCADE;
DROP TABLE IF EXISTS "public"."casos_test" CASCADE;
DROP TABLE IF EXISTS "public"."historial" CASCADE;
DROP TABLE IF EXISTS "public"."mensajes_procesados" CASCADE;
DROP TABLE IF EXISTS "public"."negocios" CASCADE;
DROP TABLE IF EXISTS "public"."profesional_servicios" CASCADE;
DROP TABLE IF EXISTS "public"."profesionales" CASCADE;
DROP TABLE IF EXISTS "public"."reservas" CASCADE;
DROP TABLE IF EXISTS "public"."resultados_test" CASCADE;
DROP TABLE IF EXISTS "public"."servicios" CASCADE;
DROP SEQUENCE IF EXISTS historial_id_seq;
DROP SEQUENCE IF EXISTS resultados_test_id_resultado_seq;

-- ===================== agent_alerts =====================
CREATE TABLE "public"."agent_alerts" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "negocio_id" uuid NOT NULL,
    "cliente_telefono" text NOT NULL,
    "cliente_nombre" text,
    "motivo" text NOT NULL,
    "resumen" text,
    "mensaje_cliente" text,
    "status" text DEFAULT 'pendiente',
    "enviado_en" timestamptz,
    "created_at" timestamptz DEFAULT now(),
    CONSTRAINT "agent_alerts_pkey" PRIMARY KEY ("id")
);
CREATE INDEX idx_alerts_pendientes ON public.agent_alerts USING btree (negocio_id, cliente_telefono, status, created_at DESC);

-- ===================== casos_test =====================
CREATE TABLE "public"."casos_test" (
    "id" text NOT NULL,
    "grupo" text NOT NULL,
    "nombre" text NOT NULL,
    "como_rol" text DEFAULT 'cliente',
    "mensaje" text NOT NULL,
    "espera_texto" text,
    "no_espera_texto" text,
    "activo" boolean DEFAULT true,
    CONSTRAINT "casos_test_pkey" PRIMARY KEY ("id")
);

-- ===================== historial =====================
CREATE SEQUENCE historial_id_seq INCREMENT 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1;
CREATE TABLE "public"."historial" (
    "id" bigint DEFAULT nextval('historial_id_seq') NOT NULL,
    "negocio_id" uuid NOT NULL,
    "cliente_telefono" text NOT NULL,
    "cliente_nombre" text,
    "role" text NOT NULL,
    "mensaje" text NOT NULL,
    "session_state" jsonb,
    "created_at" timestamptz DEFAULT now(),
    CONSTRAINT "historial_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "historial_role_check" CHECK (((role = ANY (ARRAY['user'::text, 'assistant'::text, 'system'::text]))))
);
CREATE INDEX idx_historial_cliente ON public.historial USING btree (negocio_id, cliente_telefono, created_at DESC);

-- ===================== mensajes_procesados =====================
CREATE TABLE "public"."mensajes_procesados" (
    "message_id" text NOT NULL,
    "cliente_telefono" text,
    "created_at" timestamptz DEFAULT now(),
    CONSTRAINT "mensajes_procesados_pkey" PRIMARY KEY ("message_id")
);
CREATE INDEX idx_mensajes_procesados_created_at ON public.mensajes_procesados USING btree (created_at);

-- ===================== negocios =====================
CREATE TABLE "public"."negocios" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "slug" text NOT NULL,
    "nombre" text NOT NULL,
    "tipo_vertical" text NOT NULL,
    "direccion" text,
    "phone_number_id" text NOT NULL,
    "dueno_telefono" text,
    "horario" jsonb,
    "max_dias_futuros" integer DEFAULT 14,
    "zona_horaria" text DEFAULT 'Europe/Madrid',
    "activo" boolean DEFAULT true,
    "created_at" timestamptz DEFAULT now(),
    "updated_at" timestamptz DEFAULT now(),
    "telefono_contacto" text,
    "email_contacto" text,
    "web" text,
    "instagram" text,
    "chatwoot_account_id" text,
    CONSTRAINT "negocios_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX negocios_slug_key ON public.negocios USING btree (slug);
CREATE UNIQUE INDEX negocios_phone_number_id_key ON public.negocios USING btree (phone_number_id);
CREATE INDEX idx_negocios_phone_number_id ON public.negocios USING btree (phone_number_id) WHERE (activo = true);
CREATE TRIGGER "trg_negocios_updated_at" BEFORE UPDATE ON "public"."negocios" FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ===================== profesional_servicios =====================
CREATE TABLE "public"."profesional_servicios" (
    "profesional_id" uuid NOT NULL,
    "servicio_id" uuid NOT NULL,
    CONSTRAINT "profesional_servicios_pkey" PRIMARY KEY ("profesional_id", "servicio_id")
);

-- ===================== profesionales =====================
CREATE TABLE "public"."profesionales" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "negocio_id" uuid NOT NULL,
    "nombre" text NOT NULL,
    "servicios" text[],
    "horario" jsonb,
    "activo" boolean DEFAULT true,
    "created_at" timestamptz DEFAULT now(),
    CONSTRAINT "profesionales_pkey" PRIMARY KEY ("id")
);
CREATE INDEX idx_profesionales_negocio ON public.profesionales USING btree (negocio_id) WHERE (activo = true);

-- ===================== reservas =====================
CREATE TABLE "public"."reservas" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "negocio_id" uuid NOT NULL,
    "cliente_telefono" text,
    "cliente_nombre" text,
    "servicios_json" jsonb,
    "servicios_resumen" text,
    "duracion_minutos" integer,
    "precio_total" numeric(10,2),
    "fecha" date NOT NULL,
    "hora_inicio" time without time zone NOT NULL,
    "hora_fin" time without time zone NOT NULL,
    "profesional" text,
    "estado" text DEFAULT 'pendiente_confirmacion_cliente' NOT NULL,
    "created_at" timestamptz DEFAULT now(),
    "updated_at" timestamptz DEFAULT now(),
    "profesional_id" uuid,
    CONSTRAINT "reservas_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "reservas_estado_check" CHECK (((estado = ANY (ARRAY['pendiente_confirmacion_cliente'::text, 'confirmado'::text, 'cancelado'::text, 'descartado_cliente'::text]))))
);
CREATE INDEX idx_reservas_negocio_fecha ON public.reservas USING btree (negocio_id, fecha) WHERE (estado = ANY (ARRAY['confirmado'::text, 'pendiente_confirmacion_cliente'::text]));
CREATE INDEX idx_reservas_telefono ON public.reservas USING btree (negocio_id, cliente_telefono, fecha DESC);
CREATE INDEX idx_reservas_profesional_fecha ON public.reservas USING btree (profesional_id, fecha) WHERE (estado = ANY (ARRAY['confirmado'::text, 'pendiente_confirmacion_cliente'::text]));
CREATE TRIGGER "trg_reservas_updated_at" BEFORE UPDATE ON "public"."reservas" FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ===================== resultados_test =====================
CREATE SEQUENCE resultados_test_id_resultado_seq INCREMENT 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1;
CREATE TABLE "public"."resultados_test" (
    "id_resultado" bigint DEFAULT nextval('resultados_test_id_resultado_seq') NOT NULL,
    "corrida" text,
    "caso_id" text,
    "grupo" text,
    "nombre" text,
    "mensaje_enviado" text,
    "respuesta_bot" text,
    "espera_texto" text,
    "resultado" text,
    "detalle" text,
    "created_at" timestamptz DEFAULT now(),
    CONSTRAINT "resultados_test_pkey" PRIMARY KEY ("id_resultado")
);

-- ===================== servicios =====================
CREATE TABLE "public"."servicios" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "negocio_id" uuid NOT NULL,
    "nombre" text NOT NULL,
    "duracion_minutos" integer DEFAULT 30 NOT NULL,
    "precio" numeric(10,2) DEFAULT 0 NOT NULL,
    "profesional" text,
    "categoria" text DEFAULT 'General',
    "descripcion" text,
    "activo" boolean DEFAULT true,
    "created_at" timestamptz DEFAULT now(),
    CONSTRAINT "servicios_pkey" PRIMARY KEY ("id")
);
CREATE INDEX idx_servicios_negocio ON public.servicios USING btree (negocio_id) WHERE (activo = true);

-- ===================== claves foráneas =====================
ALTER TABLE ONLY "public"."historial" ADD CONSTRAINT "historial_negocio_id_fkey" FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE;
ALTER TABLE ONLY "public"."profesional_servicios" ADD CONSTRAINT "profesional_servicios_profesional_id_fkey" FOREIGN KEY (profesional_id) REFERENCES profesionales(id) ON DELETE CASCADE;
ALTER TABLE ONLY "public"."profesional_servicios" ADD CONSTRAINT "profesional_servicios_servicio_id_fkey" FOREIGN KEY (servicio_id) REFERENCES servicios(id) ON DELETE CASCADE;
ALTER TABLE ONLY "public"."profesionales" ADD CONSTRAINT "profesionales_negocio_id_fkey" FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE;
ALTER TABLE ONLY "public"."reservas" ADD CONSTRAINT "reservas_negocio_id_fkey" FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE;
ALTER TABLE ONLY "public"."reservas" ADD CONSTRAINT "reservas_profesional_id_fkey" FOREIGN KEY (profesional_id) REFERENCES profesionales(id) ON DELETE SET NULL;
ALTER TABLE ONLY "public"."servicios" ADD CONSTRAINT "servicios_negocio_id_fkey" FOREIGN KEY (negocio_id) REFERENCES negocios(id) ON DELETE CASCADE;
