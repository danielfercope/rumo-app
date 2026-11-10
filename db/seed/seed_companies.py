#!/usr/bin/env python3
"""Gera empresas fictícias dentro de um raio geográfico, pra popular o
banco local de testes (alvo do `make data`).

Imprime SQL (INSERT) no stdout — não se conecta ao banco diretamente, de
propósito: quem chama decide pra onde mandar (psql local, outro ambiente,
etc.). Só usa a stdlib do Python, sem dependência nova.

Uso direto (sem o Makefile):
    python3 db/seed/seed_companies.py --count 40 | psql -U postgres -d rumo
"""
import argparse
import math
import random

# Ponto de referência: 26°26'13.0"S 49°04'14.9"W (Jaraguá do Sul, SC).
CENTER_LAT = -26.436944
CENTER_LON = -49.070806
DEFAULT_RADIUS_KM = 10.0

SEGMENTOS = ["Varejo", "Indústria", "Serviços", "Tecnologia", "Agronegócio"]
PRODUTOS = ["SaveID", "Libr.ia", None]
MUNICIPIOS = ["Jaraguá do Sul", "Guaramirim", "Corupá", "Massaranduba", "Schroeder"]
PREFIXOS_FANTASIA = [
    "Metalúrgica", "Comércio", "Distribuidora", "Indústria", "Serviços",
    "Transportes", "Tecnologia", "Agropecuária", "Construtora", "Confecções",
]


def gerar_cnpj() -> str:
    """CNPJ com dígitos verificadores válidos — é dado de teste, não
    corresponde a nenhuma empresa real (os 8 primeiros dígitos são
    aleatórios, não uma raiz de CNPJ emitida de fato)."""
    base = [random.randint(0, 9) for _ in range(12)]

    def calcular_dv(numeros: list[int]) -> int:
        pesos = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2][-len(numeros):]
        soma = sum(n * p for n, p in zip(numeros, pesos))
        resto = soma % 11
        return 0 if resto < 2 else 11 - resto

    dv1 = calcular_dv(base)
    dv2 = calcular_dv(base + [dv1])
    return "".join(map(str, base + [dv1, dv2]))


def ponto_aleatorio_no_raio(lat: float, lon: float, raio_km: float) -> tuple[float, float]:
    """Ponto aleatório dentro de um círculo de `raio_km` ao redor de
    (lat, lon), uniformemente distribuído por ÁREA (daí o sqrt() na
    distância — sem ele, os pontos ficariam concentrados perto do centro).
    Aproximação plana: válida pra raios pequenos como os 10km daqui; não
    serve pra distâncias continentais."""
    angulo = random.uniform(0, 2 * math.pi)
    distancia = raio_km * math.sqrt(random.uniform(0, 1))

    delta_lat = (distancia * math.cos(angulo)) / 111.32
    delta_lon = (distancia * math.sin(angulo)) / (111.32 * math.cos(math.radians(lat)))

    return lat + delta_lat, lon + delta_lon


def sql_str(valor) -> str:
    if valor is None:
        return "NULL"
    return "'" + str(valor).replace("'", "''") + "'"


def gerar_insert_empresa(indice: int, lat_centro: float, lon_centro: float, raio_km: float) -> str:
    lat, lon = ponto_aleatorio_no_raio(lat_centro, lon_centro, raio_km)
    cnpj = gerar_cnpj()
    nome_fantasia = f"{random.choice(PREFIXOS_FANTASIA)} {indice:03d}"
    razao_social = f"{nome_fantasia} LTDA"
    segmento = random.choice(SEGMENTOS)
    produto = random.choice(PRODUTOS)
    is_client = random.random() < 0.4
    municipio = random.choice(MUNICIPIOS)
    telefone = f"479{random.randint(1000, 9999)}{random.randint(1000, 9999)}"
    dominio = nome_fantasia.lower().replace(" ", "")
    email = f"contato{indice}@{dominio}.com.br"

    return (
        "INSERT INTO companies "
        "(cnpj, razao_social, nome_fantasia, segmento, produto, is_client, "
        "uf, municipio, telefone_principal, email_principal, latitude, longitude) "
        f"VALUES ({sql_str(cnpj)}, {sql_str(razao_social)}, {sql_str(nome_fantasia)}, "
        f"{sql_str(segmento)}, {sql_str(produto)}, {is_client}, 'SC', {sql_str(municipio)}, "
        f"{sql_str(telefone)}, {sql_str(email)}, {lat:.6f}, {lon:.6f}) "
        "ON CONFLICT (cnpj) DO NOTHING;"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=40, help="Quantas empresas gerar")
    parser.add_argument("--lat", type=float, default=CENTER_LAT)
    parser.add_argument("--lon", type=float, default=CENTER_LON)
    parser.add_argument("--radius-km", type=float, default=DEFAULT_RADIUS_KM)
    parser.add_argument("--seed", type=int, default=None, help="Seed do random, pra reprodutibilidade")
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    print("BEGIN;")
    for i in range(1, args.count + 1):
        print(gerar_insert_empresa(i, args.lat, args.lon, args.radius_km))
    print("COMMIT;")


if __name__ == "__main__":
    main()
