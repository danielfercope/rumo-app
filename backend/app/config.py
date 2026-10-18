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


settings = Settings()
