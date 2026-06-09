import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'counter/counter_controller.dart';
import 'logging/in_memory_log_sink.dart';
import 'provider_variants/provider_variants.dart';
import 'todos/todo_controller.dart';

final class BlocpodSampleApp extends StatefulWidget {
  const BlocpodSampleApp({super.key});

  @override
  State<BlocpodSampleApp> createState() => _BlocpodSampleAppState();
}

final class _BlocpodSampleAppState extends State<BlocpodSampleApp> {
  final InMemoryLogSink _sink = InMemoryLogSink();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        inMemoryLogSinkProvider.overrideWithValue(_sink),
        eventLoggerProvider.overrideWithValue(BlocpodEventLogger(_sink)),
      ],
      child: const MaterialApp(title: 'Blocpod Sample', home: SampleHome()),
    );
  }

  @override
  void dispose() {
    _sink.dispose();
    super.dispose();
  }
}

final class SampleHome extends ConsumerWidget {
  const SampleHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocpod Sample')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CounterPanel(),
              SizedBox(height: 16),
              TodoPanel(),
              SizedBox(height: 16),
              ProviderVariantsPanel(),
              SizedBox(height: 16),
              EventLogPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

final class CounterPanel extends ConsumerWidget {
  const CounterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = switch (ref.watch(counterProvider)) {
      AsyncData(:final value) => value,
      _ => 0,
    };
    final notifier = ref.read(counterProvider.notifier);

    return _SampleSection(
      title: 'Counter events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Count: $count', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: () => notifier.dispatch(const CounterIncremented(1)), child: const Text('+1')),
              OutlinedButton(onPressed: () => notifier.dispatch(const CounterDecremented()), child: const Text('-1')),
              OutlinedButton(onPressed: () => notifier.dispatch(const CounterReset()), child: const Text('Reset')),
            ],
          ),
        ],
      ),
    );
  }
}

final class TodoPanel extends ConsumerWidget {
  const TodoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = switch (ref.watch(todoProvider)) {
      AsyncData(:final value) => value,
      _ => const [],
    };
    final notifier = ref.read(todoProvider.notifier);

    return _SampleSection(
      title: 'UseCase and Result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => notifier.dispatch(const TodoLoaded()),
                child: const Text('Load todos'),
              ),
              OutlinedButton(
                onPressed: () => notifier.dispatch(const TodoAdded('Try Blocpod')),
                child: const Text('Add todo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final todo in todos) Text(todo.title),
        ],
      ),
    );
  }
}

final class ProviderVariantsPanel extends ConsumerWidget {
  const ProviderVariantsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regular = switch (ref.watch(regularVariantProvider)) {
      AsyncData(:final value) => value,
      _ => 0,
    };
    final autoDispose = switch (ref.watch(autoDisposeVariantProvider)) {
      AsyncData(:final value) => value,
      _ => 0,
    };
    final family = switch (ref.watch(familyVariantProvider(10))) {
      AsyncData(:final value) => value,
      _ => 10,
    };
    final autoDisposeFamily = switch (ref.watch(autoDisposeFamilyVariantProvider(20))) {
      AsyncData(:final value) => value,
      _ => 20,
    };

    return _SampleSection(
      title: 'Provider variants',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text('Regular: $regular'),
              Text('Auto dispose: $autoDispose'),
              Text('Family(10): $family'),
              Text('Auto family(20): $autoDisposeFamily'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => ref.dispatch(regularVariantProvider, const VariantIncremented()),
                child: const Text('Regular'),
              ),
              OutlinedButton(
                onPressed: () => ref.dispatch(autoDisposeVariantProvider, const VariantIncremented()),
                child: const Text('Auto dispose'),
              ),
              OutlinedButton(
                onPressed: () => ref.dispatch(familyVariantProvider(10), const VariantIncremented()),
                child: const Text('Family'),
              ),
              OutlinedButton(
                onPressed: () => ref.dispatch(autoDisposeFamilyVariantProvider(20), const VariantIncremented()),
                child: const Text('Auto family'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class EventLogPanel extends ConsumerWidget {
  const EventLogPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sink = ref.watch(inMemoryLogSinkProvider);

    return _SampleSection(
      title: 'Event log',
      child: ListenableBuilder(
        listenable: sink,
        builder: (context, _) {
          final entries = sink.entries.reversed.take(8).toList();
          if (entries.isEmpty) {
            return const Text('No events yet');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.message),
                      if (_visibleMetadata(entry.metadata).isNotEmpty)
                        Text(_visibleMetadata(entry.metadata), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

const Set<String> _reservedLogMetadataKeys = <String>{
  'phase',
  'traceId',
  'spanId',
  'parentSpanId',
  'controllerName',
  'eventName',
  'durationMicros',
  'transitionIndex',
  'previousStateKind',
  'nextStateKind',
  'hasChanged',
  'previousStateLabel',
  'nextStateLabel',
  'stateMetadata',
};

String _visibleMetadata(Map<String, Object?> metadata) {
  return metadata.entries
      .where((entry) => !_reservedLogMetadataKeys.contains(entry.key) && entry.value != null)
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' | ');
}

final class _SampleSection extends StatelessWidget {
  const _SampleSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
