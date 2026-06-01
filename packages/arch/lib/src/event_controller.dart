import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Public dispatch boundary for event-driven controllers.
abstract class EventController<E> {
  /// Dispatches [event] through the controller.
  Future<void> dispatch(E event);
}

/// Riverpod [AsyncNotifier] base class with a single event dispatch boundary.
abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S>
    implements EventController<E> {
  @override
  Future<void> dispatch(E event) async {
    await future;
    await onEvent(event);
  }

  /// Handles one dispatched event.
  @protected
  Future<void> onEvent(E event);
}

/// Dispatch helper for providers and other non-widget Riverpod code.
extension RefEventDispatcherX on Ref {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}

/// Dispatch helper for widgets.
extension WidgetRefEventDispatcherX on WidgetRef {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}
