-- Schema novo, desenhado do zero (sem migrar dados do Supabase, conforme
-- combinado) — substitui a tabela única `central_data` (~50 colunas) por
-- um modelo separado por domínio:
--   companies                 identidade + geo (caminho rápido da busca)
--   company_financial_profile dados de crédito/score (consulta só no detalhe)
--   company_contacts          telefones/e-mails/redes sociais secundários (1:N)
--   company_crm_sync          status de sincronização com o HubSpot

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE public.companies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  cnpj text NOT NULL,
  razao_social text,
  nome_fantasia text,
  segmento text,
  cnae_principal text,
  natureza_juridica text,
  porte text,
  situacao text,
  data_abertura date,
  is_client boolean,
  produto text,
  url_company_page text,
  endereco_completo text,
  tipo_logradouro text,
  logradouro text,
  numero text,
  bairro text,
  municipio text,
  uf text,
  cep text,
  precisao_geocodificacao text,
  telefone_principal text,
  email_principal text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT companies_pkey PRIMARY KEY (id),
  CONSTRAINT companies_cnpj_unique UNIQUE (cnpj)
);

CREATE TABLE public.company_financial_profile (
  company_id uuid NOT NULL,
  faixa_faturamento text,
  faixa_funcionarios text,
  regime_tributario text,
  divida_ativa_uniao text,
  saude_tributaria text,
  score_propensao text,
  CONSTRAINT company_financial_profile_pkey PRIMARY KEY (company_id),
  CONSTRAINT company_financial_profile_company_id_fkey
    FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

CREATE TABLE public.company_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  contact_type text NOT NULL, -- 'phone' | 'email' | 'linkedin' | 'instagram' | 'facebook' | 'twitter'
  value text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT company_contacts_pkey PRIMARY KEY (id),
  CONSTRAINT company_contacts_company_id_fkey
    FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

CREATE TABLE public.company_crm_sync (
  company_id uuid NOT NULL,
  hubspot_contact_id text,
  last_synced_at timestamp with time zone,
  sync_status text,
  CONSTRAINT company_crm_sync_pkey PRIMARY KEY (company_id),
  CONSTRAINT company_crm_sync_company_id_fkey
    FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- ── Auth/perfil (Firebase) e tracking — sem mudança de modelagem aqui,
-- só o id/user_id como text (UID do Firebase não é UUID). ──────────────────

CREATE TABLE public.profiles (
  id text NOT NULL,
  email text,
  nome text,
  departamento text,
  nivel_acesso text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);

CREATE TABLE public.tracking_equipe (
  user_id text NOT NULL,
  email text,
  nome text,
  latitude double precision,
  longitude double precision,
  ultimo_visto timestamp with time zone DEFAULT now(),
  CONSTRAINT tracking_equipe_pkey PRIMARY KEY (user_id)
);

CREATE TABLE public.tracking_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id text NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  captured_at timestamp with time zone DEFAULT now(),
  CONSTRAINT tracking_history_pkey PRIMARY KEY (id)
);
