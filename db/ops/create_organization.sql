-- Operação manual: cria uma organização (grupo) e a entrega a um administrador já
-- cadastrado. Serve pra criar a organização DONA da base atual ("Rumo"); depois
-- disso, `assign_legacy_companies.sql` passa a base sem dono pra ela.
--
-- O administrador precisa já ter entrado no app uma vez (existir em `profiles`).
-- Idempotente: se já existe uma organização com esse nome em que ele é admin,
-- não cria outra. O código de convite NÃO é impresso (o admin vê no app).
--
-- Uso:  psql -U postgres -d rumo -v org_name='Rumo' -v admin_email='alguem@exemplo.com' \
--          -f db/ops/create_organization.sql
\set ON_ERROR_STOP on

-- psql não interpola variáveis dentro de $$...$$: passa por configurações de sessão.
SELECT set_config('rumo.org_name', btrim(:'org_name'), false) AS _ \gset
SELECT set_config('rumo.admin_email', lower(btrim(:'admin_email')), false) AS _ \gset

DO $$
DECLARE
  v_name text := current_setting('rumo.org_name');
  v_admin text;
  v_group uuid;
BEGIN
  IF v_name = '' THEN
    RAISE EXCEPTION 'org_name é obrigatório';
  END IF;

  SELECT id INTO v_admin FROM public.profiles WHERE lower(email) = current_setting('rumo.admin_email');
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'Nenhum perfil com o e-mail informado: a pessoa precisa entrar no app uma vez antes.';
  END IF;

  SELECT g.id INTO v_group
  FROM public.groups g
  JOIN public.group_members m ON m.group_id = g.id AND m.user_id = v_admin AND m.role = 'admin'
  WHERE g.name = v_name
  ORDER BY g.created_at
  LIMIT 1;

  IF v_group IS NULL THEN
    INSERT INTO public.groups (name, invite_hash, created_by)
    VALUES (v_name, encode(gen_random_bytes(16), 'hex'), v_admin)
    RETURNING id INTO v_group;

    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_group, v_admin, 'admin');
    RAISE NOTICE 'organização criada';
  ELSE
    RAISE NOTICE 'já existia: nada foi criado';
  END IF;
END $$;

SELECT g.id AS organizacao_id, g.name, (SELECT count(*) FROM public.group_members m WHERE m.group_id = g.id) AS membros
FROM public.groups g
JOIN public.group_members a ON a.group_id = g.id AND a.role = 'admin'
JOIN public.profiles p ON p.id = a.user_id AND lower(p.email) = lower(btrim(:'admin_email'))
WHERE g.name = btrim(:'org_name')
ORDER BY g.created_at;
