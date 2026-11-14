-- Cache do enriquecimento dos detalhes da empresa (Receita, compras públicas,
-- comércio exterior do município, IBGE, Google).
--
-- Cada fonte externa é consultada sob demanda, quando alguém abre os detalhes,
-- e o resultado fica aqui por um tempo (o Backend decide a validade por fonte).
-- Assim a mesma empresa aberta por várias pessoas não repete chamadas a APIs
-- públicas com limite de uso, e uma fonte fora do ar ainda mostra o último dado.
--
-- `chave` é o CNPJ (fontes da empresa) ou o código IBGE do município (fontes
-- regionais, compartilhadas por todas as empresas da cidade). Só dado público.
-- Só o papel crm_sync (Backend) lê e grava; o app nunca acessa direto: a rota
-- confere antes se o CNPJ está na carteira da organização de quem pede.
--
-- Idempotente.

CREATE TABLE IF NOT EXISTS public.enriquecimento_cache (
  fonte text NOT NULL,
  chave text NOT NULL,
  dados jsonb NOT NULL,
  buscado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fonte, chave)
);

ALTER TABLE public.enriquecimento_cache ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.enriquecimento_cache TO crm_sync;

DROP POLICY IF EXISTS enriquecimento_cache_all_crm_sync ON public.enriquecimento_cache;
CREATE POLICY enriquecimento_cache_all_crm_sync ON public.enriquecimento_cache
  FOR ALL TO crm_sync USING (true) WITH CHECK (true);

-- O PostgREST guarda o esquema em cache: sem isto, a tabela/colunas novas
-- só aparecem pra ele depois de reiniciar.
NOTIFY pgrst, 'reload schema';
