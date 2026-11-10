-- O Backend precisa conferir se quem pede pra conectar/desconectar o CRM é
-- ADMIN da organização (endpoints /carteira/* em backend/app/main.py). Ele fala
-- com o banco como `crm_sync` (sem identidade de usuário, então is_group_admin()
-- não serve), logo precisa ler group_members. Só leitura — a pertença continua
-- sendo escrita exclusivamente pelas RPCs de 007_groups.sql.
-- Idempotente (o `make migrate` reaplica todos os arquivos de db/schema).

GRANT SELECT ON public.group_members TO crm_sync;

DROP POLICY IF EXISTS group_members_select_crm_sync ON public.group_members;
CREATE POLICY group_members_select_crm_sync ON public.group_members
  FOR SELECT TO crm_sync USING (true);
