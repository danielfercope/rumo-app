"""Importação única do histórico de empresas do CRM pro banco.

Uso (dentro do container do backend):
    python -m app.scripts.crm_backfill

Idempotente: empresas que já estão no banco só ganham o vínculo com o CRM, e a
marca d'água do job periódico nunca anda pra trás. Rode antes de ligar
CRM_SYNC_ENABLED."""

import asyncio
import logging

from ..main import (
    company_lookup_service,
    crm_service,
    crm_sync_service,
    geocoding_service,
    postgrest_client,
)


async def main() -> None:
    logging.basicConfig(level=logging.INFO)
    # httpx loga a URL de cada chamada em INFO — inclui a chave do geocoding.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    try:
        total = await crm_sync_service.backfill()
        print(f"Backfill concluído: {total}")
    finally:
        await company_lookup_service.aclose()
        await crm_service.aclose()
        await geocoding_service.aclose()
        await postgrest_client.aclose()


if __name__ == "__main__":
    asyncio.run(main())
