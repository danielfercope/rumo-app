"""Seed de teste: carteira sintética de revendas de insumos agrícolas.

Pega CNPJs reais e públicos da base aberta da Receita, atribui status de
cliente/lead/perdido por uma regra SINTÉTICA e documentada, e sobe tudo para
uma conta de teste do HubSpot — pra exercitar o fluxo completo (conectar o CRM,
sincronizar, priorizar) sem uma carteira real.

Os status são inventados: o teste valida o ENCANAMENTO (conexão, sincronização,
cálculo, tela), não o valor do algoritmo. Ver `labeling.py`.

Uso: `python -m app.scripts.seed_agro --help`."""
