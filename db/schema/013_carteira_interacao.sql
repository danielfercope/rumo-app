-- Sinais do CRM usados na priorização quando a organização ainda tem poucos
-- clientes (sem eles o modelo não tem o que aprender): há quanto tempo o
-- registro existe no CRM e quanta interação a empresa já teve com a equipe.
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).
--
-- Vêm de propriedades da própria EMPRESA no CRM (data de criação, última
-- atividade de vendas, nº de vezes contatada) — nenhum contato, nota ou
-- negócio é lido, então a minimização de dados (LGPD) continua valendo.

ALTER TABLE public.carteira_empresas
  ADD COLUMN IF NOT EXISTS crm_criado_em timestamptz,
  ADD COLUMN IF NOT EXISTS ultima_interacao_em timestamptz,
  ADD COLUMN IF NOT EXISTS num_interacoes integer;

-- A fila guarda os mesmos sinais pra retentativa gravar a carteira completa
-- sem reconsultar o CRM.
ALTER TABLE public.carteira_pendencias
  ADD COLUMN IF NOT EXISTS crm_criado_em timestamptz,
  ADD COLUMN IF NOT EXISTS ultima_interacao_em timestamptz,
  ADD COLUMN IF NOT EXISTS num_interacoes integer;
