import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class CounterEvent {
  const CounterEvent();
}

final class AddCounterEvent extends CounterEvent {
  const AddCounterEvent(this.amount);

  final int amount;
}

final counterProvider = AsyncNotifierProvider<CounterController, int>(CounterController.new);

final autoDisposeCounterProvider = AsyncNotifierProvider.autoDispose<CounterController, int>(CounterController.new);

final familyCounterProvider = AsyncNotifierProvider.family<FamilyCounterController, int, int>(
  FamilyCounterController.new,
);

final autoDisposeFamilyCounterProvider = AsyncNotifierProvider.autoDispose.family<FamilyCounterController, int, int>(
  FamilyCounterController.new,
);

final class CounterController extends EventControllerNotifier<int, CounterEvent> {
  @override
  Future<int> build() async {
    return 0;
  }

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case AddCounterEvent(:final amount):
        state = AsyncData(_currentValue + amount);
    }
  }

  int get _currentValue {
    return switch (state) {
      AsyncData(:final value) => value,
      _ => 0,
    };
  }
}

final class FamilyCounterController extends EventControllerNotifier<int, CounterEvent> {
  FamilyCounterController(this.initialValue);

  final int initialValue;

  @override
  Future<int> build() async {
    return initialValue;
  }

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case AddCounterEvent(:final amount):
        state = AsyncData(_currentValue + amount);
    }
  }

  int get _currentValue {
    return switch (state) {
      AsyncData(:final value) => value,
      _ => initialValue,
    };
  }
}

void main() {
  test('dispatch routes events to onEvent', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const AddCounterEvent(2));

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 2));
  });

  test('Ref.dispatch supports regular and autoDispose providers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final regularDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(counterProvider, const AddCounterEvent(3));
    });
    final autoDisposeDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(autoDisposeCounterProvider, const AddCounterEvent(4));
    });

    await container.read(regularDispatchProvider);
    await container.read(autoDisposeDispatchProvider);

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 3));
    expect(
      container.read(autoDisposeCounterProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 4),
    );
  });

  test('Ref.dispatch supports family and autoDispose.family providers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final familyDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(familyCounterProvider(10), const AddCounterEvent(5));
    });
    final autoDisposeFamilyDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(autoDisposeFamilyCounterProvider(20), const AddCounterEvent(6));
    });

    await container.read(familyDispatchProvider);
    await container.read(autoDisposeFamilyDispatchProvider);

    expect(
      container.read(familyCounterProvider(10)),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 15),
    );
    expect(
      container.read(autoDisposeFamilyCounterProvider(20)),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 26),
    );
  });

  testWidgets('WidgetRef.dispatch routes events through the same boundary', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, child) {
            widgetRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await widgetRef.dispatch(counterProvider, const AddCounterEvent(8));

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 8));
  });
}
