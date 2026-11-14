"""Enriquecimento dos detalhes da empresa com fontes públicas.

Cada módulo é uma fonte independente: busca, normaliza num formato próprio e
levanta `SourceUnavailable` quando a fonte não responde. Quem orquestra (cache,
controle de acesso, falha isolada por fonte) é `service.EnrichmentService`."""
