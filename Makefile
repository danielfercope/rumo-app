.PHONY: db-up db-down db-reset psql migrate token data deploy deploy-web deploy-apk

COMPOSE = docker compose -f docker-compose.backend.yml --env-file infra/.env
COUNT ?= 40
# A stack rumo-app-backend roda em us-east-1 (o padrão do CLI pode ser outro).
AWS_REGION ?= us-east-1

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

BRANCH ?= main

deploy: ## Redeploy manual em produção via SSM (AWS CLI + INSTANCE_ID); acompanha a main: make deploy INSTANCE_ID=i-xxxx [BRANCH=main]
	aws ssm send-command --region $(AWS_REGION) \
		--instance-ids $(INSTANCE_ID) \
		--document-name "AWS-RunShellScript" \
		--parameters 'commands=["cd /opt/rumo-app && git fetch --depth 1 origin $(BRANCH) && git checkout -B $(BRANCH) FETCH_HEAD && docker compose -f docker-compose.backend.yml -f docker-compose.prod.yml --env-file infra/.env up -d --build"]'

deploy-web: ## Build do Flutter Web + publica em produção: make deploy-web INSTANCE_ID=i-xxxx ARTIFACTS_BUCKET=bucket
	AWS_REGION=$(AWS_REGION) infra/scripts/deploy_frontend.sh web

deploy-apk: ## Build do APK assinado + publica em /download/rumo.apk: make deploy-apk INSTANCE_ID=i-xxxx ARTIFACTS_BUCKET=bucket
	AWS_REGION=$(AWS_REGION) infra/scripts/deploy_frontend.sh apk
