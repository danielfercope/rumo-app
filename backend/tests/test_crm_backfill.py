import pytest

from app.scripts import crm_backfill


@pytest.fixture
def closed(monkeypatch):
    names = []
    for name in (
        "company_lookup_service",
        "crm_service",
        "geocoding_service",
        "postgrest_client",
    ):
        service = getattr(crm_backfill, name)

        async def aclose(name=name):
            names.append(name)

        monkeypatch.setattr(service, "aclose", aclose)
    return names


async def test_main_roda_o_backfill_e_fecha_os_clientes(monkeypatch, closed, capsys):
    async def fake_backfill():
        return "importou 3"

    monkeypatch.setattr(crm_backfill.crm_sync_service, "backfill", fake_backfill)

    await crm_backfill.main()

    assert "Backfill concluído: importou 3" in capsys.readouterr().out
    assert sorted(closed) == [
        "company_lookup_service",
        "crm_service",
        "geocoding_service",
        "postgrest_client",
    ]


async def test_main_fecha_os_clientes_mesmo_se_o_backfill_falhar(monkeypatch, closed):
    async def boom():
        raise RuntimeError("CRM fora do ar")

    monkeypatch.setattr(crm_backfill.crm_sync_service, "backfill", boom)

    with pytest.raises(RuntimeError):
        await crm_backfill.main()

    assert len(closed) == 4
