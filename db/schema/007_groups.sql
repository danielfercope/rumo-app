-- Grupos (organizações): qualquer usuário pode criar um grupo (tornando-se
-- admin automaticamente) ou entrar via hash de convite (entra como member).
-- Um usuário pode pertencer a vários grupos (N-para-N via group_members).
--
-- Toda escrita em groups/group_members passa pelas RPCs abaixo (SECURITY
-- DEFINER) em vez de INSERT/UPDATE direto via PostgREST — várias regras
-- (não deixar o grupo sem admin, só admin regenera convite, join
-- idempotente) não são expressáveis como uma cláusula USING/WITH CHECK
-- estática. A coluna invite_hash fica de fora do GRANT de SELECT: só
-- get_group_invite() (admin-only) a devolve — nenhum membro comum consegue
-- ler o hash via GET /rest/groups.

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_bytes() pro hash do convite

CREATE TABLE IF NOT EXISTS public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  invite_hash text NOT NULL,
  tracking_enabled boolean NOT NULL DEFAULT false,
  created_by text NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS groups_invite_hash_key ON public.groups(invite_hash);

CREATE TABLE IF NOT EXISTS public.group_members (
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id text NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS group_members_user_id_idx ON public.group_members(user_id);

-- ── Funções auxiliares de autorização ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id AND user_id = public.auth_uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_group_member(uuid) TO web_user;

CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id AND user_id = public.auth_uid() AND role = 'admin'
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_group_admin(uuid) TO web_user;

-- Usada pela policy de SELECT de tracking_equipe/tracking_history: um admin
-- só pode ler a posição de outra pessoa se os dois compartilharem um grupo
-- em que ele é admin e esse grupo tem tracking_enabled=true.
CREATE OR REPLACE FUNCTION public.can_view_tracking(p_target_user_id text)
RETURNS boolean AS $$
  SELECT p_target_user_id = public.auth_uid()
    OR EXISTS (
      SELECT 1
      FROM public.group_members gm_self
      JOIN public.group_members gm_target
        ON gm_target.group_id = gm_self.group_id
       AND gm_target.user_id = p_target_user_id
      JOIN public.groups g ON g.id = gm_self.group_id
      WHERE gm_self.user_id = public.auth_uid()
        AND gm_self.role = 'admin'
        AND g.tracking_enabled = true
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.can_view_tracking(text) TO web_user;

-- ── RLS de groups/group_members ─────────────────────────────────────────────

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.groups FROM web_user;
GRANT SELECT (id, name, tracking_enabled, created_by, created_at) ON public.groups TO web_user;

DROP POLICY IF EXISTS groups_select_member ON public.groups;
CREATE POLICY groups_select_member ON public.groups
  FOR SELECT TO web_user USING (public.is_group_member(id));

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.group_members TO web_user;

DROP POLICY IF EXISTS group_members_select_same_group ON public.group_members;
CREATE POLICY group_members_select_same_group ON public.group_members
  FOR SELECT TO web_user USING (public.is_group_member(group_id));

-- ── RPCs ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_group(p_name text)
RETURNS public.groups AS $$
DECLARE
  v_uid text := public.auth_uid();
  v_group public.groups;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;
  IF btrim(coalesce(p_name, '')) = '' THEN
    RAISE EXCEPTION 'Nome do grupo é obrigatório';
  END IF;

  INSERT INTO public.groups (name, invite_hash, created_by)
  VALUES (btrim(p_name), encode(gen_random_bytes(16), 'hex'), v_uid)
  RETURNING * INTO v_group;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group.id, v_uid, 'admin');

  RETURN v_group;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_group(text) TO web_user;

CREATE OR REPLACE FUNCTION public.join_group_by_hash(p_hash text)
RETURNS public.groups AS $$
DECLARE
  v_uid text := public.auth_uid();
  v_group public.groups;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;

  SELECT * INTO v_group FROM public.groups WHERE invite_hash = p_hash;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Convite inválido ou expirado';
  END IF;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group.id, v_uid, 'member')
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN v_group;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.join_group_by_hash(text) TO web_user;

CREATE OR REPLACE FUNCTION public.regenerate_group_invite(p_group_id uuid)
RETURNS public.groups AS $$
DECLARE
  v_group public.groups;
BEGIN
  IF NOT public.is_group_admin(p_group_id) THEN
    RAISE EXCEPTION 'Apenas administradores podem regenerar o convite';
  END IF;

  UPDATE public.groups
  SET invite_hash = encode(gen_random_bytes(16), 'hex')
  WHERE id = p_group_id
  RETURNING * INTO v_group;

  RETURN v_group;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.regenerate_group_invite(uuid) TO web_user;

