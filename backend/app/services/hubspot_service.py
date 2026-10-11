from ..errors import NotImplementedIntegrationError


class HubSpotService:
    """Integração com o HubSpot CRM. BLOQUEIO #2 do plano: a lógica real
    (hoje uma Edge Function do Supabase com 4 ações) precisa ser extraída
    antes de implementar — não inventar a lógica aqui. Contrato mantido
    igual ao que lib/features/company/hubspot_service.dart já espera."""

    async def handle(self, payload: dict) -> dict:
        action = payload.get("action")
        handlers = {
            "getNotesWithOwners": self.get_notes_with_owners,
            "getContacts": self.get_contacts,
            "addContact": self.add_contact,
            "addNote": self.add_note,
        }
        handler = handlers.get(action)
        if handler is None:
            raise NotImplementedIntegrationError(f"Ação HubSpot desconhecida: {action}")
        return await handler(payload)

    async def get_notes_with_owners(self, payload: dict) -> dict:
        raise NotImplementedIntegrationError(
            "Endpoint ainda não implementado — depende da extração da Edge "
            "Function original (ver bloqueio #2 do plano)"
        )

    async def get_contacts(self, payload: dict) -> dict:
        raise NotImplementedIntegrationError(
            "Endpoint ainda não implementado — depende da extração da Edge "
            "Function original (ver bloqueio #2 do plano)"
        )

    async def add_contact(self, payload: dict) -> dict:
        raise NotImplementedIntegrationError(
            "Endpoint ainda não implementado — depende da extração da Edge "
            "Function original (ver bloqueio #2 do plano)"
        )

    async def add_note(self, payload: dict) -> dict:
        raise NotImplementedIntegrationError(
            "Endpoint ainda não implementado — depende da extração da Edge "
            "Function original (ver bloqueio #2 do plano)"
        )
