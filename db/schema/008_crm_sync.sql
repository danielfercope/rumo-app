-- Sincronização CRM -> banco (backend/app/services/crm_sync_service.py).
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).
--
--   crm_sync_state    marca d'água do job: maior ID de empresa do CRM já
--                     processado. É o que permite checar "há empresa nova?"
--                     com uma única consulta, sem varrer o CRM nem o banco.
--   crm_sync_pending  empresas do CRM que falharam no ETL (CNPJ não achado,
--                     endereço sem coordenada...) e aguardam nova tentativa.
--                     Tabela à parte porque companies.latitude/longitude são
--                     NOT NULL e company_crm_sync tem FK pra companies.

-- Papel do job: o Backend emite um token interno com role = "crm_sync"
-- (ver backend/app/services/postgrest_client.py) e o PostgREST faz SET ROLE.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'crm_sync') THEN
    CREATE ROLE crm_sync NOLOGIN;
  END IF;
END $$;

GRANT crm_sync TO authenticator;
GRANT USAGE ON SCHEMA public TO crm_sync;

CREATE TABLE IF NOT EXISTS public.crm_sync_state (
  key text NOT NULL,
  last_crm_id bigint NOT NULL,
  last_run_at timestamp with time zone,
  last_status text,
  CONSTRAINT crm_sync_state_pkey PRIMARY KEY (key)
);

CREATE TABLE IF NOT EXISTS public.crm_sync_pending (
  crm_object_id text NOT NULL,
  cnpj text NOT NULL,
  attempts integer NOT NULL DEFAULT 1,
  last_error text,
  next_retry_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT crm_sync_pending_pkey PRIMARY KEY (crm_object_id)
);

CREATE INDEX IF NOT EXISTS crm_sync_pending_retry_idx
  ON public.crm_sync_pending (next_retry_at);

-- Só o papel do job enxerga as tabelas de controle (nem web_user nem web_anon).
GRANT SELECT, INSERT, UPDATE ON public.crm_sync_state TO crm_sync;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_sync_pending TO crm_sync;

-- companies: o job só lê e insere — nunca atualiza (não sobrescreve o que o
-- app já cadastrou; o INSERT usa ON CONFLICT DO NOTHING).
GRANT SELECT, INSERT ON public.companies TO crm_sync;
GRANT SELECT, INSERT, UPDATE ON public.company_crm_sync TO crm_sync;

DROP POLICY IF EXISTS companies_select_crm_sync ON public.companies;
CREATE POLICY companies_select_crm_sync ON public.companies
  FOR SELECT TO crm_sync USING (true);

DROP POLICY IF EXISTS companies_insert_crm_sync ON public.companies;
CREATE POLICY companies_insert_crm_sync ON public.companies
  FOR INSERT TO crm_sync WITH CHECK (true);

DROP POLICY IF EXISTS company_crm_sync_all_crm_sync ON public.company_crm_sync;
CREATE POLICY company_crm_sync_all_crm_sync ON public.company_crm_sync
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);
