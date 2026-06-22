Rumo

Prospecção inteligente e dinâmica baseada em geolocalização para equipes de vendas externas (Field Sales).

O Rumo é uma aplicação mobile focada em inteligência comercial. Ele substitui planilhas estáticas por uma arquitetura geoespacial dinâmica, permitindo que executivos de vendas visualizem, filtrem e interajam com leads e clientes diretamente no mapa, integrando dados públicos e o CRM corporativo em tempo real.

Funcionalidades Principais

Mapeamento Georreferenciado: Exibe empresas cadastradas no raio de atuação do usuário, processando filtragens espaciais de alta precisão diretamente no banco de dados.

Integração Bidirecional de CRM: Sincronização automatizada e em tempo real com o HubSpot. Notas, contatos e negócios criados em campo refletem instantaneamente na nuvem, e vice-versa.

Descoberta Dinâmica de Leads: Enriquecimento cadastral via CNPJ e geocodificação inteligente de endereços, convertendo listas em rotas práticas sem necessidade de digitação manual.

Roteamento Integrado: Traçado de rotas otimizadas até o cliente utilizando o padrão de mercado do Google Maps.

Contexto Centralizado: Todo o histórico de interações, métricas e dados estratégicos do cliente acessíveis a um toque.

Tecnologias e Arquitetura

O projeto foi desenhado sob o padrão arquitetural MVVM (Model-View-ViewModel), garantindo reatividade, baixo acoplamento e alta testabilidade.

Mobile (Frontend)

Flutter: Framework multiplataforma (Dart) focado em performance nativa.

Componentes Reativos: Utilização de Cupertino Widgets para uma usabilidade fluida focada no uso em campo.

Google Maps SDK: Renderização de camadas geoespaciais e interação de mapa.

Backend & Banco de Dados

Supabase: Backend-as-a-Service, provendo autenticação e microsserviços rápidos.

PostgreSQL + PostGIS: O coração do sistema de geolocalização. Processa Stored Procedures baseadas no modelo elipsoidal WGS 84 para cálculo de distâncias na casa dos milímetros.

APIs & Integrações

HubSpot API v3: Gestão de contatos, negócios e histórico de anotações.

Google Geocoding API: Conversão de endereços em coordenadas com qualificação de precisão (Rooftop, Interpolated, etc.).

Como Executar o Projeto

Pré-requisitos

Certifique-se de ter instalado em sua máquina:

Flutter SDK (versão mais recente)

Uma IDE como VS Code ou Android Studio

Conta configurada no Supabase e chaves das APIs do Google e HubSpot.

Passo a Passo

Clone o repositório:

git clone [https://github.com/seu-usuario/rumo-app.git](https://github.com/seu-usuario/rumo-app.git)
cd rumo-app


Instale as dependências:

flutter pub get


Configure as Variáveis de Ambiente:
Crie um arquivo .env na raiz do projeto e adicione suas credenciais:

SUPABASE_URL=sua_url_aqui
SUPABASE_ANON_KEY=sua_chave_aqui
GOOGLE_MAPS_API_KEY=sua_chave_maps_aqui
HUBSPOT_ACCESS_TOKEN=seu_token_hubspot_aqui


Execute o aplicativo:

flutter run


Testes e Qualidade

O ciclo de engenharia do Rumo aplica uma forte cultura de testes visando a estabilidade da ferramenta em campo:

TDD (Test-Driven Development): Ampla cobertura de testes unitários nas camadas de Model e ViewModel.

Análise Estática: Governança de código contínua via SonarQube para garantir a manutenibilidade do Dart.

Autor

Desenvolvido com dedicação por Daniel Fernando Costa Pereira.

Centro Universitário Católica de Santa Catarina (Projeto PAC)

Contato: danielfercope@gmail.com
