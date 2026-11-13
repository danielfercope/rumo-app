-- Testes de isolamento entre organizações (015_isolamento_organizacao.sql).
-- Roda como o PostgREST roda: SET ROLE web_user + claim "sub" do usuário.
-- Tudo dentro de uma transação que termina em ROLLBACK: não deixa dados.
-- Uso: make test-db   (sobe um Postgres descartável com o schema inteiro)
\set ON_ERROR_STOP on
\set QUIET on
BEGIN;

CREATE SCHEMA t;
CREATE FUNCTION t.ok(cond boolean, msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF cond IS NOT TRUE THEN RAISE EXCEPTION 'FALHOU: %', msg; END IF;
END $$;
-- executa um comando e exige que ele falhe com uma mensagem contendo `fragment`
CREATE FUNCTION t.raises(stmt text, fragment text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF position(fragment IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'FALHOU: erro inesperado em [%]: %', stmt, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FALHOU: deveria ter dado erro: %', stmt;
END $$;
GRANT USAGE ON SCHEMA t TO web_user, crm_sync;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO web_user, crm_sync;

-- ── Cenário ─────────────────────────────────────────────────────────────────
--   u1  admin da organização g1        u2  admin da organização g2
--   u3  SEM organização                u4  membro comum de g1 (departamento Vendas)
INSERT INTO public.profiles (id, email, nome, departamento, nivel_acesso) VALUES
  ('u1', 'u1@x', 'U1', 'Gestão', 'user'),
  ('u2', 'u2@x', 'U2', 'Gestão', 'user'),
  ('u3', 'u3@x', 'U3', 'Gestão', 'user'),
  ('u4', 'u4@x', 'U4', 'Vendas', 'user');
INSERT INTO public.groups (id, name, invite_hash, created_by) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'G1', 'hash-g1', 'u1'),
  ('00000000-0000-0000-0000-0000000000a2', 'G2', 'hash-g2', 'u2');
INSERT INTO public.group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'u1', 'admin'),
  ('00000000-0000-0000-0000-0000000000a1', 'u4', 'member'),
  ('00000000-0000-0000-0000-0000000000a2', 'u2', 'admin');
INSERT INTO public.companies (id, cnpj, razao_social, uf, produto, latitude, longitude) VALUES
  ('00000000-0000-0000-0000-0000000000c1', '11111111000111', 'Empresa G1 a', 'SC', NULL,          -26.48, -49.07),
  ('00000000-0000-0000-0000-0000000000c2', '22222222000122', 'Empresa G1 b', 'SC', NULL,          -26.49, -49.08),
  ('00000000-0000-0000-0000-0000000000c3', '33333333000133', 'Empresa G2',   'RS', 'SEGREDO-G2',  -30.03, -51.22),
  ('00000000-0000-0000-0000-0000000000c4', '44444444000144', 'Empresa orfa', 'PR', NULL,          -25.43, -49.27);
INSERT INTO public.carteira_empresas (group_id, company_id, status, origem) VALUES
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'cliente', 'crm'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c2', 'lead',    'crm'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000c3', 'lead',    'crm');
INSERT INTO public.company_financial_profile (company_id, faixa_faturamento) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'ate 1M'),
  ('00000000-0000-0000-0000-0000000000c3', 'segredo G2');
INSERT INTO public.company_contacts (company_id, contact_type, value) VALUES
  ('00000000-0000-0000-0000-0000000000c3', 'phone', '47 99999-0000');
INSERT INTO public.company_crm_sync (company_id, sync_status) VALUES
  ('00000000-0000-0000-0000-0000000000c3', 'ok');

