-- Catálogo de teses de recuperação tributária usado pelo diagnóstico dos
-- detalhes da empresa (`backend/app/services/tax_diagnosis/`).
--
-- O banco guarda o CONTEÚDO de cada tese: textos, base legal, situação
-- jurídica, perguntas para a visita e os CNAEs que a disparam. As CONDIÇÕES
-- (regime, janela de 5 anos, porte, compras públicas...) ficam no código
-- (`rules.py`), ligadas à tese pelo `id`. Assim o time jurídico/comercial
-- ajusta a redação, desliga uma tese ou muda a lista de CNAEs sem deploy.
--
--   teses_tributarias            1 linha por tese
--   teses_tributarias_perguntas  perguntas para validar na visita, em ordem
--   teses_tributarias_cnaes      CNAEs (7 dígitos) que disparam a tese
--
-- Catálogo global (não é dado de organização) e só o Backend lê (papel
-- crm_sync); o app recebe o diagnóstico pronto pela rota
-- /diagnostico/tributario, que confere acesso antes.
--
-- Idempotente: o conteúdo inicial entra com ON CONFLICT DO NOTHING, então
-- reaplicar o arquivo não desfaz edições feitas no banco.

CREATE TABLE IF NOT EXISTS public.teses_tributarias (
  id text PRIMARY KEY,
  titulo text NOT NULL,
  resumo text NOT NULL,
  tributos text[] NOT NULL DEFAULT '{}',
  base_legal text NOT NULL,
  situacao_juridica text NOT NULL,
  -- tese ainda em discussão nos tribunais: só vira a principal sem outra
  em_discussao boolean NOT NULL DEFAULT false,
  como_abordar text NOT NULL,
  ativa boolean NOT NULL DEFAULT true,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.teses_tributarias_perguntas (
  tese_id text NOT NULL REFERENCES public.teses_tributarias(id) ON DELETE CASCADE,
  ordem smallint NOT NULL,
  texto text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tese_id, ordem)
);

CREATE TABLE IF NOT EXISTS public.teses_tributarias_cnaes (
  tese_id text NOT NULL REFERENCES public.teses_tributarias(id) ON DELETE CASCADE,
  cnae char(7) NOT NULL CHECK (cnae ~ '^[0-9]{7}$'),
  -- o que a empresa revende com esse CNAE (aparece na evidência)
  descricao text NOT NULL,
  -- só parte das vendas se encaixa (ex.: supermercado no monofásico): confiança menor
  parcial boolean NOT NULL DEFAULT false,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tese_id, cnae)
);

-- Qualquer edição renova `atualizado_em`: o diagnóstico usa o maior valor
-- das três tabelas como versão do catálogo.
CREATE OR REPLACE FUNCTION public.teses_tributarias_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS teses_tributarias_touch ON public.teses_tributarias;
CREATE TRIGGER teses_tributarias_touch BEFORE UPDATE ON public.teses_tributarias
  FOR EACH ROW EXECUTE FUNCTION public.teses_tributarias_touch();
DROP TRIGGER IF EXISTS teses_tributarias_perguntas_touch ON public.teses_tributarias_perguntas;
CREATE TRIGGER teses_tributarias_perguntas_touch BEFORE UPDATE ON public.teses_tributarias_perguntas
  FOR EACH ROW EXECUTE FUNCTION public.teses_tributarias_touch();
DROP TRIGGER IF EXISTS teses_tributarias_cnaes_touch ON public.teses_tributarias_cnaes;
CREATE TRIGGER teses_tributarias_cnaes_touch BEFORE UPDATE ON public.teses_tributarias_cnaes
  FOR EACH ROW EXECUTE FUNCTION public.teses_tributarias_touch();

ALTER TABLE public.teses_tributarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teses_tributarias_perguntas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teses_tributarias_cnaes ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.teses_tributarias TO crm_sync;
GRANT SELECT ON public.teses_tributarias_perguntas TO crm_sync;
GRANT SELECT ON public.teses_tributarias_cnaes TO crm_sync;

DROP POLICY IF EXISTS teses_tributarias_select_crm_sync ON public.teses_tributarias;
CREATE POLICY teses_tributarias_select_crm_sync ON public.teses_tributarias
  FOR SELECT TO crm_sync USING (true);
DROP POLICY IF EXISTS teses_tributarias_perguntas_select_crm_sync ON public.teses_tributarias_perguntas;
CREATE POLICY teses_tributarias_perguntas_select_crm_sync ON public.teses_tributarias_perguntas
  FOR SELECT TO crm_sync USING (true);
DROP POLICY IF EXISTS teses_tributarias_cnaes_select_crm_sync ON public.teses_tributarias_cnaes;
CREATE POLICY teses_tributarias_cnaes_select_crm_sync ON public.teses_tributarias_cnaes
  FOR SELECT TO crm_sync USING (true);

-- ─── Conteúdo inicial ──────────────────────────────────────────────────

INSERT INTO public.teses_tributarias
  (id, titulo, resumo, tributos, base_legal, situacao_juridica, em_discussao, como_abordar)
