-- Operação ÚNICA, manual: associa à organização :group_id as empresas que hoje não
-- estão na carteira de NENHUMA organização (a base anterior ao isolamento, importada
-- pelo sync antigo de conta única ou cadastrada antes das organizações).
--
-- Depois de 015_isolamento_organizacao.sql, uma empresa sem linha em
-- carteira_empresas fica invisível pra todo mundo. Rode isto pra devolver a base
-- à organização dona dela.
--
-- Não toca em empresa que já esteja na carteira de qualquer organização.
-- Status: 'cliente' se o flag antigo companies.is_client era verdadeiro; senão 'lead'.
-- origem = 'manual' (e não 'crm') pra desconectar um CRM com "apagar a carteira
-- importada" nunca apagar esta base.
--
-- Uso:  psql -U postgres -d rumo -v group_id=<uuid-da-organizacao> -f db/ops/assign_legacy_companies.sql
-- Rode antes com :dry_run=1 pra só contar:  -v dry_run=1
\set ON_ERROR_STOP on
\if :{?dry_run}
\else
  \set dry_run 0
\endif

SELECT 'organização' AS alvo, g.id, g.name
FROM public.groups g WHERE g.id = :'group_id'::uuid;

SELECT 'empresas sem dono (serão associadas)' AS o_que, count(*) AS qtd
FROM public.companies c
WHERE NOT EXISTS (SELECT 1 FROM public.carteira_empresas x WHERE x.company_id = c.id);

\if :dry_run
  \echo DRY-RUN: nada foi alterado.
\else
  INSERT INTO public.carteira_empresas (group_id, company_id, status, origem)
  SELECT :'group_id'::uuid, c.id,
         CASE WHEN c.is_client IS TRUE THEN 'cliente' ELSE 'lead' END,
         'manual'
  FROM public.companies c
  WHERE NOT EXISTS (SELECT 1 FROM public.carteira_empresas x WHERE x.company_id = c.id)
  ON CONFLICT (group_id, company_id) DO NOTHING;
\endif
