-- Resultado do cálculo de prioridade por organização. É recalculado pelo
-- Backend ao fim de cada sincronização que mudou a carteira; o app só LÊ daqui
-- (nenhuma consulta varre `companies` nem recalcula nada).
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).
--
--   prioridade_modelos    1 linha por organização: qual estratégia valeu na
--                         última vez, tamanho da carteira e o modelo ajustado
--                         (jsonb, só na estratégia "perfil").
--   carteira_prioridade   1 linha por lead, já ordenada (posicao) e com os
--                         motivos que explicam a posição.

CREATE TABLE IF NOT EXISTS public.prioridade_modelos (
  group_id uuid PRIMARY KEY REFERENCES public.groups(id) ON DELETE CASCADE,
  estrategia text NOT NULL CHECK (estrategia IN ('interacao', 'perfil')),
  n_clientes integer NOT NULL,
  n_leads integer NOT NULL,
  modelo jsonb,
  calculado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.carteira_prioridade (
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  posicao integer NOT NULL,
  nota integer,                      -- 0-100; nulo na estratégia "interacao"
  motivos jsonb NOT NULL DEFAULT '[]'::jsonb,
  calculado_em timestamptz NOT NULL,
  PRIMARY KEY (group_id, company_id)
);

CREATE INDEX IF NOT EXISTS carteira_prioridade_ordem_idx
  ON public.carteira_prioridade (group_id, posicao);

-- Só o Backend (papel do job) enxerga: a identidade e a checagem de
-- membro são feitas no endpoint, como nas demais rotas de /carteira.
ALTER TABLE public.prioridade_modelos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carteira_prioridade ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.prioridade_modelos TO crm_sync;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.carteira_prioridade TO crm_sync;

DROP POLICY IF EXISTS prioridade_modelos_all_crm_sync ON public.prioridade_modelos;
CREATE POLICY prioridade_modelos_all_crm_sync ON public.prioridade_modelos
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS carteira_prioridade_all_crm_sync ON public.carteira_prioridade;
CREATE POLICY carteira_prioridade_all_crm_sync ON public.carteira_prioridade
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);
