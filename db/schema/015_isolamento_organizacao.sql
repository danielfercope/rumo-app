-- Isolamento entre organizações.
--
-- Antes: `companies` (e as tabelas satélite) eram legíveis por QUALQUER usuário
-- autenticado (policy USING (true)), e a escrita era liberada por departamento
-- (auto-declarado), sem olhar organização. Um usuário novo, sem organização,
-- via a base inteira — inclusive a carteira que outras organizações importaram.
--
-- Agora: uma empresa só é visível a quem é membro de uma organização que a tem
-- na carteira (`carteira_empresas`). `companies` continua sendo o catálogo
-- global de dados públicos (CNPJ, endereço, CNAE...), mas o ACESSO é sempre pela
-- carteira. Nada aqui apaga dados: empresas sem linha na carteira de ninguém
-- ficam invisíveis até serem associadas a uma organização (ver
-- db/ops/assign_legacy_companies.sql).
--
-- Escrita: o app deixa de gravar direto em `companies` e nas tabelas satélite;
-- o cadastro manual passa por `register_company`, que confere a organização.
-- Quem escreve de verdade (sincronização do CRM) é o papel crm_sync, com as
-- próprias policies (008), que não mudam.
--
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).

-- ── Visibilidade: "a empresa está na carteira de uma organização minha?" ────
-- SECURITY DEFINER pra não depender das RLS de carteira_empresas/group_members
-- dentro da policy (evita recursão e custo); auth_uid() lê o claim do request,
-- que o SECURITY DEFINER não altera.

