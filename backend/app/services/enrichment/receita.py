"""Receita Federal (cadastro do CNPJ): BrasilAPI, com o Minha Receita de reserva.

As duas servem o mesmo formato (dados abertos do CNPJ da Receita). Normaliza
para o que o app mostra: situação, abertura, porte, capital, Simples/MEI,
histórico de regime tributário, CNAEs e quadro de sócios."""

import httpx

from .base import SourceNotFound, SourceUnavailable, blank_to_none, digits, get_json

BRASILAPI_URL = "https://brasilapi.com.br/api/cnpj/v1/{cnpj}"
MINHA_RECEITA_URL = "https://minhareceita.org/{cnpj}"

# identificador_de_socio da Receita
_TIPO_SOCIO = {1: "PJ", 2: "PF", 3: "Estrangeiro"}


async def fetch(client: httpx.AsyncClient, cnpj: str) -> dict:
    """Cadastro normalizado. Tenta a BrasilAPI e, se ela cair, o Minha Receita.
    CNPJ inexistente nas duas → SourceNotFound."""
    errors = []
    for origem, url in (
        ("BrasilAPI", BRASILAPI_URL),
        ("Minha Receita", MINHA_RECEITA_URL),
    ):
        try:
            raw = await get_json(client, url.format(cnpj=cnpj))
        except SourceNotFound:
            errors.append("not_found")
            continue
        except SourceUnavailable as exc:
            errors.append(str(exc))
            continue
        if isinstance(raw, dict) and raw.get("cnpj"):
            return {**normalize(raw), "origem": origem}
        errors.append(f"{origem}: formato inesperado")
    if errors and all(e == "not_found" for e in errors):
        raise SourceNotFound(cnpj)
    raise SourceUnavailable("; ".join(errors))


def _phone(ddd_tel) -> str | None:
    d = digits(ddd_tel)
    if len(d) < 10:
        return None
    ddd, num = d[:2], d[2:]
    return f"({ddd}) {num[:-4]}-{num[-4:]}"


def _date(value) -> str | None:
    value = blank_to_none(value)
    return value[:10] if isinstance(value, str) else None


def _cnae(code, desc) -> dict | None:
    if not code and not desc:
        return None
    c = digits(code)
    pretty = f"{c[:2]}.{c[2:4]}-{c[4]}/{c[5:]}" if len(c) == 7 else c or None
    return {"codigo": pretty, "descricao": blank_to_none(desc)}


def normalize(raw: dict) -> dict:
    telefones = [
        t for t in (_phone(raw.get("ddd_telefone_1")), _phone(raw.get("ddd_telefone_2"))) if t
    ]
    regime = sorted(
        (
            {"ano": r.get("ano"), "forma": blank_to_none(r.get("forma_de_tributacao"))}
            for r in raw.get("regime_tributario") or []
            if r.get("ano")
        ),
        key=lambda r: r["ano"],
        reverse=True,
    )
    socios = [
        {
            "nome": blank_to_none(s.get("nome_socio")),
            "qualificacao": blank_to_none(s.get("qualificacao_socio")),
            "desde": _date(s.get("data_entrada_sociedade")),
            "faixa_etaria": blank_to_none(s.get("faixa_etaria")),
            "tipo": _TIPO_SOCIO.get(s.get("identificador_de_socio")),
        }
        for s in raw.get("qsa") or []
        if blank_to_none(s.get("nome_socio"))
    ]
    capital = raw.get("capital_social")
    try:
        capital = float(capital) if capital not in (None, "") else None
    except (TypeError, ValueError):
        capital = None
    return {
        "cnpj": digits(raw.get("cnpj")),
        "razao_social": blank_to_none(raw.get("razao_social")),
        "nome_fantasia": blank_to_none(raw.get("nome_fantasia")),
        "matriz": raw.get("identificador_matriz_filial") == 1,
        "situacao": {
            "descricao": blank_to_none(raw.get("descricao_situacao_cadastral")),
            "desde": _date(raw.get("data_situacao_cadastral")),
            "motivo": blank_to_none(raw.get("descricao_motivo_situacao_cadastral")),
        },
        "abertura": _date(raw.get("data_inicio_atividade")),
        "porte": blank_to_none(raw.get("porte")),
        "natureza_juridica": blank_to_none(raw.get("natureza_juridica")),
        "capital_social": capital,
        "cnae_principal": _cnae(raw.get("cnae_fiscal"), raw.get("cnae_fiscal_descricao")),
        "cnaes_secundarios": [
            c
            for c in (
                _cnae(s.get("codigo"), s.get("descricao"))
                for s in raw.get("cnaes_secundarios") or []
            )
            if c and c.get("descricao")
        ],
        "simples": {
            "optante": raw.get("opcao_pelo_simples"),
            "desde": _date(raw.get("data_opcao_pelo_simples")),
            "excluido_em": _date(raw.get("data_exclusao_do_simples")),
        },
        "mei": {
            "optante": raw.get("opcao_pelo_mei"),
            "desde": _date(raw.get("data_opcao_pelo_mei")),
            "excluido_em": _date(raw.get("data_exclusao_do_mei")),
        },
        "regime_tributario": regime,
        "socios": socios,
        "endereco": {
            "logradouro": " ".join(
                p
                for p in (
                    blank_to_none(raw.get("descricao_tipo_de_logradouro")),
                    blank_to_none(raw.get("logradouro")),
                )
                if p
            )
            or None,
            "numero": blank_to_none(raw.get("numero")),
            "complemento": blank_to_none(raw.get("complemento")),
            "bairro": blank_to_none(raw.get("bairro")),
            "municipio": blank_to_none(raw.get("municipio")),
            "uf": blank_to_none(raw.get("uf")),
            "cep": digits(raw.get("cep")) or None,
        },
        "codigo_municipio_ibge": raw.get("codigo_municipio_ibge"),
        "telefones": telefones,
        "email": (blank_to_none(raw.get("email")) or "").lower() or None,
    }
