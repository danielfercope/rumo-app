"""Chamadas ao HubSpot respeitando os limites de taxa.

A Search API (`/crm/v3/objects/*/search`) aceita só ~5 requisições por segundo
por conta, somando todos os apps; as demais rotas têm limites maiores. Paginar
a busca sem pausa (prévia, carga inicial) estoura o limite e o HubSpot responde
429 "You have reached your secondly limit".

Por isso: buscas espaçadas (no máximo SEARCH_PER_SECOND por cliente) e, se ainda
assim vier 429, espera e tenta de novo — usando o `Retry-After` quando o HubSpot
manda, senão um recuo exponencial curto."""

import asyncio
import time
from collections.abc import Awaitable, Callable

import httpx

SEARCH_PER_SECOND = 4
MAX_RETRIES = 5
BASE_BACKOFF_S = 1.0
MAX_BACKOFF_S = 10.0

Sleep = Callable[[float], Awaitable[None]]


class HubSpotHttp:
    def __init__(
        self,
        client: httpx.AsyncClient,
        *,
        sleep: Sleep | None = None,
        clock: Callable[[], float] | None = None,
    ) -> None:
        self._client = client
        # resolvidos aqui (não no default) pra os testes poderem trocar
        self._sleep = sleep or asyncio.sleep
        self._clock = clock or time.monotonic
        self._lock = asyncio.Lock()
        self._next_search_at = 0.0

    async def send(self, method: str, path: str, **kwargs) -> httpx.Response:
        """Faz a chamada; 429 vira espera e nova tentativa. Erros de rede
        (`httpx.RequestError`) sobem como vieram — quem chama os traduz."""
        for attempt in range(MAX_RETRIES + 1):
            if path.endswith("/search"):
                await self._pace_search()
            response = await self._client.request(method, path, **kwargs)
            if response.status_code != 429 or attempt == MAX_RETRIES:
                return response
            await self._sleep(self._backoff(response, attempt))
        return response  # inalcançável; satisfaz o verificador de tipos

    async def _pace_search(self) -> None:
        async with self._lock:
            wait = self._next_search_at - self._clock()
            if wait > 0:
                await self._sleep(wait)
            self._next_search_at = (
                max(self._clock(), self._next_search_at) + 1.0 / SEARCH_PER_SECOND
            )

    @staticmethod
    def _backoff(response: httpx.Response, attempt: int) -> float:
        retry_after = response.headers.get("Retry-After")
        try:
            if retry_after is not None:
                return min(max(float(retry_after), 0.0), MAX_BACKOFF_S)
        except ValueError:
            pass
        return min(BASE_BACKOFF_S * 2**attempt, MAX_BACKOFF_S)
