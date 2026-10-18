import re

import httpx

from ..errors import CnpjNotFoundError, UpstreamIntegrationError

BASE_URL = "https://brasilapi.com.br/api/cnpj/v1"


def _only_digits(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


class CompanyLookupService:
    """Consulta de dados cadastrais por CNPJ. Hoje usa a BrasilAPI (pública,
    gratuita, sem token) — substitui o antigo provedor EmpresaAqui por
    completo, sem fallback (decisão do roadmap).

    O contrato de saída preserva de propósito as mesmas chaves que o
    provedor antigo produzia (`razao`, `fantasia`, `log_tipo`, `ddd_1`/
    `tel_1`, etc.), pra não exigir nenhuma mudança em
    lib/features/company/registration_service.dart (saveCompany/
    sendToWebhook) nem em add_company_modal.dart — só o nome do
    método/rota muda no lado do app."""

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(base_url=BASE_URL, timeout=10.0)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def lookup_cnpj(self, cnpj: str) -> dict:
        cnpj_digits = _only_digits(cnpj)
        try:
            response = await self._client.get(f"/{cnpj_digits}")
        except httpx.RequestError as exc:
            raise UpstreamIntegrationError(
                f"Falha de rede ao consultar CNPJ na BrasilAPI: {exc}"
            ) from exc

        if response.status_code == 404:
            raise CnpjNotFoundError(f"CNPJ {cnpj_digits} não encontrado")
        if response.status_code >= 400:
            raise UpstreamIntegrationError(
                f"BrasilAPI respondeu {response.status_code}: {response.text}"
            )

        return self._to_legacy_shape(response.json())

    @staticmethod
    def _to_legacy_shape(data: dict) -> dict:
        ddd, tel = CompanyLookupService._split_telefone(data.get("ddd_telefone_1"))
        data_abertura = data.get("data_inicio_atividade")
        if data_abertura:
            data_abertura = data_abertura.replace("-", "")

        return {
            "cnpj": data.get("cnpj"),
            "razao": data.get("razao_social"),
            "fantasia": data.get("nome_fantasia"),
            "email": data.get("email"),
            "site": None,  # não disponível na BrasilAPI gratuita
            "ddd_1": ddd,
            "tel_1": tel,
            "log_tipo": data.get("descricao_tipo_de_logradouro"),
            "log_nome": data.get("logradouro"),
            "log_num": data.get("numero"),
            "log_bairro": data.get("bairro"),
            "log_municipio": data.get("municipio"),
            "log_uf": data.get("uf"),
            "log_cep": data.get("cep"),
            "situacao_cadastral": data.get("descricao_situacao_cadastral"),
            "porte": data.get("porte"),
            "cnae_principal": data.get("cnae_fiscal_descricao"),
            "natureza_juridica": data.get("natureza_juridica"),
            "data_abertura": data_abertura,
        }

    @staticmethod
    def _split_telefone(raw: str | None) -> tuple[str, str]:
        digits = _only_digits(raw)
        if len(digits) < 3:
            return "", ""
        return digits[:2], digits[2:]
