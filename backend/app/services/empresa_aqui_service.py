from ..errors import NotImplementedIntegrationError


class EmpresaAquiService:
    """Consulta de dados cadastrais por CNPJ. BLOQUEIO #2 do plano: a lógica
    real (hoje uma Edge Function do Supabase) precisa ser extraída do
    Dashboard → Edge Functions (ou `supabase functions download
    empresa-aqui`) antes deste método ser implementado — não inventar a
    lógica aqui."""

    async def lookup_cnpj(self, payload: dict) -> dict:
        raise NotImplementedIntegrationError(
            "Endpoint ainda não implementado — depende da extração da Edge "
            "Function original (ver bloqueio #2 do plano)"
        )
