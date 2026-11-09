-- search_companies passa a conhecer a carteira da organização (009_carteira.sql).
--
-- Com p_group_id, "cliente" deixa de ser o flag global companies.is_client e
-- vira o status da empresa na carteira daquela organização; a nova coluna
-- status_carteira devolve 'cliente' | 'lead' | 'perdido' (NULL = empresa que a
-- organização ainda não conhece, ou seja, candidata a ser pontuada). A busca
-- continua varrendo TODAS as empresas (o universo de candidatos), só muda de
-- onde vem o status.
-- Sem p_group_id o comportamento é o de antes (usa companies.is_client).
--
-- O DROP é necessário: um parâmetro novo em CREATE OR REPLACE criaria uma
-- sobrecarga, e o PostgREST não resolve chamadas ambíguas entre as duas.
-- Idempotente: o `make migrate` reaplica 004 (que recria a assinatura antiga)
-- e este arquivo troca de novo.

DROP FUNCTION IF EXISTS public.search_companies(
  double precision, double precision, double precision, text, text, text, text, text, text, boolean, integer
);

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
  IF p_group_id IS NOT NULL AND NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Você não pertence a esta organização';
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
    CASE WHEN p_group_id IS NULL THEN c.is_client
         ELSE COALESCE(ct.status = 'cliente', false) END,
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
  FROM public.companies c
  LEFT JOIN public.company_financial_profile f ON f.company_id = c.id
  LEFT JOIN public.carteira_empresas ct
    ON p_group_id IS NOT NULL AND ct.group_id = p_group_id AND ct.company_id = c.id
  WHERE
    (v_point IS NULL OR ST_DWithin(c.geom, v_point, p_radius_km * 1000))
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
    AND (
      p_is_client IS NULL
      OR CASE WHEN p_group_id IS NULL THEN c.is_client = p_is_client
              ELSE COALESCE(ct.status = 'cliente', false) = p_is_client END
    )
  ORDER BY CASE WHEN v_point IS NOT NULL THEN ST_Distance(c.geom, v_point) ELSE 0 END
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.search_companies(
  double precision, double precision, double precision, text, text, text, text, text, text, boolean, integer, uuid
) TO web_user;
