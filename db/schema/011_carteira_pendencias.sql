-- Fila de retentativas da sincronização por conexão (CarteiraSyncService).
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).
--
-- Análoga a crm_sync_pending (008), que é de conta única e usa só o ID do
-- objeto do CRM como chave — o que colidiria entre duas contas de CRM. Aqui a
-- chave inclui a conexão. Guarda também o status mapeado, pra a retentativa
-- conseguir gravar a carteira sem reconsultar o CRM.

CREATE TABLE IF NOT EXISTS public.carteira_pendencias (
  conexao_id uuid NOT NULL REFERENCES public.crm_conexoes(id) ON DELETE CASCADE,
  crm_object_id text NOT NULL,
  cnpj text NOT NULL,
  status text NOT NULL CHECK (status IN ('cliente', 'lead', 'perdido')),
  attempts integer NOT NULL DEFAULT 1,
  last_error text,
  next_retry_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conexao_id, crm_object_id)
);

CREATE INDEX IF NOT EXISTS carteira_pendencias_retry_idx
  ON public.carteira_pendencias (conexao_id, next_retry_at);

-- Tabela de controle interna: só o papel do job enxerga (nem web_user nem web_anon).
ALTER TABLE public.carteira_pendencias ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.carteira_pendencias TO crm_sync;

DROP POLICY IF EXISTS carteira_pendencias_all_crm_sync ON public.carteira_pendencias;
CREATE POLICY carteira_pendencias_all_crm_sync ON public.carteira_pendencias
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);
