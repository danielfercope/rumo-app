# Requisitos Funcionais — RUMO

Lista de requisitos funcionais do aplicativo, derivada das funcionalidades implementadas. Para arquitetura, diagrama de providers e fluxo de navegação, ver [`CLAUDE.md`](../CLAUDE.md).

| ID | Requisito |
|---|---|
| RF01 | O sistema deve permitir que o usuário se autentique via e-mail e senha. |
| RF02 | O sistema deve permitir autenticação via conta Google (OAuth2). |
| RF03 | O sistema deve permitir o cadastro de novos usuários, informando nome, e-mail, senha e departamento. |
| RF04 | O sistema deve exibir, em um mapa, as empresas cadastradas dentro de um raio configurável a partir da localização atual do usuário. |
| RF05 | O sistema deve permitir filtrar as empresas exibidas por segmento, produto, UF, cidade, CNAE e tipo (cliente ou lead). |
| RF06 | O sistema deve exibir os detalhes de uma empresa ao selecionar seu marcador no mapa. |
| RF07 | O sistema deve permitir traçar rota até a empresa selecionada, delegando para um aplicativo externo de mapas. |
| RF08 | O sistema deve exibir e permitir adicionar notas e contatos do CRM (HubSpot) vinculados a uma empresa. |
| RF09 | O sistema deve permitir o cadastro de uma nova empresa a partir do CNPJ, buscando automaticamente os dados cadastrais na API EmpresaAqui. |
| RF10 | O sistema deve validar que a empresa sendo cadastrada está dentro de um raio de proximidade aceitável (2 km) em relação à localização do usuário no momento do cadastro. |
| RF11 | O sistema deve enviar os dados da empresa recém-cadastrada para o CRM corporativo via webhook. |
| RF12 | O sistema deve restringir o cadastro de empresas a usuários dos departamentos Pré-vendas, Gestão ou Administração Interna, ou com nível de acesso administrador. |
| RF13 | O sistema deve permitir a busca textual de empresas/leads por nome ou CNPJ. |
| RF14 | O sistema deve registrar periodicamente (a cada 5 minutos) a localização do usuário autenticado, mantendo a posição mais recente da equipe e um histórico de localizações. |
| RF15 | O sistema deve permitir que o usuário encerre sua sessão (logout). |
| RF16 | O sistema deve exibir ao usuário a Política de Privacidade, acessível tanto antes quanto depois da autenticação. |
| RF17 | O sistema deve registrar eventos de navegação e falhas técnicas para fins de monitoramento (Firebase Analytics e Crashlytics). |
