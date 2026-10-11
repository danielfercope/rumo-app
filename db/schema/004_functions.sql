-- RPCs de busca — desenhadas do zero (não são extração do Supabase; a
-- decisão foi construir uma nova em vez de reverter a lógica antiga).
-- search_companies unifica raio geográfico + busca textual + filtros num
-- único endpoint; get_filter_options continua separada (é agregação pra
-- popular dropdowns, uma operação diferente de busca).
--
-- O formato de retorno usa os mesmos nomes de coluna que Company.fromJson
-- (lib/features/map/models/company_model.dart) já espera — zero mudança
-- no model Dart quando company_service.dart for rewired pra chamar isto.

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
  p_limit integer DEFAULT 200
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
  distance_km double precision
) AS $$
DECLARE
  v_point geography;
  v_cnpj_digits text;
BEGIN
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
    c.is_client,
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
    CASE WHEN v_point IS NOT NULL THEN ST_Distance(c.geom, v_point) / 1000.0 END AS distance_km
  FROM public.companies c
  LEFT JOIN public.company_financial_profile f ON f.company_id = c.id
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
    AND (p_is_client IS NULL OR c.is_client = p_is_client)
  ORDER BY CASE WHEN v_point IS NOT NULL THEN ST_Distance(c.geom, v_point) ELSE 0 END
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.search_companies(
  double precision, double precision, double precision, text, text, text, text, text, text, boolean, integer
) TO web_user;

CREATE OR REPLACE FUNCTION public.get_filter_options()
RETURNS jsonb AS $$
  SELECT jsonb_build_object(
    'segments', (SELECT coalesce(jsonb_agg(DISTINCT segmento), '[]') FROM companies WHERE segmento IS NOT NULL),
    'products', (SELECT coalesce(jsonb_agg(DISTINCT produto), '[]') FROM companies WHERE produto IS NOT NULL),
    'states', (SELECT coalesce(jsonb_agg(DISTINCT uf), '[]') FROM companies WHERE uf IS NOT NULL),
    'cnaes', (SELECT coalesce(jsonb_agg(DISTINCT cnae_principal), '[]') FROM companies WHERE cnae_principal IS NOT NULL),
    'state_to_cities', (
      SELECT coalesce(jsonb_object_agg(uf, cities), '{}')
      FROM (
        SELECT uf, jsonb_agg(DISTINCT municipio) AS cities
        FROM companies
        WHERE uf IS NOT NULL AND municipio IS NOT NULL
        GROUP BY uf
      ) t
    )
  );
$$ LANGUAGE sql STABLE;

GRANT EXECUTE ON FUNCTION public.get_filter_options() TO web_user;
