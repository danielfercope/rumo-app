-- Progresso da carga inicial + nomes de empresa vazios.
--
-- sincronizacoes passa a guardar quantas empresas a carga estima processar e
-- quantas já processou, pra a tela mostrar "230 de 502" em vez de ficar em 0 até
-- o fim (os totais finais só eram gravados quando a carga terminava). O
-- web_user já lê a tabela inteira (GRANT de 009), então as colunas novas
-- chegam ao app sem GRANT novo.
--
-- A BrasilAPI devolve nome fantasia como string vazia. O app só cai pra razão
-- social quando o campo é NULL, então o título dos detalhes saía em branco:
-- normaliza o que já está gravado (o Backend passa a gravar NULL).
--
-- Idempotente.

ALTER TABLE public.sincronizacoes
  ADD COLUMN IF NOT EXISTS total_estimado integer,
  ADD COLUMN IF NOT EXISTS total_processadas integer NOT NULL DEFAULT 0;

UPDATE public.companies
   SET nome_fantasia = NULL
 WHERE nome_fantasia IS NOT NULL AND btrim(nome_fantasia) = '';

-- O PostgREST guarda o esquema em cache: sem isto, a tabela/colunas novas
-- só aparecem pra ele depois de reiniciar.
NOTIFY pgrst, 'reload schema';
