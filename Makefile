.PHONY: db-up db-down db-reset psql migrate token

COMPOSE = docker compose -f docker-compose.backend.yml --env-file infra/.env

db-up: ## Sobe db + postgrest + Backend em background
	$(COMPOSE) up -d

db-down: ## Derruba os containers (mantém os dados)
	$(COMPOSE) down

db-reset: ## Apaga os dados e reaplica o schema do zero (db/schema/*.sql)
	$(COMPOSE) down -v
	$(COMPOSE) up -d db
	@echo "Aguardando o Postgres ficar saudável..."
	@until $(COMPOSE) exec -T db pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
	$(COMPOSE) up -d postgrest backend

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
