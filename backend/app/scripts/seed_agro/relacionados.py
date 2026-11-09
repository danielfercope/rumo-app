"""Contato e negócio FICTÍCIOS pra cada empresa do seed.

Nada aqui descreve uma pessoa real: nomes saem de listas genéricas combinadas de
forma determinística pelo CNPJ, e o e-mail usa `example.com` (domínio reservado
pela RFC 2606, que nunca entrega mensagem). Não há telefone.

Como o token do seed não cria propriedades em contatos/negócios, o que marca
um registro como do lote são campos que já existem: o domínio do e-mail do
contato e o prefixo do nome do negócio."""

import hashlib
import re
import unicodedata

from .enrich import Company

EMAIL_DOMAIN = "seed.example.com"

FIRST_NAMES = (
    "Ana", "Bruno", "Carla", "Daniel", "Elisa", "Fábio", "Gabriela", "Henrique",
    "Isabela", "João", "Karina", "Lucas", "Marina", "Nelson", "Olívia", "Paulo",
    "Renata", "Sérgio", "Tatiana", "Vítor",
)
LAST_NAMES = (
    "Almeida", "Barros", "Cardoso", "Dias", "Esteves", "Fontana", "Gomes",
    "Henriques", "Ibarra", "Jardim", "Klein", "Lopes", "Moreira", "Nogueira",
    "Oliveira", "Pereira", "Queiroz", "Ramos", "Siqueira", "Teixeira",
)
JOB_TITLES = ("Comprador", "Gerente comercial", "Diretor", "Responsável técnico")

# negócios em aberto variam entre as etapas iniciais do funil padrão
OPEN_STAGES = ("appointmentscheduled", "qualifiedtobuy", "presentationscheduled")
DEAL_STAGE_BY_STATUS = {"cliente": "closedwon", "perdido": "closedlost"}


def _n(cnpj: str, salt: str) -> int:
    digest = hashlib.sha256(f"{salt}:{cnpj}".encode()).digest()
    return int.from_bytes(digest[:4], "big")


def _slug(text: str) -> str:
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "", plain.lower())


def deal_prefix(lote: str) -> str:
    return f"[{lote}] "


def contact_properties(company: Company) -> dict[str, str]:
    cnpj = re.sub(r"\D", "", company.cnpj)
    first = FIRST_NAMES[_n(cnpj, "first") % len(FIRST_NAMES)]
    last = LAST_NAMES[_n(cnpj, "last") % len(LAST_NAMES)]
    return {
        "firstname": first,
        "lastname": last,
        # o CNPJ inteiro mantém o e-mail único entre empresas
        "email": f"{_slug(first)}.{_slug(last)}.{cnpj}@{EMAIL_DOMAIN}",
        "jobtitle": JOB_TITLES[_n(cnpj, "job") % len(JOB_TITLES)],
    }


def is_seed_contact(properties: dict) -> bool:
    return (properties.get("email") or "").lower().endswith("@" + EMAIL_DOMAIN)


def deal_properties(company: Company, status: str, lote: str) -> dict[str, str]:
    cnpj = re.sub(r"\D", "", company.cnpj)
    name = company.nome_fantasia or company.razao_social
    return {
        "dealname": f"{deal_prefix(lote)}{name} · insumos agrícolas",
        "pipeline": "default",
        "dealstage": DEAL_STAGE_BY_STATUS.get(
            status, OPEN_STAGES[_n(cnpj, "stage") % len(OPEN_STAGES)]
        ),
        # valores redondos entre 5 mil e 250 mil
        "amount": str(5000 + (_n(cnpj, "amount") % 49) * 5000),
    }


def is_seed_deal(properties: dict, lote: str) -> bool:
    return (properties.get("dealname") or "").startswith(deal_prefix(lote))
