import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class VariantIncremented {
  const VariantIncremented();
}

final regularVariantProvider =
    AsyncNotifierProvider<VariantCounterController, int>(
      () => VariantCounterController(
        providerName: 'regularVariantProvider',
        providerKind: 'regular',
      ),
    );

final autoDisposeVariantProvider =
    AsyncNotifierProvider.autoDispose<VariantCounterController, int>(
      () => VariantCounterController(
        providerName: 'autoDisposeVariantProvider',
        providerKind: 'autoDispose',
      ),
    );

final familyVariantProvider =
    AsyncNotifierProvider.family<FamilyVariantCounterController, int, int>(
      (initialValue) => FamilyVariantCounterController(
        initialValue,
        providerName: 'familyVariantProvider',
        providerKind: 'family',
      ),
    );

final autoDisposeFamilyVariantProvider = AsyncNotifierProvider.autoDispose
    .family<FamilyVariantCounterController, int, int>(
      (initialValue) => FamilyVariantCounterController(
        initialValue,
        providerName: 'autoDisposeFamilyVariantProvider',
        providerKind: 'autoDisposeFamily',
      ),
    );

final regularVariantDispatchProvider = Provider<Future<void>>((ref) {
  return ref.dispatch(regularVariantProvider, const VariantIncremented());
});

final autoDisposeVariantDispatchProvider = Provider<Future<void>>((ref) {
  return ref.dispatch(autoDisposeVariantProvider, const VariantIncremented());
});

final familyVariantDispatchProvider = Provider.family<Future<void>, int>((
  ref,
  initialValue,
) {
  return ref.dispatch(
    familyVariantProvider(initialValue),
    const VariantIncremented(),
  );
});

final autoDisposeFamilyVariantDispatchProvider =
    Provider.family<Future<void>, int>((ref, initialValue) {
      return ref.dispatch(
        autoDisposeFamilyVariantProvider(initialValue),
        const VariantIncremented(),
      );
    });

final class VariantCounterController
    extends EventControllerNotifier<int, VariantIncremented> {
  VariantCounterController({
    required this.providerName,
    required this.providerKind,
  });

  final String providerName;
  final String providerKind;

  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(VariantIncremented event) async {
    state = AsyncData(_currentValue + 1);
  }

  int get _currentValue => switch (state) {
    AsyncData(:final value) => value,
    _ => 0,
  };

  @override
  Map<String, Object?> controllerMetadata() {
    return <String, Object?>{
      'providerName': providerName,
      'providerKind': providerKind,
      'samplePanel': 'Provider variants',
    };
  }
}

final class FamilyVariantCounterController
    extends EventControllerNotifier<int, VariantIncremented> {
  FamilyVariantCounterController(
    this.initialValue, {
    required this.providerName,
    required this.providerKind,
  });

  final int initialValue;
  final String providerName;
  final String providerKind;

  @override
  Future<int> build() async => initialValue;

  @override
  Future<void> onEvent(VariantIncremented event) async {
    state = AsyncData(_currentValue + 1);
  }

  int get _currentValue => switch (state) {
    AsyncData(:final value) => value,
    _ => initialValue,
  };

  @override
  Map<String, Object?> controllerMetadata() {
    return <String, Object?>{
      'providerName': providerName,
      'providerKind': providerKind,
      'providerArg': initialValue,
      'samplePanel': 'Provider variants',
    };
  }
}
