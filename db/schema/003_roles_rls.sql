-- Papéis do PostgREST + RLS equivalente ao auth.uid() do Supabase.
-- O Backend emite um token interno com claim "sub" = Firebase UID e
-- "role" = "web_user" (ver backend/app/internal_token.py); o PostgREST
-- usa o claim "role" pra fazer SET ROLE automaticamente (PGRST_JWT_ROLE_CLAIM_KEY).

CREATE ROLE web_anon NOLOGIN;
CREATE ROLE web_user NOLOGIN;

-- Senha de DEV apenas. Em produção, a senha real é definida via
-- `ALTER ROLE authenticator WITH PASSWORD '...'` executado manualmente no
-- deploy (valor vem do Secrets Manager) — nunca comitar a senha real aqui.
CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'authenticator';
GRANT web_anon TO authenticator;
GRANT web_user TO authenticator;

GRANT USAGE ON SCHEMA public TO web_anon, web_user;

-- Equivalente ao auth.uid() do Supabase: o Firebase coloca o UID no claim "sub".
CREATE OR REPLACE FUNCTION public.auth_uid() RETURNS text AS $$
  SELECT current_setting('request.jwt.claims', true)::json ->> 'sub';
$$ LANGUAGE sql STABLE;

-- ── profiles ────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO web_user;

CREATE POLICY profiles_select_own ON public.profiles
  FOR SELECT TO web_user USING (id = auth_uid());
CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT TO web_user WITH CHECK (id = auth_uid());
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO web_user USING (id = auth_uid());

-- ── tracking_equipe / tracking_history ──────────────────────────────────────
-- NOTA: hoje não há nenhuma leitura desses dados no app (só escrita, via
-- tracking_service.dart). SELECT "só a própria linha" é o padrão conservador
-- — se existir uma tela de gestão que precise ver a equipe toda, precisa de
-- uma policy adicional (ex.: liberar SELECT pra nivel_acesso = 'admin').
ALTER TABLE public.tracking_equipe ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.tracking_equipe TO web_user;

CREATE POLICY tracking_equipe_select_own ON public.tracking_equipe
  FOR SELECT TO web_user USING (user_id = auth_uid());
CREATE POLICY tracking_equipe_upsert_own ON public.tracking_equipe
  FOR INSERT TO web_user WITH CHECK (user_id = auth_uid());
CREATE POLICY tracking_equipe_update_own ON public.tracking_equipe
  FOR UPDATE TO web_user USING (user_id = auth_uid());

ALTER TABLE public.tracking_history ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.tracking_history TO web_user;

CREATE POLICY tracking_history_select_own ON public.tracking_history
  FOR SELECT TO web_user USING (user_id = auth_uid());
CREATE POLICY tracking_history_insert_own ON public.tracking_history
  FOR INSERT TO web_user WITH CHECK (user_id = auth_uid());

-- ── companies e tabelas satélite ─────────────────────────────────────────────
-- Leitura liberada a qualquer usuário autenticado; escrita restrita
-- replicando UserProfile.canAddCompany (departamento ou nivel_acesso).
CREATE OR REPLACE FUNCTION public.can_add_company() RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth_uid()
      AND (
        p.departamento IN ('Pré-vendas', 'Gestão', 'Administração Interna')
        OR p.nivel_acesso = 'admin'
      )
  );
$$ LANGUAGE sql STABLE;

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.companies TO web_user;

CREATE POLICY companies_select_all ON public.companies
  FOR SELECT TO web_user USING (true);
CREATE POLICY companies_insert_authorized ON public.companies
  FOR INSERT TO web_user WITH CHECK (can_add_company());
CREATE POLICY companies_update_authorized ON public.companies
  FOR UPDATE TO web_user USING (can_add_company());

ALTER TABLE public.company_financial_profile ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.company_financial_profile TO web_user;

CREATE POLICY company_financial_profile_select_all ON public.company_financial_profile
  FOR SELECT TO web_user USING (true);
CREATE POLICY company_financial_profile_write_authorized ON public.company_financial_profile
  FOR ALL TO web_user USING (can_add_company()) WITH CHECK (can_add_company());

ALTER TABLE public.company_contacts ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_contacts TO web_user;

CREATE POLICY company_contacts_select_all ON public.company_contacts
  FOR SELECT TO web_user USING (true);
CREATE POLICY company_contacts_write_authorized ON public.company_contacts
  FOR ALL TO web_user USING (can_add_company()) WITH CHECK (can_add_company());

-- company_crm_sync é escrito pelo Backend (sincronização com HubSpot) — sem
-- regra de permissão por departamento, só precisa estar autenticado.
ALTER TABLE public.company_crm_sync ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.company_crm_sync TO web_user;

CREATE POLICY company_crm_sync_select_all ON public.company_crm_sync
  FOR SELECT TO web_user USING (true);
CREATE POLICY company_crm_sync_write_all ON public.company_crm_sync
  FOR ALL TO web_user USING (true) WITH CHECK (true);
