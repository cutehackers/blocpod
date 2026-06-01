# Blocpod 아키텍처

Blocpod은 Riverpod의 provider 런타임을 유지하면서 BLoC 스타일 이벤트 dispatch, 상태 전환 로깅, clean architecture 기본 요소를 워크스페이스 패키지로 표준화한다.

## 핵심 아키텍처 소스 계약

Blocpod의 아키텍처 소스 계약은 워크스페이스 패키지에 둔다.

1. `packages/arch/lib/src/result.dart`
2. `packages/arch/lib/src/use_case.dart`
3. `packages/arch/lib/src/event_controller.dart`
4. `packages/arch/lib/src/trace_context.dart`
5. `packages/arch/lib/src/event_log_record.dart`
6. `packages/arch/lib/src/event_logger.dart`
7. `packages/logger/lib/src/`
8. `packages/arch_logger/lib/src/`

애플리케이션은 안정적인 public barrel을 import한다.

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
```

의존성 방향은 고정한다.

- `blocpod_arch`는 Flutter와 `flutter_riverpod`에 의존한다.
- `blocpod_logger`는 `debugPrint` 출력용 Flutter에 의존한다.
- `blocpod_arch_logger`는 `blocpod_arch`와 `blocpod_logger`에 의존한다.
- `blocpod_arch`는 `blocpod_logger`를 import하지 않는다.
- `blocpod_logger`는 `blocpod_arch`를 import하지 않는다.

컨트롤러는 `EventControllerNotifier<State, Event>`를 상속하고 public action API로 `dispatch`만 노출한다. 위젯은 `ref.dispatch(provider, event)`로 이벤트를 전달한다. 이 아키텍처에서는 generated `@riverpod` controller class를 만들지 않는다.

## 로깅 경계

`blocpod_arch`는 `eventLoggerProvider`를 통해 구조화된 event record를 내보내며 기본값은 no-op logging이다. 애플리케이션은 adapter package의 provider override로 구체적인 출력을 설치한다.
