"""Linha de comando do seed de insumos agrícolas.

Etapas (cada uma lê o arquivo da anterior):
  select   Receita → candidatas → BrasilAPI → empresas aceitas      (só leitura)
  label    atribui cliente/lead/perdido pela regra sintética         (local)
  upload   cria as empresas no HubSpot (estágio A ou B)    (ESCREVE só com --apply)
  relate   cria um contato e um negócio fictícios por empresa  (ESCREVE só com --apply)
  promote  muda os clientes do estágio A para o B          (ESCREVE só com --apply)
  clean    apaga do HubSpot o que o lote criou             (ESCREVE só com --apply)

Tudo o que escreve no HubSpot é DRY-RUN por padrão: sem --apply só mostra o
plano. O token vem da variável HUBSPOT_SEED_TOKEN, nunca de argumento."""

import argparse
import asyncio
import json
import os
import sys
from datetime import date

from . import enrich, hubspot, labeling, receita, relacionados

DEFAULT_LOTE = "seed-agro-1"


def _write(path: str, data) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def _read(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


async def cmd_select(args) -> int:
    municipios = receita.read_municipios(args.municipios)
    candidates: list[receita.Candidate] = []
    for path in args.estabelecimentos:
        found = receita.read_candidates(path)
        print(f"{os.path.basename(path)}: {len(found)} matrizes ativas nos CNAEs do segmento")
        candidates += found
    # a mesma empresa não deve aparecer duas vezes
    candidates = list({c.cnpj: c for c in candidates}.values())
    print(f"Total único: {len(candidates)}")

    pool = receita.stratified_sample(
        candidates, int(args.target * args.oversample), key=lambda c: receita.decade(c.ano), seed=args.seed
    )
    print(f"Candidatas a consultar na BrasilAPI: {len(pool)} (meta: {args.target} aceitas)")

    cache = enrich.Cache(args.cache)

    def progress(i, ok, total):
        if i % 25 == 0:
            print(f"  consultadas {i}/{total} · aceitas {ok}", flush=True)

    accepted, excluded = await enrich.enrich(
        [c.cnpj for c in pool], args.target * 2, cache, pause=args.pause, on_progress=progress
    )
    print("Excluídas:", excluded or "nenhuma")

    final = receita.stratified_sample(
        accepted, args.target, key=lambda c: receita.decade(
            int(c.inicio_atividade[:4]) if c.inicio_atividade else None
        ), seed=args.seed,
    )
    _write(args.out, [c.to_json() for c in final])
    print(f"Gravadas {len(final)} empresas em {args.out}")
    by_decade: dict[str, int] = {}
    by_uf: dict[str, int] = {}
    for c in final:
        d = receita.decade(int(c.inicio_atividade[:4]) if c.inicio_atividade else None)
        by_decade[d] = by_decade.get(d, 0) + 1
        by_uf[c.uf] = by_uf.get(c.uf, 0) + 1
    print("Por abertura:", dict(sorted(by_decade.items())))
    print("Por UF:", dict(sorted(by_uf.items(), key=lambda t: -t[1])))
    if len(final) < args.target:
        print(f"ATENÇÃO: só {len(final)} das {args.target} pedidas passaram nos filtros.")
    return 0


def cmd_label(args) -> int:
    companies = [enrich.Company.from_json(x) for x in _read(args.inp)]
    labeled = labeling.label(companies, seed=args.seed, today=date.today())
    _write(args.out, [x.to_json() for x in labeled])
    s = labeling.summary(labeled)
    print(f"{s['total']} empresas · status: {s['por_status']}")
    sul = {k: v for k, v in s["por_uf"].items() if k in labeling.SUL}
    print("Sul (PR/RS/SC):", sul)
    print(f"Teto de AUC desta regra (quem conhece a probabilidade verdadeira): "
          f"{labeling.ceiling_auc(labeled):.3f}")
    early = labeling.early_clients(labeled)
    print(f"Estágio A: {len(early)} clientes; o resto da carteira entra como lead.")
    return 0


def _token() -> str:
    token = os.environ.get("HUBSPOT_SEED_TOKEN", "")
    if not token:
        sys.exit("Defina HUBSPOT_SEED_TOKEN (token com escopo de escrita em empresas).")
    return token


async def cmd_upload(args) -> int:
    labeled = [labeling.Labeled.from_json(x) for x in _read(args.inp)]
    early = labeling.early_clients(labeled)
    chosen = labeled[: args.limit] if args.limit else labeled
    payloads = [
        hubspot.company_properties(x, labeling.status_at_stage(x, args.stage, early), args.lote)
        for x in chosen
    ]
    stages: dict[str, int] = {}
    for p in payloads:
        stages[p["lifecyclestage"]] = stages.get(p["lifecyclestage"], 0) + 1
    print(f"Estágio {args.stage}: {len(payloads)} empresas · ciclo de vida: {stages}")
    print("Exemplo do que seria enviado (nenhum telefone, e-mail ou contato):")
    print(json.dumps(payloads[:2], ensure_ascii=False, indent=1))
    if not args.apply:
        print("\nDRY-RUN: nada foi enviado. Use --apply para criar no HubSpot.")
        return 0
    seeder = hubspot.HubSpotSeeder(_token())
    try:
        created_props = await seeder.ensure_properties()
        if created_props:
            print("Propriedades criadas na conta:", created_props)
        n = await seeder.create(payloads, args.lote)
        print(f"Criadas {n} empresas (as já existentes no lote foram puladas).")
    finally:
        await seeder.aclose()
    return 0


async def cmd_relate(args) -> int:
    labeled = [labeling.Labeled.from_json(x) for x in _read(args.inp)]
    early = labeling.early_clients(labeled)
    chosen = labeled[: args.limit] if args.limit else labeled
    plan = [
        (
            x,
            relacionados.contact_properties(x.company),
            relacionados.deal_properties(x.company, labeling.status_at_stage(x, "A", early), args.lote),
        )
        for x in chosen
    ]
    stages: dict[str, int] = {}
    for _, _, d in plan:
        stages[d["dealstage"]] = stages.get(d["dealstage"], 0) + 1
    print(f"{len(plan)} empresas → {len(plan)} contatos + {len(plan)} negócios (todos fictícios)")
    print("Etapas dos negócios:", stages)
    print("Exemplo (sem telefone; e-mail em example.com, que não entrega):")
    print(json.dumps([{"contato": c, "negocio": d} for _, c, d in plan[:2]], ensure_ascii=False, indent=1))
    if not args.apply:
        print("\nDRY-RUN: nada foi enviado. Use --apply.")
        return 0
    seeder = hubspot.HubSpotSeeder(_token())
    try:
        companies = await seeder.existing(args.lote)
        missing = [x.company.cnpj for x, _, _ in plan if x.company.cnpj not in companies]
        if missing:
            sys.exit(f"{len(missing)} empresas do arquivo não estão no HubSpot (lote '{args.lote}'): rode `upload` antes.")
        items = [
            (companies[x.company.cnpj]["id"], c, d)
            for x, c, d in plan
        ]
        contacts, deals = await seeder.create_related(args.lote, items)
        print(f"Criados {contacts} contatos e {deals} negócios (os que já existiam foram preservados).")
    finally:
        await seeder.aclose()
    return 0


async def cmd_promote(args) -> int:
    labeled = [labeling.Labeled.from_json(x) for x in _read(args.inp)]
    targets = {x.company.cnpj: x.status for x in labeled}
    clients = sum(1 for s in targets.values() if s == "cliente")
    print(f"Estágio B: levar o lote '{args.lote}' ao status final ({clients} clientes).")
    if not args.apply:
        print("DRY-RUN: nada foi alterado. Use --apply.")
        return 0
    seeder = hubspot.HubSpotSeeder(_token())
    try:
        print(f"Atualizadas {await seeder.set_status(args.lote, targets)} empresas.")
    finally:
        await seeder.aclose()
    return 0


async def cmd_clean(args) -> int:
    print(f"Apagar do HubSpot TODAS as empresas do lote '{args.lote}'.")
    if not args.apply:
        print("DRY-RUN: nada foi apagado. Use --apply.")
        return 0
    seeder = hubspot.HubSpotSeeder(_token())
    try:
        contacts, deals = await seeder.delete_related(args.lote)
        print(f"Arquivados {contacts} contatos e {deals} negócios fictícios do lote.")
        print(f"Apagadas {await seeder.delete_lote(args.lote)} empresas.")
    finally:
        await seeder.aclose()
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="seed_agro", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("select", help="escolhe as empresas (só leitura)")
    s.add_argument("--estabelecimentos", nargs="+", required=True)
    s.add_argument("--municipios", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--cache", help="respostas da BrasilAPI (retoma se cair)")
    s.add_argument("--target", type=int, default=500)
    s.add_argument("--oversample", type=float, default=1.8)
    s.add_argument("--pause", type=float, default=0.4)
    s.add_argument("--seed", type=int, default=42)

    l = sub.add_parser("label", help="atribui os status (regra sintética)")
    l.add_argument("--in", dest="inp", required=True)
    l.add_argument("--out", required=True)
    l.add_argument("--seed", type=int, default=42)

    for name, text in (("upload", "cria no HubSpot"), ("relate", "contato + negócio fictícios por empresa"), ("promote", "estágio A → B"),
                       ("clean", "apaga o lote")):
        c = sub.add_parser(name, help=text)
        if name != "clean":
            c.add_argument("--in", dest="inp", required=True)
        c.add_argument("--lote", default=DEFAULT_LOTE)
        c.add_argument("--apply", action="store_true", help="de fato escreve no HubSpot")
        if name == "relate":
            c.add_argument("--limit", type=int, help="só as N primeiras (ex.: 2 pra testar)")
        if name == "upload":
            c.add_argument("--stage", choices=("A", "B"), default="A")
            c.add_argument("--limit", type=int, help="só as N primeiras (ex.: 5 pra testar)")
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    handler = {"select": cmd_select, "label": cmd_label, "upload": cmd_upload,
               "relate": cmd_relate, "promote": cmd_promote, "clean": cmd_clean}[args.cmd]
    result = handler(args)
    return asyncio.run(result) if asyncio.iscoroutine(result) else result


if __name__ == "__main__":
    sys.exit(main())
