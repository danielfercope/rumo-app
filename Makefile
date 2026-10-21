.PHONY: db-up db-down db-reset psql migrate token data

COMPOSE = docker compose -f docker-compose.backend.yml --env-file infra/.env
COUNT ?= 40

db-up: ## Sobe db + postgrest + Backend em background (reconstrói imagens alteradas)
	$(COMPOSE) up -d --build

db-down: ## Derruba os containers (mantém os dados)
	$(COMPOSE) down

db-reset: ## Apaga os dados e reaplica o schema do zero (db/schema/*.sql)
	$(COMPOSE) down -v
	$(COMPOSE) up -d db
	@echo "Aguardando o Postgres ficar saudável..."
	@until $(COMPOSE) exec -T db pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
	$(COMPOSE) up -d --build postgrest backend

psql: ## Abre um shell psql dentro do container do banco
	$(COMPOSE) exec db psql -U postgres -d rumo

migrate: ## Reaplica manualmente os arquivos de db/schema (idempotentes via IF NOT EXISTS/OR REPLACE)
	@for f in db/schema/*.sql; do \
		echo "Aplicando $$f..."; \
		$(COMPOSE) exec -T db psql -U postgres -d rumo < $$f; \
	done
	@$(COMPOSE) exec -T db psql -U postgres -d rumo -c "NOTIFY pgrst, 'reload schema';"

token: ## Gera um JWT de teste: make token UID=algum-uid
	@python3 infra/scripts/make_token.py $(UID)

data: ## Popula o banco local com empresas fictícias num raio de 10km de Jaraguá do Sul/SC: make data [COUNT=40]
	@python3 db/seed/seed_companies.py --count $(COUNT) | $(COMPOSE) exec -T db psql -U postgres -d rumo
