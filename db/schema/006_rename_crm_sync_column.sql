-- Renomeia company_crm_sync.hubspot_contact_id -> crm_object_id. Nome
-- agnóstico de fornecedor (ver CrmService/CompanyLookupService) — seguro
-- fazer agora porque nenhum código ainda lê/escreve essa coluna.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'company_crm_sync'
      AND column_name = 'hubspot_contact_id'
  ) THEN
    ALTER TABLE public.company_crm_sync RENAME COLUMN hubspot_contact_id TO crm_object_id;
  END IF;
END $$;
