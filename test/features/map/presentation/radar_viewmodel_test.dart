import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/presentation/radar_viewmodel.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('estado inicial mostra a lista e mantém a contagem recolhida', () {
    final state = container.read(radarViewModelProvider);
    expect(state.showBottomList, isTrue);
    expect(state.isCountExpanded, isFalse);
  });

  test('toggleBottomList alterna a visibilidade da lista', () {
    final vm = container.read(radarViewModelProvider.notifier);
    vm.toggleBottomList();
    expect(container.read(radarViewModelProvider).showBottomList, isFalse);
    vm.toggleBottomList();
    expect(container.read(radarViewModelProvider).showBottomList, isTrue);
  });

  test('hideBottomList e showList definem a visibilidade explicitamente', () {
    final vm = container.read(radarViewModelProvider.notifier);
    vm.hideBottomList();
    expect(container.read(radarViewModelProvider).showBottomList, isFalse);
    vm.showList();
    expect(container.read(radarViewModelProvider).showBottomList, isTrue);
  });

  test('toggleCountExpanded alterna sem afetar a lista', () {
    final vm = container.read(radarViewModelProvider.notifier);
    vm.toggleCountExpanded();
    final state = container.read(radarViewModelProvider);
    expect(state.isCountExpanded, isTrue);
    expect(state.showBottomList, isTrue);
  });
}