VALUES
  ('monofasico_simples',
   'PIS/COFINS monofásico pago de novo no Simples',
   'Quem revende produto monofásico (medicamentos, cosméticos, autopeças, bebidas, combustíveis) já teve o PIS/COFINS cobrado na indústria. No Simples, essa receita precisa ser segregada no PGDAS-D; quando não é, a empresa paga PIS/COFINS em duplicidade dentro do DAS.',
   '{PIS,COFINS}',
   'LC 123/2006, art. 18, §4º-A; Leis 10.147/2000 (higiene e farmacêuticos), 10.485/2002 (autopeças), 13.097/2015 (bebidas) e 9.718/1998 (combustíveis)',
   'Pacificada (previsão legal expressa)',
   false,
   'Abordagem direta e de baixo risco: a recuperação é administrativa (retificação do PGDAS-D dos últimos 5 anos), sem ação judicial. Ofereça uma análise gratuita das apurações para estimar o valor.'),
  ('icms_st_simples',
   'ICMS-ST pago de novo no DAS',
   'Produtos com substituição tributária chegam com o ICMS já recolhido pelo fornecedor. No Simples, a revenda deve ser informada como ''com ST'' no PGDAS-D; sem isso, o ICMS é cobrado outra vez no DAS.',
   '{ICMS}',
   'LC 123/2006, art. 18, §4º-A, I, e §14',
   'Pacificada (previsão legal expressa)',
   false,
   'Mostre que o erro é comum em varejo com mix grande de produtos e que a correção é por retificação do PGDAS-D. Proponha cruzar as notas de compra (CST/CSOSN de ST) com o que foi declarado.'),
  ('icms_base_pis_cofins',
   'ICMS na base do PIS/COFINS',
   'O STF decidiu que o ICMS destacado na nota não compõe a receita e deve sair da base do PIS/COFINS. Empresas do Lucro Presumido ou Real que vendem mercadorias e ainda não fazem a exclusão pagam a mais.',
   '{PIS,COFINS}',
   'STF, RE 574.706 (Tema 69); modulação a partir de 15/03/2017',
   'Pacificada pelo STF',
   false,
   'Tese conhecida: comece perguntando se a empresa já exclui o ICMS. Muitas ainda não fazem a exclusão em todos os períodos ou calculam pelo ICMS a recolher em vez do destacado.'),
  ('insumos_lucro_real',
   'Créditos de PIS/COFINS sobre insumos',
   'No Lucro Real (regime não cumulativo), tudo o que é essencial ou relevante para a atividade gera crédito de PIS/COFINS. Despesas como EPIs, manutenção, fretes e embalagens costumam ficar de fora.',
   '{PIS,COFINS}',
   'Leis 10.637/2002 e 10.833/2003, art. 3º; STJ, REsp 1.221.170 (Temas 779 e 780)',
   'Pacificada pelo STJ (critério da essencialidade e relevância)',
   false,
   'Fale de margem: créditos não tomados são custo a mais. Proponha um levantamento das despesas operacionais que não geraram crédito nos últimos 5 anos.'),
  ('retencoes_orgaos_publicos',
   'Retenções em vendas ao governo não compensadas',
   'Órgãos públicos retêm tributos no pagamento a fornecedores (os federais: IR, CSLL, PIS e COFINS; estados e municípios: IR). Quando a empresa não compensa essas retenções na apuração, fica com crédito parado.',
   '{IRPJ,CSLL,PIS,COFINS}',
   'Lei 9.430/1996, art. 64; IN RFB 1.234/2012; STF, Tema 1.130',
   'Pacificada (previsão legal expressa)',
   false,
   'A empresa vende ao governo, então tem retenções. Proponha conciliar os informes de rendimentos dos órgãos com o que foi deduzido nas apurações (DCTF/PER-DCOMP).'),
  ('iss_base_pis_cofins',
   'ISS na base do PIS/COFINS',
   'Mesma lógica da exclusão do ICMS, aplicada ao ISS dos prestadores de serviço no Lucro Presumido ou Real. A tese ainda depende do STF.',
   '{PIS,COFINS}',
   'STF, RE 592.616 (Tema 118)',
   'Em discussão no STF: exige ação judicial e tem risco',
   true,
   'Apresente como oportunidade judicial, com risco. Funciona melhor como complemento de outra tese do que como abordagem principal.'),
  ('verbas_indenizatorias',
   'Contribuição previdenciária sobre verbas indenizatórias',
   'Algumas verbas pagas aos empregados não são salário (como aviso prévio indenizado e os 15 primeiros dias de afastamento por doença) e não deveriam entrar na base do INSS patronal.',
   '{INSS patronal}',
   'Lei 8.212/1991, art. 22; STJ, REsp 1.230.957 (Temas 478 e 738)',
   'Pacificada no STJ para algumas verbas; outras dependem de ação',
   false,
   'Relevante para empresas com folha grande. Peça a relação das rubricas da folha para separar as indenizatórias.')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.teses_tributarias_perguntas (tese_id, ordem, texto) VALUES
  ('monofasico_simples', 1, 'Na apuração do DAS, a contabilidade separa as receitas de produtos monofásicos?'),
  ('monofasico_simples', 2, 'Que parte do faturamento vem desses produtos?'),
  ('monofasico_simples', 3, 'Alguém já revisou os PGDAS-D dos últimos 5 anos?'),
  ('icms_st_simples', 1, 'Vocês compram produtos com ICMS retido pelo fornecedor?'),
  ('icms_st_simples', 2, 'O sistema de vendas marca os itens com substituição tributária?'),
  ('icms_base_pis_cofins', 1, 'Vocês já excluem o ICMS destacado da base do PIS/COFINS?'),
  ('icms_base_pis_cofins', 2, 'Desde quando? Os 5 anos anteriores foram recuperados?'),
  ('insumos_lucro_real', 1, 'Quais despesas de produção/operação hoje geram crédito de PIS/COFINS?'),
  ('insumos_lucro_real', 2, 'Fretes, manutenção, EPIs e embalagens entram no cálculo?'),
  ('retencoes_orgaos_publicos', 1, 'As retenções feitas pelos órgãos são deduzidas na apuração de cada mês?'),
  ('retencoes_orgaos_publicos', 2, 'Existe saldo negativo de IRPJ/CSLL dos últimos anos sem pedido de restituição?'),
  ('iss_base_pis_cofins', 1, 'A empresa tem ação judicial sobre o ISS na base do PIS/COFINS?'),
  ('iss_base_pis_cofins', 2, 'Qual o ISS recolhido por ano, aproximadamente?'),
  ('verbas_indenizatorias', 1, 'Quantos empregados a empresa tem?'),
  ('verbas_indenizatorias', 2, 'A folha já exclui alguma verba da base do INSS patronal?')
