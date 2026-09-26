# Casos de Uso e Fluxos de Uso — RUMO

## Atores

- **Executivo de vendas**: usuário padrão, opera em campo, consulta o mapa e registra visitas.
- **Pré-vendas / Gestão / Administração Interna**: além do acesso padrão, podem cadastrar novas empresas.
- **Administrador** (`nivel_acesso = admin`): acesso completo, incluindo cadastro de empresas independente do departamento.

## User stories

| ID | User story |
|---|---|
| US01 | Como executivo de vendas, quero visualizar no mapa as empresas próximas da minha localização, para priorizar visitas por proximidade geográfica. |
| US02 | Como executivo de vendas, quero filtrar as empresas exibidas por segmento e produto, para focar minha prospecção em um nicho específico. |
| US03 | Como executivo de vendas, quero ver o histórico de notas e contatos do CRM de uma empresa, para me preparar antes de uma visita. |
| US04 | Como usuário autorizado, quero cadastrar uma nova empresa informando apenas o CNPJ, para não digitar manualmente dados que já existem publicamente. |
| US05 | Como gestor comercial, quero que a localização da equipe seja registrada automaticamente, para acompanhar a cobertura territorial dos vendedores. |
| US06 | Como usuário, quero buscar uma empresa pelo nome ou CNPJ, para encontrá-la rapidamente sem precisar estar fisicamente perto dela. |
| US07 | Como usuário, quero saber quais dados o aplicativo coleta sobre mim, para entender como minha privacidade é tratada. |

---

## Fluxos de uso completos

O `norte.md` exige ao menos três fluxos de uso completos que demonstrem o valor do produto. Os três abaixo cobrem as três frentes funcionais do RUMO: consulta geoespacial, prospecção via CRM e cadastro de novas empresas.

### Fluxo 1 — Prospecção geoespacial no radar

1. Usuário faz login (e-mail/senha ou Google).
2. App obtém a localização GPS atual e centraliza o mapa.
3. `RadarPage` exibe os marcadores das empresas dentro do raio configurado (`companiesProvider`, via RPC `search_companies_in_radius`).
4. Usuário aplica filtros avançados (segmento, produto, UF, cidade, CNAE, tipo cliente/lead) através do `FilterModal`.
5. Usuário toca em um marcador → abre `CompanyDetailsModal` com os dados da empresa.
6. Usuário toca em "traçar rota" → app abre o Google Maps externo com a rota até a empresa.

**Valor demonstrado**: substitui planilhas estáticas por priorização visual e geoespacial de visitas.

### Fluxo 2 — Consulta de lead via CRM

1. Usuário navega até a aba "Leads".
2. Usuário busca uma empresa por nome ou CNPJ (`leadsSearchQueryProvider` → `leadsResultsProvider`).
3. Usuário abre os detalhes da empresa encontrada.
4. App busca e exibe notas (`hubspotNotesProvider`) e contatos (`hubspotContactsProvider`) do HubSpot vinculados à empresa.
5. Usuário adiciona uma nova nota após uma interação comercial, que é sincronizada de volta ao HubSpot.

**Valor demonstrado**: integração bidirecional com o CRM sem sair do aplicativo de campo.

### Fluxo 3 — Cadastro de nova empresa

1. Usuário autorizado (departamento ou nível de acesso compatível) toca em "+ empresa" no `RadarPage`.
2. **Passo 1**: informa o CNPJ; app consulta a API EmpresaAqui e valida que a empresa está a até 2 km da localização atual.
3. **Passo 2**: revisa/completa dados do sócio responsável.
4. **Passo 3**: preenche dados complementares (segmento, produto, observações).
5. App salva a empresa no Supabase (`central_data`) e envia os dados para o CRM via webhook.
6. App exibe confirmação de sucesso e atualiza o mapa com o novo marcador.

**Valor demonstrado**: elimina digitação manual e garante que só empresas fisicamente visitadas sejam cadastradas.
