"""Erros do app que não têm o Crashlytics (hoje: Flutter Web).

O app manda o erro pra `POST /client-errors` e ele vira UMA linha no log do
Backend, que em produção vai pro CloudWatch junto com o resto. A rota aceita
chamada sem login (o erro pode acontecer na tela de login), então:
- cada campo tem tamanho máximo (no schema);
- a linha é JSON: quebras de linha da pilha viram `\\n` e ninguém forja uma
  linha de log falsa nem quebra o erro em vários eventos no CloudWatch;
- há um limite de envios por cliente (uid, ou IP sem login) por janela.
"""

import json
import logging
import time
from collections import deque

logger = logging.getLogger("uvicorn.error.client")

MAX_REPORTS_PER_WINDOW = 20
WINDOW_SECONDS = 60.0
# Teto de clientes acompanhados ao mesmo tempo: sem ele, IPs diferentes
# fariam o dicionário crescer sem limite.
MAX_TRACKED_CLIENTS = 5000


class ClientErrorService:
    def __init__(
        self,
        max_per_window: int = MAX_REPORTS_PER_WINDOW,
        window_seconds: float = WINDOW_SECONDS,
        clock=time.monotonic,
    ) -> None:
        self._max = max_per_window
        self._window = window_seconds
        self._clock = clock
        self._hits: dict[str, deque[float]] = {}

    def allow(self, client_key: str) -> bool:
        now = self._clock()
        hits = self._hits.get(client_key)
        if hits is None:
            if len(self._hits) >= MAX_TRACKED_CLIENTS:
                self._prune(now)
            hits = self._hits[client_key] = deque()
        while hits and now - hits[0] >= self._window:
            hits.popleft()
        if len(hits) >= self._max:
            return False
        hits.append(now)
        return True

    def _prune(self, now: float) -> None:
        stale = [
            key
            for key, hits in self._hits.items()
            if not hits or now - hits[-1] >= self._window
        ]
        for key in stale:
            del self._hits[key]
        if len(self._hits) >= MAX_TRACKED_CLIENTS:
            # todos ativos: descarta o mais antigo (ordem de inserção)
            del self._hits[next(iter(self._hits))]

    def record(self, report: dict, uid: str | None) -> None:
        entry = {"uid": uid, **report}
        logger.error(
            "client_error %s", json.dumps(entry, ensure_ascii=False, sort_keys=True)
        )
