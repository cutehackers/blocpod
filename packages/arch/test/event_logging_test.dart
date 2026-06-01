import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class LoggingEvent {
  const LoggingEvent();
}

final class IncrementEvent extends LoggingEvent {
  const IncrementEvent();
}

final class ThrowEvent extends LoggingEvent {
  const ThrowEvent();
}

final class ParentEvent extends LoggingEvent {
  const ParentEvent();
}

final class ChildEvent extends LoggingEvent {
  const ChildEvent();
}

final class ThrowMetadataEvent extends LoggingEvent {
  const ThrowMetadataEvent();
}

final class ThrowEventAndMetadataEvent extends LoggingEvent {
  const ThrowEventAndMetadataEvent();
}

final loggingProvider = AsyncNotifierProvider<LoggingController, int>(LoggingController.new);

final explodingEqualityProvider = AsyncNotifierProvider<ExplodingEqualityController, ExplodingEquality>(
  ExplodingEqualityController.new,
);

final class LoggingController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  Future<int> build() async {
    return 0;
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {
    switch (event) {
      case IncrementEvent():
        final value = switch (state) {
          AsyncData(:final value) => value,
          _ => 0,
        };
        state = AsyncData(value + 1);
      case ThrowEvent():
        throw StateError('boom');
      case ParentEvent():
        await dispatch(const ChildEvent());
        state = const AsyncData(10);
      case ChildEvent():
        state = const AsyncData(5);
      case ThrowMetadataEvent():
        state = const AsyncData(20);
      case ThrowEventAndMetadataEvent():
        throw StateError('handler failed');
    }
  }

  @override
  Map<String, Object?> metadataFor(LoggingEvent event) {
    return switch (event) {
      IncrementEvent() => const {'kind': 'increment'},
      ThrowEvent() => const {'kind': 'throw'},
      ParentEvent() => const {'kind': 'parent'},
      ChildEvent() => const {'kind': 'child'},
      ThrowMetadataEvent() => throw StateError('metadata failed'),
      ThrowEventAndMetadataEvent() => throw StateError('metadata failed'),
    };
  }
}

final class ExplodingEquality {
  const ExplodingEquality(this.value);

  final int value;

  @override
  bool operator ==(Object other) {
    throw StateError('payload equality should not be called');
  }

  @override
  int get hashCode => value.hashCode;
}

final class ExplodingEqualityEvent {
  const ExplodingEqualityEvent();
}

final class ExplodingEqualityController extends EventControllerNotifier<ExplodingEquality, ExplodingEqualityEvent> {
  @override
  Future<ExplodingEquality> build() async {
    return const ExplodingEquality(0);
  }

  @override
  Future<void> onEvent(ExplodingEqualityEvent event) async {
    state = const AsyncData(ExplodingEquality(1));
  }

  @override
  bool updateShouldNotify(AsyncValue<ExplodingEquality> previous, AsyncValue<ExplodingEquality> next) {
    return !identical(previous, next);
  }
}

final class CollectingEventLogger implements EventLogger {
  final records = <EventLogRecord>[];

  @override
  void log(EventLogRecord record) {
    records.add(record);
  }
}

final class ThrowingEventLogger implements EventLogger {
  @override
  void log(EventLogRecord record) {
    throw StateError('logger failed');
  }
}

void main() {
  test('default logger is no-op and dispatch still succeeds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('dispatch logs before and after AsyncValue state kinds', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(logger.records, hasLength(1));
    expect(logger.records.single.controllerName, 'LoggingController');
    expect(logger.records.single.eventName, 'IncrementEvent');
    expect(logger.records.single.beforeStateKind, AsyncValueKind.data);
    expect(logger.records.single.afterStateKind, AsyncValueKind.data);
    expect(logger.records.single.hasChanged, isTrue);
    expect(logger.records.single.metadata, containsPair('kind', 'increment'));
    expect(logger.records.single.error, isNull);
    expect(logger.records.single.stackTrace, isNull);
  });

  test('dispatch logs thrown errors and preserves the original stack trace', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(loggingProvider.notifier).dispatch(const ThrowEvent()),
      throwsA(isA<StateError>()),
    );

    expect(logger.records, hasLength(1));
    expect(logger.records.single.eventName, 'ThrowEvent');
    expect(logger.records.single.error, isA<StateError>());
    expect(logger.records.single.stackTrace, isNotNull);
  });

  test('nested dispatches keep one trace id and create child spans', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const ParentEvent());

    final parent = logger.records.singleWhere((record) => record.eventName == 'ParentEvent');
    final child = logger.records.singleWhere((record) => record.eventName == 'ChildEvent');

    expect(child.traceContext.traceId, parent.traceContext.traceId);
    expect(parent.traceContext.traceId, startsWith('trace-'));
    expect(parent.traceContext.spanId, startsWith('span-'));
    expect(child.traceContext.spanId, startsWith('span-'));
    expect(parent.traceContext.parentSpanId, isNull);
    expect(child.traceContext.parentSpanId, parent.traceContext.spanId);
    expect(child.traceContext.spanId, isNot(parent.traceContext.spanId));
  });

  test('metadata failures do not break successful dispatches', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const ThrowMetadataEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 20));
  });

  test('metadata failures do not mask original event handler errors', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(loggingProvider.notifier).dispatch(const ThrowEventAndMetadataEvent()),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'handler failed')),
    );

    expect(logger.records, hasLength(1));
    expect(logger.records.single.eventName, 'ThrowEventAndMetadataEvent');
    expect(
      logger.records.single.error,
      isA<StateError>().having((error) => error.message, 'message', 'handler failed'),
    );
    expect(logger.records.single.stackTrace, isNotNull);
    expect(logger.records.single.metadata, isEmpty);
  });

  test('logger failures do not break application flow', () async {
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(ThrowingEventLogger())]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('hasChanged does not invoke AsyncData payload equality', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(explodingEqualityProvider.notifier).dispatch(const ExplodingEqualityEvent());

    expect(logger.records, hasLength(1));
    expect(logger.records.single.hasChanged, isTrue);
  });

  test('TraceContext.run exposes current context only inside the async zone', () async {
    final context = TraceContext.root(startedAt: DateTime.utc(2026, 6));

    expect(TraceContext.current, isNull);
    await TraceContext.run(context, () async {
      await Future<void>.delayed(Duration.zero);
      expect(TraceContext.current, same(context));
    });
    expect(TraceContext.current, isNull);
  });
}
