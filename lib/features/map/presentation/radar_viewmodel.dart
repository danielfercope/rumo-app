import 'package:flutter_riverpod/flutter_riverpod.dart';

class RadarUiState {
  final bool showBottomList;
  final bool isCountExpanded;

  const RadarUiState({
    this.showBottomList = true,
    this.isCountExpanded = false,
  });

  RadarUiState copyWith({bool? showBottomList, bool? isCountExpanded}) =>
      RadarUiState(
        showBottomList: showBottomList ?? this.showBottomList,
        isCountExpanded: isCountExpanded ?? this.isCountExpanded,
      );
}

class RadarViewModel extends Notifier<RadarUiState> {
  @override
  RadarUiState build() => const RadarUiState();

  void toggleBottomList() =>
      state = state.copyWith(showBottomList: !state.showBottomList);

  void hideBottomList() => state = state.copyWith(showBottomList: false);

  void showList() => state = state.copyWith(showBottomList: true);

  void toggleCountExpanded() =>
      state = state.copyWith(isCountExpanded: !state.isCountExpanded);
}

final radarViewModelProvider =
    NotifierProvider<RadarViewModel, RadarUiState>(RadarViewModel.new);