ON CONFLICT (tese_id, ordem) DO NOTHING;

INSERT INTO public.teses_tributarias_cnaes (tese_id, cnae, descricao, parcial) VALUES
  -- Revenda de produtos monofásicos
  ('monofasico_simples', '4771701', 'medicamentos', false),
  ('monofasico_simples', '4771702', 'medicamentos', false),
  ('monofasico_simples', '4771703', 'medicamentos', false),
  ('monofasico_simples', '4772500', 'cosméticos e perfumaria', false),
  ('monofasico_simples', '4530701', 'autopeças', false),
  ('monofasico_simples', '4530702', 'pneus', false),
  ('monofasico_simples', '4530703', 'autopeças', false),
  ('monofasico_simples', '4530705', 'pneus', false),
  ('monofasico_simples', '4723700', 'bebidas', false),
  ('monofasico_simples', '4635401', 'bebidas', false),
  ('monofasico_simples', '4635402', 'bebidas', false),
  ('monofasico_simples', '4635499', 'bebidas', false),
  ('monofasico_simples', '4731800', 'combustíveis', false),
  ('monofasico_simples', '4732600', 'lubrificantes', false),
  ('monofasico_simples', '4681801', 'combustíveis', false),
  ('monofasico_simples', '4644301', 'medicamentos', false),
  ('monofasico_simples', '4646001', 'cosméticos e perfumaria', false),
  ('monofasico_simples', '4646002', 'produtos de higiene', false),
  -- Varejo de mix amplo: só parte das vendas é monofásica
  ('monofasico_simples', '4711301', 'supermercado (bebidas, higiene e cosméticos)', true),
  ('monofasico_simples', '4711302', 'supermercado (bebidas, higiene e cosméticos)', true),
  ('monofasico_simples', '4712100', 'minimercado (bebidas, higiene e cosméticos)', true),
  -- Comércio de mercadorias tipicamente sujeitas a ICMS-ST
  ('icms_st_simples', '4741500', 'tintas', false),
  ('icms_st_simples', '4742300', 'material elétrico', false),
  ('icms_st_simples', '4743100', 'vidros', false),
  ('icms_st_simples', '4744001', 'ferragens', false),
  ('icms_st_simples', '4744003', 'materiais hidráulicos', false),
  ('icms_st_simples', '4744004', 'cal, areia e pedra', false),
  ('icms_st_simples', '4744005', 'materiais de construção', false),
  ('icms_st_simples', '4744099', 'materiais de construção', false),
  ('icms_st_simples', '4672900', 'ferragens', false),
  ('icms_st_simples', '4679699', 'materiais de construção', false),
  ('icms_st_simples', '4530703', 'autopeças', false),
  ('icms_st_simples', '4530705', 'pneus', false),
  ('icms_st_simples', '4723700', 'bebidas', false),
  ('icms_st_simples', '4751201', 'equipamentos de informática', false),
  ('icms_st_simples', '4752100', 'telefonia', false),
  ('icms_st_simples', '4753900', 'eletrodomésticos', false),
  ('icms_st_simples', '4763601', 'brinquedos', false),
  ('icms_st_simples', '4771701', 'medicamentos', false),
  ('icms_st_simples', '4772500', 'cosméticos e perfumaria', false),
  ('icms_st_simples', '4711301', 'supermercado', false),
  ('icms_st_simples', '4711302', 'supermercado', false),
  ('icms_st_simples', '4712100', 'minimercado', false)
ON CONFLICT (tese_id, cnae) DO NOTHING;

NOTIFY pgrst, 'reload schema';
