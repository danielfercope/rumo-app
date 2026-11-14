"""Peças comuns às fontes de enriquecimento."""

import httpx


class SourceUnavailable(Exception):
    """A fonte externa não respondeu (rede, timeout, 5xx, formato inesperado)."""


class SourceNotFound(Exception):
    """A fonte respondeu, mas não tem dado para esta empresa/município."""


async def get_json(
    client: httpx.AsyncClient, url: str, *, params: dict | None = None, **kwargs
):
    try:
        response = await client.get(url, params=params, **kwargs)
    except httpx.HTTPError as exc:
        raise SourceUnavailable(f"Falha de rede em {url}: {exc}") from exc
    if response.status_code == 404:
        raise SourceNotFound(url)
    if response.status_code >= 400:
        raise SourceUnavailable(f"{url} respondeu {response.status_code}")
    try:
        return response.json()
    except ValueError as exc:
        raise SourceUnavailable(f"{url} não devolveu JSON") from exc


async def post_json(client: httpx.AsyncClient, url: str, body: dict, **kwargs):
    try:
        response = await client.post(url, json=body, **kwargs)
    except httpx.HTTPError as exc:
        raise SourceUnavailable(f"Falha de rede em {url}: {exc}") from exc
    if response.status_code >= 400:
        raise SourceUnavailable(f"{url} respondeu {response.status_code}")
    try:
        return response.json()
    except ValueError as exc:
        raise SourceUnavailable(f"{url} não devolveu JSON") from exc


def digits(value) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def blank_to_none(value):
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value