-- ═══ u3: usuário SEM organização não enxerga nada ═══════════════════════════
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u3"}', true);
SELECT t.ok((SELECT count(*) FROM public.companies) = 0, 'u3 (sem organização) não pode ver NENHUMA empresa');
SELECT t.ok((SELECT count(*) FROM public.company_financial_profile) = 0, 'u3 não vê perfil financeiro');
SELECT t.ok((SELECT count(*) FROM public.company_contacts) = 0, 'u3 não vê contatos');
SELECT t.ok((SELECT count(*) FROM public.company_crm_sync) = 0, 'u3 não vê vínculos de CRM');
SELECT t.raises($$SELECT * FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a1')$$, 'não pertence');
SELECT t.raises($$SELECT * FROM public.search_companies()$$, 'Selecione uma organização');
SELECT t.raises($$SELECT public.register_company('00000000-0000-0000-0000-0000000000a1', '{"cnpj":"55555555000155","latitude":1,"longitude":1}'::jsonb)$$, 'não pertence');
SELECT t.raises($$SELECT public.portfolio_has_cnpj('00000000-0000-0000-0000-0000000000a1', '11111111000111')$$, 'não pertence');
SELECT t.ok(public.get_filter_options() = '{"segments":[],"products":[],"states":[],"cnaes":[],"state_to_cities":{}}'::jsonb, 'u3 não vê opções de filtro');
RESET ROLE;

-- ═══ u1 (admin de g1): só a carteira de g1 ══════════════════════════════════
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u1"}', true);
SELECT t.ok((SELECT count(*) FROM public.companies) = 2, 'u1 vê só as 2 empresas de g1');
SELECT t.ok(NOT EXISTS (SELECT 1 FROM public.companies WHERE cnpj IN ('33333333000133','44444444000144')), 'u1 não vê empresa de g2 nem a órfã');
SELECT t.ok((SELECT count(*) FROM public.company_financial_profile) = 1, 'u1 vê só o perfil financeiro de g1');
SELECT t.ok((SELECT count(*) FROM public.company_contacts) = 0, 'u1 não vê contatos de g2');
SELECT t.ok((SELECT count(*) FROM public.company_crm_sync) = 0, 'u1 não vê vínculo de CRM de g2');
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a1')) = 2, 'busca de g1 devolve 2');
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a1', p_is_client := true)) = 1, 'filtro cliente usa a carteira');
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_query := '33333333000133', p_group_id := '00000000-0000-0000-0000-0000000000a1')) = 0, 'busca por CNPJ de g2 não acha nada');
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_query := 'G2', p_group_id := '00000000-0000-0000-0000-0000000000a1')) = 0, 'busca por nome de g2 não acha nada');
SELECT t.raises($$SELECT * FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a2')$$, 'não pertence');
SELECT t.raises($$SELECT * FROM public.search_companies()$$, 'Selecione uma organização');
-- escrita direta é negada
SELECT t.raises($$INSERT INTO public.companies (cnpj, latitude, longitude) VALUES ('99999999000199', 0, 0)$$, 'permission denied');
SELECT t.raises($$UPDATE public.companies SET razao_social = 'hack'$$, 'permission denied');
SELECT t.raises($$DELETE FROM public.companies$$, 'permission denied');
SELECT t.raises($$INSERT INTO public.company_contacts (company_id, contact_type, value) VALUES ('00000000-0000-0000-0000-0000000000c1', 'phone', '1')$$, 'permission denied');
SELECT t.raises($$UPDATE public.company_financial_profile SET faixa_faturamento = 'x'$$, 'permission denied');
SELECT t.raises($$INSERT INTO public.company_crm_sync (company_id) VALUES ('00000000-0000-0000-0000-0000000000c1')$$, 'permission denied');
-- opções de filtro: só o que u1 pode ver
SELECT t.ok(public.get_filter_options() -> 'states' = '["SC"]'::jsonb, 'filtros de u1 só têm SC');
SELECT t.ok(public.get_filter_options() -> 'products' = '[]'::jsonb, 'filtros de u1 não vazam produto de g2');
-- não há oráculo de CNPJ
SELECT t.ok(public.portfolio_has_cnpj('00000000-0000-0000-0000-0000000000a1', '11.111.111/0001-11'), 'CNPJ de g1 está na carteira de g1 (aceita máscara)');
SELECT t.ok(NOT public.portfolio_has_cnpj('00000000-0000-0000-0000-0000000000a1', '33333333000133'), 'CNPJ que só g2 tem aparece como "não existe" pra g1');
SELECT t.raises($$SELECT public.portfolio_has_cnpj('00000000-0000-0000-0000-0000000000a2', '33333333000133')$$, 'não pertence');
-- cadastro manual entra na carteira DE g1
SELECT t.ok((public.register_company('00000000-0000-0000-0000-0000000000a1',
   '{"cnpj":"55.555.555/0001-55","razao_social":"Nova G1","uf":"SC","latitude":-26.5,"longitude":-49.1}'::jsonb) ->> 'already_in_portfolio')::boolean = false, 'primeiro cadastro cria o vínculo');
SELECT t.ok((public.register_company('00000000-0000-0000-0000-0000000000a1',
   '{"cnpj":"55555555000155","razao_social":"Nova G1","latitude":-26.5,"longitude":-49.1}'::jsonb) ->> 'already_in_portfolio')::boolean = true, 'repetir o cadastro avisa que já está na carteira');
SELECT t.ok((SELECT count(*) FROM public.companies WHERE cnpj = '55555555000155') = 1, 'u1 vê a empresa que cadastrou');
SELECT t.ok((SELECT status_carteira FROM public.search_companies(p_query := '55555555000155', p_group_id := '00000000-0000-0000-0000-0000000000a1')) = 'lead', 'cadastro manual entra como lead');
SELECT t.raises($$SELECT public.register_company('00000000-0000-0000-0000-0000000000a2', '{"cnpj":"66666666000166","latitude":1,"longitude":1}'::jsonb)$$, 'não pertence');
SELECT t.raises($$SELECT public.register_company('00000000-0000-0000-0000-0000000000a1', '{"cnpj":"123","latitude":1,"longitude":1}'::jsonb)$$, 'CNPJ inválido');
-- CNPJ que já existe no catálogo (de g2): vincula a g1 SEM sobrescrever o dado
SELECT t.ok((public.register_company('00000000-0000-0000-0000-0000000000a1',
   '{"cnpj":"33333333000133","razao_social":"SOBRESCRITA","uf":"AC","latitude":0,"longitude":0}'::jsonb) ->> 'already_in_portfolio')::boolean = false, 'empresa existente é vinculada a g1');
SELECT t.ok((SELECT razao_social FROM public.companies WHERE cnpj = '33333333000133') = 'Empresa G2', 'dado do catálogo não foi sobrescrito por g1');
RESET ROLE;

-- ═══ u4: membro de g1 SEM permissão de cadastro: vê, mas não cadastra ═══════
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u4"}', true);
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a1')) >= 2, 'u4 (membro) busca na carteira de g1');
SELECT t.raises($$SELECT public.register_company('00000000-0000-0000-0000-0000000000a1', '{"cnpj":"77777777000177","latitude":1,"longitude":1}'::jsonb)$$, 'Sem permissão');
RESET ROLE;

-- ═══ u2 (admin de g2): nada do que g1 cadastrou vaza pra g2 ═════════════════
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u2"}', true);
SELECT t.ok((SELECT count(*) FROM public.companies) = 1, 'u2 só vê a empresa de g2');
SELECT t.ok(NOT EXISTS (SELECT 1 FROM public.companies WHERE cnpj IN ('11111111000111','22222222000122','55555555000155')), 'u2 não vê nada de g1, nem o que g1 cadastrou');
SELECT t.ok((SELECT count(*) FROM public.company_contacts) = 1, 'u2 vê os contatos da própria empresa');
SELECT t.ok(public.get_filter_options() -> 'products' = '["SEGREDO-G2"]'::jsonb, 'u2 vê as opções de g2');
RESET ROLE;

-- ═══ histórico de deslocamento (016_tracking_history.sql) ═══════════════════
INSERT INTO public.tracking_history (user_id, latitude, longitude, captured_at) VALUES
  ('u4', -26.30, -48.84, '2026-11-10 12:00+00'),
  ('u4', -26.31, -48.85, '2026-11-10 11:00+00'),
  ('u4', -26.32, -48.86, '2026-11-12 11:00+00'),
  ('u2', -30.03, -51.22, '2026-11-10 12:00+00');

-- g1 ainda com rastreamento desligado: nem o admin lê
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u1"}', true);
SELECT t.raises($$SELECT * FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u4','2026-11-10 00:00+00','2026-11-11 00:00+00')$$, 'desativado');
RESET ROLE;

UPDATE public.groups SET tracking_enabled = true WHERE id = '00000000-0000-0000-0000-0000000000a1';

SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u1"}', true);
SELECT t.ok((SELECT count(*) FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u4','2026-11-10 00:00+00','2026-11-11 00:00+00')) = 2, 'admin de g1 vê o trajeto do dia, só dentro do período');
SELECT t.ok((SELECT latitude FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u4','2026-11-10 00:00+00','2026-11-11 00:00+00') LIMIT 1) = -26.31, 'trajeto em ordem cronológica');
SELECT t.raises($$SELECT * FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u2','2026-11-10 00:00+00','2026-11-11 00:00+00')$$, 'não pertence');
SELECT t.raises($$SELECT * FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u4','2026-01-01 00:00+00','2026-11-11 00:00+00')$$, '31 dias');
RESET ROLE;

SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u4"}', true);
SELECT t.raises($$SELECT * FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u4','2026-11-10 00:00+00','2026-11-11 00:00+00')$$, 'administradores');
RESET ROLE;
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u2"}', true);
SELECT t.raises($$SELECT * FROM public.list_group_tracking_history('00000000-0000-0000-0000-0000000000a1','u4','2026-11-10 00:00+00','2026-11-11 00:00+00')$$, 'administradores');
RESET ROLE;

-- ═══ o Backend (crm_sync) continua enxergando tudo pra sincronizar ══════════
SET LOCAL ROLE crm_sync;
SELECT t.ok((SELECT count(*) FROM public.companies) >= 5, 'crm_sync (Backend) segue lendo o catálogo inteiro');
RESET ROLE;

-- ═══ CRM de uma organização: o que o Backend importa pertence SÓ a ela ═════
-- (o Backend grava como crm_sync: empresa no catálogo + linha na carteira de g2)
SET LOCAL ROLE crm_sync;
INSERT INTO public.companies (id, cnpj, razao_social, uf, latitude, longitude)
  VALUES ('00000000-0000-0000-0000-0000000000d1', '88888888000188', 'Importada do CRM de G2', 'RS', -30.1, -51.3);
INSERT INTO public.carteira_empresas (group_id, company_id, status, origem)
  VALUES ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000d1', 'cliente', 'crm');
RESET ROLE;

SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u2"}', true);
SELECT t.ok(EXISTS (SELECT 1 FROM public.companies WHERE cnpj = '88888888000188'), 'quem conectou o CRM (g2) vê as empresas importadas');
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a2', p_query := '88888888000188')) = 1, 'e acha na busca da própria organização');
RESET ROLE;
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u1"}', true);
SELECT t.ok(NOT EXISTS (SELECT 1 FROM public.companies WHERE cnpj = '88888888000188'), 'g1 NÃO vê as empresas que o CRM de g2 importou');
SELECT t.ok((SELECT count(*) FROM public.search_companies(p_group_id := '00000000-0000-0000-0000-0000000000a1', p_query := '88888888000188')) = 0, 'nem na busca');
RESET ROLE;
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{"sub":"u3"}', true);
SELECT t.ok((SELECT count(*) FROM public.companies) = 0, 'sem organização continua vendo 0, mesmo depois de uma importação');
RESET ROLE;

ROLLBACK;
\echo OK: isolamento entre organizações verificado
