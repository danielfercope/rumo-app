-- Carteira de empresas por organização + conexão com o CRM de cada uma.
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).
--
-- "Organização" é o grupo de 007_groups.sql (groups/group_members): quem usa
-- a plataforma e é dono dos próprios dados. Cada uma importa a sua carteira
-- (clientes, leads, perdidos) do CRM, e é dela que o algoritmo de prioridade
-- aprende o perfil de cliente ideal.
--
--   companies           segue GLOBAL: dado público (CNPJ, endereço, CNAE...),
--                       enriquecido uma vez e reaproveitado por todas.
--   carteira_empresas   a relação de UMA organização com UMA empresa
--                       (cliente/lead/perdido). Empresa sem linha aqui é o
--                       universo de candidatos a ser pontuado.
--   crm_conexoes        credencial + mapeamento de campos do CRM da organização.
--   sincronizacoes      log de cada carga/sincronização, pra tela de status.
--
-- Fora deste arquivo (passo seguinte, junto da refatoração do sync):
-- crm_sync_state/crm_sync_pending ainda são de conta única.

-- ── carteira_empresas ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.carteira_empresas (
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('cliente', 'lead', 'perdido')),
  origem text NOT NULL DEFAULT 'crm' CHECK (origem IN ('crm', 'manual')),
  crm_object_id text,
  status_atualizado_em timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, company_id)
);

CREATE INDEX IF NOT EXISTS carteira_empresas_company_idx
  ON public.carteira_empresas (company_id);
CREATE INDEX IF NOT EXISTS carteira_empresas_status_idx
  ON public.carteira_empresas (group_id, status);

-- ── crm_conexoes ────────────────────────────────────────────────────────────
-- token_cifrado é cifrado pelo Backend (chave fora do banco, no Secrets
-- Manager) antes de gravar; o banco nunca vê o token em claro nem a chave.
-- Uma conexão por organização, por ora.

CREATE TABLE IF NOT EXISTS public.crm_conexoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL UNIQUE REFERENCES public.groups(id) ON DELETE CASCADE,
  provedor text NOT NULL CHECK (provedor IN ('hubspot')),
  token_cifrado text NOT NULL,
  -- {"campo_cnpj": "...", "status": {"cliente": [...], "perdido": [...]}}
  mapeamento jsonb NOT NULL DEFAULT '{}'::jsonb,
  situacao text NOT NULL DEFAULT 'pendente'
    CHECK (situacao IN ('pendente', 'ativa', 'erro', 'desconectada')),
  ultimo_erro text,
  -- Marca d'água da sincronização incremental (por data de modificação no CRM).
  ultima_modificacao_crm timestamptz,
  ultima_sincronizacao timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ── sincronizacoes ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sincronizacoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  conexao_id uuid REFERENCES public.crm_conexoes(id) ON DELETE SET NULL,
  tipo text NOT NULL CHECK (tipo IN ('carga_inicial', 'incremental')),
  situacao text NOT NULL DEFAULT 'em_andamento'
    CHECK (situacao IN ('em_andamento', 'concluida', 'erro')),
  total_lidas integer NOT NULL DEFAULT 0,
  total_novas integer NOT NULL DEFAULT 0,
  total_atualizadas integer NOT NULL DEFAULT 0,
  total_falhas integer NOT NULL DEFAULT 0,
  erro text,
  iniciada_em timestamptz NOT NULL DEFAULT now(),
  concluida_em timestamptz
);

CREATE INDEX IF NOT EXISTS sincronizacoes_group_idx
  ON public.sincronizacoes (group_id, iniciada_em DESC);

-- ── Permissões e RLS ────────────────────────────────────────────────────────
-- web_user só LÊ, e só da(s) organização(ões) de que é membro. Toda escrita
-- é do Backend, com o papel crm_sync (o Backend confere no código que quem
-- pediu é admin da organização, via is_group_admin).

ALTER TABLE public.carteira_empresas ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.carteira_empresas TO web_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.carteira_empresas TO crm_sync;

DROP POLICY IF EXISTS carteira_empresas_select_member ON public.carteira_empresas;
CREATE POLICY carteira_empresas_select_member ON public.carteira_empresas
  FOR SELECT TO web_user USING (public.is_group_member(group_id));

DROP POLICY IF EXISTS carteira_empresas_all_crm_sync ON public.carteira_empresas;
CREATE POLICY carteira_empresas_all_crm_sync ON public.carteira_empresas
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);

-- crm_conexoes: mesmo padrão de groups.invite_hash — o GRANT de coluna deixa
-- token_cifrado de fora, então nenhum membro lê o segredo via PostgREST.
ALTER TABLE public.crm_conexoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crm_conexoes FROM web_user;
GRANT SELECT (id, group_id, provedor, mapeamento, situacao, ultimo_erro,
              ultima_sincronizacao, created_at)
  ON public.crm_conexoes TO web_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_conexoes TO crm_sync;

DROP POLICY IF EXISTS crm_conexoes_select_member ON public.crm_conexoes;
CREATE POLICY crm_conexoes_select_member ON public.crm_conexoes
  FOR SELECT TO web_user USING (public.is_group_member(group_id));

DROP POLICY IF EXISTS crm_conexoes_all_crm_sync ON public.crm_conexoes;
CREATE POLICY crm_conexoes_all_crm_sync ON public.crm_conexoes
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);

ALTER TABLE public.sincronizacoes ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.sincronizacoes TO web_user;
GRANT SELECT, INSERT, UPDATE ON public.sincronizacoes TO crm_sync;

DROP POLICY IF EXISTS sincronizacoes_select_member ON public.sincronizacoes;
CREATE POLICY sincronizacoes_select_member ON public.sincronizacoes
  FOR SELECT TO web_user USING (public.is_group_member(group_id));

DROP POLICY IF EXISTS sincronizacoes_all_crm_sync ON public.sincronizacoes;
CREATE POLICY sincronizacoes_all_crm_sync ON public.sincronizacoes
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);

-- ── Backfill do que já existe ───────────────────────────────────────────────
-- companies.is_client era um flag global. Pra não perder o que já está no
-- banco, este utilitário copia o flag pra carteira de UMA organização
-- (idempotente). Rodado à mão, via psql/SSM, depois de escolher o grupo —
-- por isso não é concedido a web_user.
CREATE OR REPLACE FUNCTION public.backfill_carteira_from_is_client(p_group_id uuid)
RETURNS integer AS $$
  WITH ins AS (
    INSERT INTO public.carteira_empresas (group_id, company_id, status, origem)
    SELECT p_group_id, c.id,
           CASE WHEN c.is_client IS TRUE THEN 'cliente' ELSE 'lead' END,
           'manual'
    FROM public.companies c
    ON CONFLICT (group_id, company_id) DO NOTHING
    RETURNING 1
  )
  SELECT count(*)::integer FROM ins;
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.backfill_carteira_from_is_client(uuid) FROM PUBLIC;
