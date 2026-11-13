-- Histórico de deslocamento: trajeto de um membro num período, pro admin.
-- `tracking_history` já é append-only (o app insere a cada 5 min); aqui só
-- entram o índice de consulta e a RPC de leitura. Idempotente.

CREATE INDEX IF NOT EXISTS tracking_history_user_captured_idx
  ON public.tracking_history (user_id, captured_at DESC);

-- Mesmas regras de list_group_tracking: só admin do grupo, só com
-- tracking_enabled, e só de quem é membro DESSE grupo. O período é limitado
-- a 31 dias por chamada pra não devolver o histórico inteiro de uma vez.
CREATE OR REPLACE FUNCTION public.list_group_tracking_history(
  p_group_id uuid,
  p_user_id text,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS TABLE (
  latitude double precision,
  longitude double precision,
  captured_at timestamptz
) AS $$
BEGIN
  IF NOT public.is_group_admin(p_group_id) THEN
    RAISE EXCEPTION 'Apenas administradores podem ver a localização da equipe';
  END IF;
  IF NOT (SELECT tracking_enabled FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'Rastreamento desativado para este grupo';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.group_id = p_group_id AND gm.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'Usuário não pertence a este grupo';
  END IF;
  IF p_to - p_from > interval '31 days' THEN
    RAISE EXCEPTION 'Período máximo de 31 dias';
  END IF;

  RETURN QUERY
  SELECT th.latitude, th.longitude, th.captured_at
  FROM public.tracking_history th
  WHERE th.user_id = p_user_id
    AND th.captured_at >= p_from
    AND th.captured_at < p_to
  ORDER BY th.captured_at;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_group_tracking_history(uuid, text, timestamptz, timestamptz) TO web_user;

-- ── Foto do membro no Mapa da Equipe ────────────────────────────────────────
-- A foto vive no Firebase (conta Google); o app de cada usuário manda a URL
-- junto da posição. Sem ela, o mapa cai nas iniciais.
ALTER TABLE public.tracking_equipe ADD COLUMN IF NOT EXISTS foto_url text;

-- O tipo de retorno mudou (nova coluna): CREATE OR REPLACE não basta.
DROP FUNCTION IF EXISTS public.list_group_tracking(uuid);
CREATE FUNCTION public.list_group_tracking(p_group_id uuid)
RETURNS TABLE (
  user_id text, nome text, email text,
  latitude double precision, longitude double precision, ultimo_visto timestamptz,
  foto_url text
) AS $$
BEGIN
  IF NOT public.is_group_admin(p_group_id) THEN
    RAISE EXCEPTION 'Apenas administradores podem ver a localização da equipe';
  END IF;
  IF NOT (SELECT tracking_enabled FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'Rastreamento desativado para este grupo';
  END IF;

  RETURN QUERY
  SELECT te.user_id, te.nome, te.email, te.latitude, te.longitude,
         te.ultimo_visto, te.foto_url
  FROM public.tracking_equipe te
  JOIN public.group_members gm ON gm.user_id = te.user_id AND gm.group_id = p_group_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_group_tracking(uuid) TO web_user;
