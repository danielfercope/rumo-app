-- Centraliza o "ensure profile exists" (hoje espalhado em
-- signInWithGoogle/signUp em auth_provider.dart) num único round-trip.
-- Simplificada: sem o branch de "reivindicar perfil migrado por e-mail"
-- (não há mais migração de dados do Supabase — decisão do usuário).
-- Não precisa de SECURITY DEFINER: sempre opera sobre id = auth_uid(),
-- que já é exatamente o que profiles_insert_own permite.

CREATE OR REPLACE FUNCTION public.ensure_profile(
  p_nome text,
  p_departamento text DEFAULT NULL
)
RETURNS public.profiles AS $$
DECLARE
  v_uid text := public.auth_uid();
  v_email text := current_setting('request.jwt.claims', true)::json ->> 'email';
  v_profile public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF FOUND THEN
    RETURN v_profile;
  END IF;

  INSERT INTO public.profiles (id, email, nome, departamento, nivel_acesso)
  VALUES (v_uid, v_email, p_nome, COALESCE(p_departamento, 'Não definido'), 'user')
  RETURNING * INTO v_profile;
  RETURN v_profile;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.ensure_profile(text, text) TO web_user;
