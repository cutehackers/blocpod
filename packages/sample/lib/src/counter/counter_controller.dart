import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class CounterEvent {
  const CounterEvent();
}

final class CounterIncremented extends CounterEvent {
  const CounterIncremented(this.amount);

  final int amount;
}

final class CounterDecremented extends CounterEvent {
  const CounterDecremented();
}

final class CounterReset extends CounterEvent {
  const CounterReset();
}

final class CounterResetThroughChild extends CounterEvent {
  const CounterResetThroughChild();
}

final counterProvider = AsyncNotifierProvider<CounterController, int>(CounterController.new);

final class CounterController extends EventControllerNotifier<int, CounterEvent> {
  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case CounterIncremented(:final amount):
        state = AsyncData(_currentValue + amount);
      case CounterDecremented():
        state = AsyncData(_currentValue - 1);
      case CounterReset():
        state = const AsyncData(0);
      case CounterResetThroughChild():
        await dispatch(const CounterReset());
    }
  }

  @override
  String get controllerName => 'SampleCounterController';

  @override
  String eventName(CounterEvent event) => event.runtimeType.toString();

  @override
  Map<String, Object?> metadataFor(CounterEvent event) {
    return switch (event) {
      CounterIncremented(:final amount) => {'amount': amount},
      CounterDecremented() => const {'amount': -1},
      CounterReset() => const {'reason': 'direct-reset'},
      CounterResetThroughChild() => const {'reason': 'nested-dispatch'},
    };
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncData(:final value) => 'count:$value',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }

  @override
  Map<String, Object?> stateMetadata({required AsyncValue<int> previous, required AsyncValue<int> next}) {
    final previousValue = _valueOf(previous);
    final nextValue = _valueOf(next);
    if (previousValue == null || nextValue == null) {
      return const {};
    }

    return {'changedBy': nextValue - previousValue};
  }

  int get _currentValue => _valueOf(state) ?? 0;

  int? _valueOf(AsyncValue<int> value) {
    return switch (value) {
      AsyncData(:final value) => value,
      _ => null,
    };
  }
}
