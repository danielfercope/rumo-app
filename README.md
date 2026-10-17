# Rumo

> **Prospecção inteligente e dinâmica baseada em geolocalização para equipes de vendas externas (Field Sales).**

O **Rumo** é uma aplicação mobile focada em inteligência comercial. Ele substitui planilhas estáticas por uma arquitetura geoespacial dinâmica, permitindo que executivos de vendas visualizem, filtrem e interajam com leads e clientes diretamente no mapa, integrando dados públicos e o CRM corporativo em tempo real.

---

## Funcionalidades Principais

* **Mapeamento Georreferenciado:** Exibe empresas cadastradas no raio de atuação do usuário, processando filtragens espaciais de alta precisão diretamente no banco de dados.
* **Integração Bidirecional de CRM:** Sincronização automatizada e em tempo real com o HubSpot. Notas, contatos e negócios criados em campo refletem instantaneamente na nuvem, e vice-versa.
* **Descoberta Dinâmica de Leads:** Enriquecimento cadastral via CNPJ e geocodificação inteligente de endereços, convertendo listas em rotas práticas sem necessidade de digitação manual.
* **Roteamento Integrado:** Traçado de rotas otimizadas até o cliente utilizando o padrão de mercado do Google Maps.
* **Contexto Centralizado:** Todo o histórico de interações, métricas e dados estratégicos do cliente acessíveis a um toque.

---

## Tecnologias e Arquitetura

O projeto foi desenhado sob o padrão arquitetural **MVVM** (Model-View-ViewModel), garantindo reatividade, baixo acoplamento e alta testabilidade.

### Mobile (Frontend)
* **[Flutter](https://flutter.dev/):** Framework multiplataforma (Dart) focado em performance nativa.
* **Componentes Reativos:** Utilização de `Cupertino Widgets` para uma usabilidade fluida focada no uso em campo.
* **Google Maps SDK:** Renderização de camadas geoespaciais e interação de mapa.

### Backend & Banco de Dados
* **[Firebase Auth](https://firebase.google.com/products/auth):** Autenticação (e-mail/senha e Google), com Crashlytics e Analytics também via Firebase.
* **Backend self-hospedado:** PostgreSQL + PostGIS exposto via [PostgREST](https://postgrest.org/), com um serviço Python (FastAPI) auxiliar, atrás de um proxy Caddy — orquestrado localmente via Docker Compose.
* **PostgreSQL + PostGIS:** O coração do sistema de geolocalização. Processa *Stored Procedures* baseadas no modelo elipsoidal WGS 84 para cálculo de distâncias na casa dos milímetros.

### APIs & Integrações
* **HubSpot API v3:** Gestão de contatos, negócios e histórico de anotações.
* **Google Geocoding API:** Conversão de endereços em coordenadas com qualificação de precisão (Rooftop, Interpolated, etc.).

---

## Como Executar o Projeto

### Pré-requisitos
Certifique-se de ter instalado em sua máquina:
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (versão mais recente)
* Uma IDE como VS Code ou Android Studio
* [Docker](https://www.docker.com/) + Docker Compose (pra rodar o backend self-hospedado localmente)
* Projeto Firebase configurado (Auth, Crashlytics, Analytics) e chaves das APIs do Google Maps/Geocoding, HubSpot e EmpresaAqui
* Para rodar em iOS: um **Mac com Xcode**, idealmente com um **iPhone físico** disponível pra testar (o simulador não reproduz fielmente permissões de localização em background)

### Passo a Passo

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/seu-usuario/rumo-app.git
   cd rumo-app
   ```

2. **Configure o `.env` do app** na raiz do projeto, com as variáveis listadas no `CLAUDE.md` (seção "Variáveis de ambiente").

3. **Suba o backend self-hospedado localmente:**
   ```bash
   cp infra/.env.example infra/.env   # preencher os segredos antes
   make db-up                          # sobe PostgreSQL + PostGREST + backend Python + Caddy
   make data                           # opcional — popula empresas fictícias pra testar o radar
   ```

4. **Rode o app:**
   ```bash
   # Web
   flutter run -d chrome --dart-define-from-file=.env

   # Android/iOS (dispositivo ou emulador já selecionado)
   flutter run --dart-define-from-file=.env
   ```
   Detalhes completos (configuração extra do iOS, permissões, etc.) estão no `CLAUDE.md`, seção "Executando o projeto localmente".

5. **Gere o APK Android** (opcional, pra distribuição/teste fora do ambiente de desenvolvimento):
   ```bash
   flutter build apk --release --dart-define-from-file=.env
   ```
   Requer `android/key.properties` + keystore configurados (não versionados) para um build de release assinado.
