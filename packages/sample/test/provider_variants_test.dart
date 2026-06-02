import 'package:blocpod_sample/src/provider_variants/provider_variants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dispatch supports regular autoDispose family and autoDispose.family providers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(regularVariantDispatchProvider);
    await container.read(autoDisposeVariantDispatchProvider);
    await container.read(familyVariantDispatchProvider(10));
    await container.read(autoDisposeFamilyVariantDispatchProvider(20));

    expect(container.read(regularVariantProvider), isA<AsyncData<int>>().having((value) => value.value, 'regular', 1));
    expect(
      container.read(autoDisposeVariantProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'autoDispose', 1),
    );
    expect(
      container.read(familyVariantProvider(10)),
      isA<AsyncData<int>>().having((value) => value.value, 'family', 11),
    );
    expect(
      container.read(autoDisposeFamilyVariantProvider(20)),
      isA<AsyncData<int>>().having((value) => value.value, 'autoDisposeFamily', 21),
    );
  });
}