CREATE OR REPLACE FUNCTION public.company_in_my_orgs(p_company_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.carteira_empresas ce
    JOIN public.group_members gm ON gm.group_id = ce.group_id
    WHERE ce.company_id = p_company_id
      AND gm.user_id = public.auth_uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.company_in_my_orgs(uuid) TO web_user;

-- ── companies ───────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS companies_select_all ON public.companies;
DROP POLICY IF EXISTS companies_insert_authorized ON public.companies;
DROP POLICY IF EXISTS companies_update_authorized ON public.companies;
DROP POLICY IF EXISTS companies_select_org ON public.companies;

CREATE POLICY companies_select_org ON public.companies
  FOR SELECT TO web_user USING (public.company_in_my_orgs(id));

REVOKE INSERT, UPDATE, DELETE ON public.companies FROM web_user;

-- ── tabelas satélite: leitura pela mesma regra; escrita só pelo Backend ─────

DROP POLICY IF EXISTS company_financial_profile_select_all ON public.company_financial_profile;
DROP POLICY IF EXISTS company_financial_profile_write_authorized ON public.company_financial_profile;
DROP POLICY IF EXISTS company_financial_profile_select_org ON public.company_financial_profile;
CREATE POLICY company_financial_profile_select_org ON public.company_financial_profile
  FOR SELECT TO web_user USING (public.company_in_my_orgs(company_id));
REVOKE INSERT, UPDATE, DELETE ON public.company_financial_profile FROM web_user;

DROP POLICY IF EXISTS company_contacts_select_all ON public.company_contacts;
DROP POLICY IF EXISTS company_contacts_write_authorized ON public.company_contacts;
DROP POLICY IF EXISTS company_contacts_select_org ON public.company_contacts;
CREATE POLICY company_contacts_select_org ON public.company_contacts
  FOR SELECT TO web_user USING (public.company_in_my_orgs(company_id));
REVOKE INSERT, UPDATE, DELETE ON public.company_contacts FROM web_user;

DROP POLICY IF EXISTS company_crm_sync_select_all ON public.company_crm_sync;
DROP POLICY IF EXISTS company_crm_sync_write_all ON public.company_crm_sync;
DROP POLICY IF EXISTS company_crm_sync_select_org ON public.company_crm_sync;
CREATE POLICY company_crm_sync_select_org ON public.company_crm_sync
  FOR SELECT TO web_user USING (public.company_in_my_orgs(company_id));
REVOKE INSERT, UPDATE, DELETE ON public.company_crm_sync FROM web_user;

-- ── Cadastro manual: a empresa entra na carteira DA organização ─────────────
-- Só membro da organização cadastra (e, como antes, quem é admin dela ou tem
-- permissão de cadastro). O CNPJ já existente no catálogo global NÃO é
-- sobrescrito: dado público de outra organização não é alterado por esta, e a
-- resposta não revela se a empresa já existia (nada de "oráculo" de CNPJ).

CREATE OR REPLACE FUNCTION public.register_company(p_group_id uuid, p_data jsonb)
RETURNS jsonb AS $$
DECLARE
  v_cnpj text := regexp_replace(coalesce(p_data ->> 'cnpj', ''), '\D', '', 'g');
  v_company_id uuid;
  v_linked integer;
BEGIN
  IF NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Você não pertence a esta organização' USING ERRCODE = '42501';
  END IF;
  IF NOT (public.is_group_admin(p_group_id) OR public.can_add_company()) THEN
    RAISE EXCEPTION 'Sem permissão para cadastrar empresas' USING ERRCODE = '42501';
  END IF;
  IF length(v_cnpj) <> 14 THEN
    RAISE EXCEPTION 'CNPJ inválido' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_company_id FROM public.companies WHERE cnpj = v_cnpj;

  IF v_company_id IS NULL THEN
    INSERT INTO public.companies (
      cnpj, razao_social, nome_fantasia, email_principal, url_company_page,
      telefone_principal, endereco_completo, tipo_logradouro, logradouro, numero,
      bairro, municipio, uf, cep, natureza_juridica, porte, situacao,
      data_abertura, cnae_principal, latitude, longitude, precisao_geocodificacao
    ) VALUES (
      v_cnpj,
      p_data ->> 'razao_social',
      p_data ->> 'nome_fantasia',
      p_data ->> 'email_principal',
      p_data ->> 'url_company_page',
      p_data ->> 'telefone_principal',
      p_data ->> 'endereco_completo',
      p_data ->> 'tipo_logradouro',
      p_data ->> 'logradouro',
      p_data ->> 'numero',
      p_data ->> 'bairro',
      p_data ->> 'municipio',
      p_data ->> 'uf',
      p_data ->> 'cep',
      p_data ->> 'natureza_juridica',
      p_data ->> 'porte',
      p_data ->> 'situacao',
      NULLIF(p_data ->> 'data_abertura', '')::date,
      p_data ->> 'cnae_principal',
      (p_data ->> 'latitude')::double precision,
      (p_data ->> 'longitude')::double precision,
      p_data ->> 'precisao_geocodificacao'
    )
    ON CONFLICT (cnpj) DO NOTHING
    RETURNING id INTO v_company_id;

    -- corrida: outra transação criou o mesmo CNPJ entre o SELECT e o INSERT
    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM public.companies WHERE cnpj = v_cnpj;
    END IF;
  END IF;

  INSERT INTO public.carteira_empresas (group_id, company_id, status, origem)
  VALUES (p_group_id, v_company_id, 'lead', 'manual')
  ON CONFLICT (group_id, company_id) DO NOTHING;
  GET DIAGNOSTICS v_linked = ROW_COUNT;

  RETURN jsonb_build_object(
    'company_id', v_company_id,
    'already_in_portfolio', v_linked = 0
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.register_company(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_company(uuid, jsonb) TO web_user;

-- "Este CNPJ já está na carteira da minha organização?" — só olha a carteira
-- dela, então não dá pra descobrir se a empresa existe em outra organização.

CREATE OR REPLACE FUNCTION public.portfolio_has_cnpj(p_group_id uuid, p_cnpj text)
RETURNS boolean AS $$
BEGIN
  IF NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Você não pertence a esta organização' USING ERRCODE = '42501';
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.carteira_empresas ce
    JOIN public.companies c ON c.id = ce.company_id
    WHERE ce.group_id = p_group_id
      AND c.cnpj = regexp_replace(coalesce(p_cnpj, ''), '\D', '', 'g')
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.portfolio_has_cnpj(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portfolio_has_cnpj(uuid, text) TO web_user;

-- ── Busca: só a carteira da organização ─────────────────────────────────────
-- Mesma assinatura da 010 (CREATE OR REPLACE, sem sobrecarga). Mudou o
-- contrato: p_group_id é OBRIGATÓRIO (sem organização, não há busca), e o
-- universo é a carteira dela — não mais "todas as empresas".

CREATE OR REPLACE FUNCTION public.search_companies(
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_radius_km double precision DEFAULT 5,
  p_query text DEFAULT NULL,
  p_segment text DEFAULT NULL,
  p_product text DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_cnae text DEFAULT NULL,
  p_is_client boolean DEFAULT NULL,
  p_limit integer DEFAULT 200,
  p_group_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  nome_da_empresa text,
  nome_fantasia text,
  segmento text,
  endereco_completo text,
  latitude double precision,
  longitude double precision,
  cliente boolean,
  cnpj text,
  cnae_principal text,
  telefone_principal text,
  email_principal text,
  porte_da_empresa text,
  faixa_de_faturamento text,
  faixa_de_funcionarios text,
  situacao text,
  data_de_abertura date,
  natureza_juridica text,
  divida_ativa_da_uniao text,
  saude_tributaria text,
  score_propensao text,
  produto text,
  distance_km double precision,
  status_carteira text
) AS $$
DECLARE
  v_point geography;
  v_cnpj_digits text;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'Selecione uma organização' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Você não pertence a esta organização' USING ERRCODE = '42501';
  END IF;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
    v_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;
  END IF;

  IF p_query IS NOT NULL THEN
    v_cnpj_digits := regexp_replace(p_query, '\D', '', 'g');
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.razao_social,
    c.nome_fantasia,
    c.segmento,
    c.endereco_completo,
    c.latitude,
    c.longitude,
    ct.status = 'cliente',
    c.cnpj,
    c.cnae_principal,
    c.telefone_principal,
    c.email_principal,
    c.porte,
    f.faixa_faturamento,
    f.faixa_funcionarios,
    c.situacao,
    c.data_abertura,
    c.natureza_juridica,
    f.divida_ativa_uniao,
    f.saude_tributaria,
    f.score_propensao,
    c.produto,
    CASE WHEN v_point IS NOT NULL THEN ST_Distance(c.geom, v_point) / 1000.0 END AS distance_km,
    ct.status
  FROM public.carteira_empresas ct
  JOIN public.companies c ON c.id = ct.company_id
  LEFT JOIN public.company_financial_profile f ON f.company_id = c.id
  WHERE
    ct.group_id = p_group_id
    AND (v_point IS NULL OR ST_DWithin(c.geom, v_point, p_radius_km * 1000))
    AND (
      p_query IS NULL
      OR c.razao_social ILIKE '%' || p_query || '%'
      OR c.nome_fantasia ILIKE '%' || p_query || '%'
      OR (v_cnpj_digits <> '' AND c.cnpj = v_cnpj_digits)
    )
    AND (p_segment IS NULL OR c.segmento = p_segment)
    AND (p_product IS NULL OR c.produto = p_product)
    AND (p_state IS NULL OR c.uf = p_state)
    AND (p_city IS NULL OR c.municipio = p_city)
    AND (p_cnae IS NULL OR c.cnae_principal = p_cnae)
    AND (p_is_client IS NULL OR (ct.status = 'cliente') = p_is_client)
  ORDER BY CASE WHEN v_point IS NOT NULL THEN ST_Distance(c.geom, v_point) ELSE 0 END
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.search_companies(
  double precision, double precision, double precision, text, text, text, text, text, text, boolean, integer, uuid
) TO web_user;

-- get_filter_options não muda: roda com as permissões de quem chama, então a RLS
-- de companies já limita as opções às empresas das organizações do usuário.

NOTIFY pgrst, 'reload schema';
