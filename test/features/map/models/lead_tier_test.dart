import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/carteira/models/priority_models.dart';
import 'package:rumo_app/features/map/models/lead_tier.dart';

PriorityItem item(String id, int posicao, int? nota) =>
    PriorityItem(posicao: posicao, companyId: id, nota: nota);

PriorityResult result(List<PriorityItem> itens, PriorityStrategy e) =>
    PriorityResult(
      estrategia: e,
      nClientes: 5,
      nLeads: itens.length,
      minimoClientesPerfil: 10,
      itens: itens,
    );

void main() {
  test('com nota: limiares 67 (quente) e 34 (morno)', () {
    expect(tierForNota(100), LeadTier.hot);
    expect(tierForNota(67), LeadTier.hot);
    expect(tierForNota(66), LeadTier.warm);
    expect(tierForNota(34), LeadTier.warm);
    expect(tierForNota(33), LeadTier.cold);
    expect(tierForNota(0), LeadTier.cold);
  });

  test('sem nota (interação): terços pela posição', () {
    final itens = [for (var i = 0; i < 6; i++) item('c$i', i + 1, null)];
    final tiers = leadTiers(result(itens, PriorityStrategy.interacao));
    expect([
      for (var i = 0; i < 6; i++) tiers['c$i']
    ], [
      LeadTier.hot,
      LeadTier.hot,
      LeadTier.warm,
      LeadTier.warm,
      LeadTier.cold,
      LeadTier.cold,
    ]);
  });

  test('resultado vazio não gera faixas', () {
    expect(leadTiers(result(const [], PriorityStrategy.perfil)), isEmpty);
  });
}
