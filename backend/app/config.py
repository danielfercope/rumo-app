from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    firebase_project_id: str
    # Caminho para o JSON da service account do Firebase (montado como volume local
    # ou escrito pelo UserData do EC2 a partir do Secrets Manager em produção).
    firebase_service_account_path: str = "/app/secrets/firebase-service-account.json"

    # Segredo compartilhado com o PostgREST (mesmo valor em PGRST_JWT_SECRET).
    internal_jwt_secret: str
    internal_jwt_ttl_seconds: int = 3600

    crm_token: str = ""
    # Nome interno (não o label) da propriedade customizada de CNPJ no objeto
    # Company do CRM — criada manualmente na conta, não assumir um valor fixo.
    crm_cnpj_property_name: str = "cnpj"

    # Sincronização CRM -> banco (ver services/crm_sync_service.py). Desligada
    # por padrão: só liga depois do backfill inicial (app.scripts.crm_backfill).
    crm_sync_enabled: bool = False
    crm_sync_interval_seconds: int = 600
    # Janela de sobreposição da consulta: o Search do HubSpot demora um pouco
    # pra indexar empresas novas, então empresas criadas nesta janela são
    # reconsultadas (e deduplicadas) a cada ciclo.
    crm_sync_overlap_minutes: int = 30
    crm_sync_batch_size: int = 100

    # Chave de SERVIDOR da Google Geocoding API (distinta da chave do Maps no
    # app, que é restrita por referrer/app).
    geocoding_api_key: str = ""

    # PostgREST dentro da rede do compose (sem passar pelo Caddy).
    postgrest_url: str = "http://postgrest:3000"


settings = Settings()