-- Única forma de reler o hash sem regenerar (ex.: reabrir a tela de gestão).
-- Se o chamador não for admin, devolve NULL (0 linhas) em vez de erro — o
-- GroupService no Flutter trata null como "sem permissão".
CREATE OR REPLACE FUNCTION public.get_group_invite(p_group_id uuid)
RETURNS text AS $$
  SELECT invite_hash FROM public.groups
  WHERE id = p_group_id AND public.is_group_admin(p_group_id);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_group_invite(uuid) TO web_user;

-- Edge case: nunca deixar o grupo sem nenhum admin (bloqueia despromover,
-- inclusive auto-despromover, o último admin restante).
CREATE OR REPLACE FUNCTION public.set_member_role(
  p_group_id uuid, p_user_id text, p_role text
)
RETURNS public.group_members AS $$
DECLARE
  v_member public.group_members;
  v_admin_count int;
BEGIN
  IF p_role NOT IN ('admin', 'member') THEN
    RAISE EXCEPTION 'Papel inválido: %', p_role;
  END IF;
  IF NOT public.is_group_admin(p_group_id) THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar papéis';
  END IF;

  SELECT * INTO v_member FROM public.group_members
  WHERE group_id = p_group_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuário não pertence a este grupo';
  END IF;

  IF v_member.role = 'admin' AND p_role = 'member' THEN
    SELECT count(*) INTO v_admin_count FROM public.group_members
    WHERE group_id = p_group_id AND role = 'admin';
    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'O grupo precisa de pelo menos um administrador';
    END IF;
  END IF;

  UPDATE public.group_members SET role = p_role
  WHERE group_id = p_group_id AND user_id = p_user_id
  RETURNING * INTO v_member;

  RETURN v_member;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.set_member_role(uuid, text, text) TO web_user;

CREATE OR REPLACE FUNCTION public.set_group_tracking(p_group_id uuid, p_enabled boolean)
RETURNS public.groups AS $$
DECLARE
  v_group public.groups;
BEGIN
  IF NOT public.is_group_admin(p_group_id) THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar o rastreamento do grupo';
  END IF;

  UPDATE public.groups SET tracking_enabled = p_enabled WHERE id = p_group_id
  RETURNING * INTO v_group;

  RETURN v_group;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.set_group_tracking(uuid, boolean) TO web_user;

-- Lista membros com dados de perfil — RPC em vez de view: uma view comum
-- sobre profiles herdaria a RLS "só a própria linha" pra quem consulta, e
-- membros não veriam o nome dos colegas.
CREATE OR REPLACE FUNCTION public.list_group_members(p_group_id uuid)
RETURNS TABLE (
  user_id text, nome text, email text, departamento text, role text, joined_at timestamptz
) AS $$
BEGIN
  IF NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Você não pertence a este grupo';
  END IF;

  RETURN QUERY
  SELECT gm.user_id, p.nome, p.email, p.departamento, gm.role, gm.joined_at
  FROM public.group_members gm
  JOIN public.profiles p ON p.id = gm.user_id
  WHERE gm.group_id = p_group_id
  ORDER BY gm.role DESC, p.nome;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_group_members(uuid) TO web_user;

-- Posições da equipe de um grupo — só admin, e só se tracking_enabled.
-- Usada pela tela "Mapa da Equipe".
CREATE OR REPLACE FUNCTION public.list_group_tracking(p_group_id uuid)
RETURNS TABLE (
  user_id text, nome text, email text,
  latitude double precision, longitude double precision, ultimo_visto timestamptz
) AS $$
BEGIN
  IF NOT public.is_group_admin(p_group_id) THEN
    RAISE EXCEPTION 'Apenas administradores podem ver a localização da equipe';
  END IF;
  IF NOT (SELECT tracking_enabled FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'Rastreamento desativado para este grupo';
  END IF;

  RETURN QUERY
  SELECT te.user_id, te.nome, te.email, te.latitude, te.longitude, te.ultimo_visto
  FROM public.tracking_equipe te
  JOIN public.group_members gm ON gm.user_id = te.user_id AND gm.group_id = p_group_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_group_tracking(uuid) TO web_user;

-- ── Policies de leitura de tracking_equipe/tracking_history ─────────────────
-- Substitui "só a própria linha" por can_view_tracking(). As policies de
-- INSERT/UPDATE (upsert da própria posição) ficam intactas.

DROP POLICY IF EXISTS tracking_equipe_select_own ON public.tracking_equipe;
CREATE POLICY tracking_equipe_select_own ON public.tracking_equipe
  FOR SELECT TO web_user USING (public.can_view_tracking(user_id));

DROP POLICY IF EXISTS tracking_history_select_own ON public.tracking_history;
CREATE POLICY tracking_history_select_own ON public.tracking_history
  FOR SELECT TO web_user USING (public.can_view_tracking(user_id));
