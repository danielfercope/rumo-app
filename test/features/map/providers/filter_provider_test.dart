import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';

void main() {
  group('MapFilters', () {
    test('valores padrão: raio 5.0 e demais campos nulos', () {
      final filters = MapFilters();

      expect(filters.radius, 5.0);
      expect(filters.segment, isNull);
      expect(filters.isEmpty, isTrue);
    });

    test('copyWith atualiza apenas o campo informado', () {
      final filters = MapFilters().copyWith(segment: 'Varejo');

      expect(filters.segment, 'Varejo');
      expect(filters.radius, 5.0);
      expect(filters.isEmpty, isFalse);
    });

    test(
        'copyWith com clearX remove o campo mesmo se um novo valor for passado',
        () {
      final comSegmento = MapFilters().copyWith(segment: 'Varejo');
      final semSegmento =
          comSegmento.copyWith(segment: 'Ignorado', clearSegment: true);

      expect(semSegmento.segment, isNull);
    });

    test('limpar o estado (UF) também limpa a cidade selecionada', () {
      final filters = MapFilters().copyWith(state: 'SC', city: 'Joinville');
      expect(filters.city, 'Joinville');

      final semEstado = filters.copyWith(clearState: true);

      expect(semEstado.state, isNull);
      expect(semEstado.city, isNull,
          reason: 'cidade não faz sentido sem o estado');
    });

    test(
        'copyWith(state: novoValor) sem informar city limpa a cidade do estado anterior',
        () {
      final filters = MapFilters().copyWith(state: 'SC', city: 'Joinville');
      final novoEstado = filters.copyWith(state: 'SP');

      expect(novoEstado.state, 'SP');
      expect(novoEstado.city, isNull,
          reason: 'cidade de um estado diferente não deve ser preservada');
    });

    test(
        'copyWith(state: novoValor, city: novaCidade) usa a nova cidade informada',
        () {
      final filters = MapFilters().copyWith(state: 'SC', city: 'Joinville');
      final novoEstado = filters.copyWith(state: 'SP', city: 'Campinas');

      expect(novoEstado.state, 'SP');
      expect(novoEstado.city, 'Campinas');
    });
  });

  group('MapFiltersNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('estado inicial é MapFilters padrão', () {
      final state = container.read(mapFiltersProvider);
      expect(state.isEmpty, isTrue);
    });

    test('setSegment define e limpa o segmento', () {
      final notifier = container.read(mapFiltersProvider.notifier);

      notifier.setSegment('Indústria');
      expect(container.read(mapFiltersProvider).segment, 'Indústria');

      notifier.setSegment(null);
      expect(container.read(mapFiltersProvider).segment, isNull);
    });

    test('setUf(null) limpa a cidade junto com o estado', () {
      final notifier = container.read(mapFiltersProvider.notifier);

      notifier.setUf('SC');
      notifier.setCity('Joinville');
      expect(container.read(mapFiltersProvider).city, 'Joinville');

      notifier.setUf(null);
      expect(container.read(mapFiltersProvider).city, isNull);
    });

    test('setUf(novoEstado) limpa a cidade do estado anterior', () {
      final notifier = container.read(mapFiltersProvider.notifier);

      notifier.setUf('SC');
      notifier.setCity('Joinville');

      notifier.setUf('SP');

      expect(container.read(mapFiltersProvider).city, isNull);
    });

    test('clear() restaura os filtros para o estado padrão', () {
      final notifier = container.read(mapFiltersProvider.notifier);

      notifier.setSegment('Indústria');
      notifier.setRadius(20);
      notifier.clear();

      final state = container.read(mapFiltersProvider);
      expect(state.isEmpty, isTrue);
      expect(state.radius, 5.0);
    });

    test('apply() substitui o estado inteiro pelo filtro informado', () {
      final notifier = container.read(mapFiltersProvider.notifier);
      final novosFiltros = MapFilters(segment: 'Serviços', radius: 10);

      notifier.apply(novosFiltros);

      expect(container.read(mapFiltersProvider), same(novosFiltros));
    });
  });
}
