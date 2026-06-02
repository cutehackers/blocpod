# 아키텍처

---

## 개요

이 가이드는 event-driven state management를 사용하는 Riverpod의
AsyncNotifier 패턴 기반 Flutter Clean Architecture 구현을 설명합니다.
State-Domain-DTO 데이터 플로우를 따르는 기능 기반(feature-based)
폴더 구조를 따릅니다.

### 핵심 특성

- 엄격한 의존성 역전: 의존성은 내부로 흐릅니다
  (presentation → domain ← data)
- `lib/src/features/<feature>/` 하위의 기능 기반 모듈 구조
- 명시적 `Provider` / `AsyncNotifierProvider` 선언을 사용하는 Riverpod 3.x
- Freezed를 활용한 불변 domain/state 모델 (적합한 경우)
- 비즈니스 로직을 캡슐화하는 Use Case 패턴
- 데이터 소스를 추상화하는 Repository 패턴

### 핵심 원칙

- **관심사 분리(SoC)**: 각 계층이 명확하고 독립적인 책임을 갖습니다
- **의존성 역전**: 상위 계층은 하위 계층에 직접 의존하지 않습니다
- **테스트 가능성**: 각 계층을 독립적으로 테스트할 수 있습니다
- **확장성**: 기존 코드 영향도를 최소화하며 새 기능을 추가할 수 있습니다
- **Event-Driven State**: 이벤트를 통해 명확하고 추적 가능한 상태 변경 수행
- **Type Safety**: Dart sealed events + Riverpod, Freezed를 활용해 상태/DTO 사용성 강화

---

## 아키텍처 계층

```
┌─────────────────────────────────────────┐
│         Presentation Layer              │
│   (UI, State, Events, AsyncNotifier)    │
│   - Widget                              │
│   - Event (User Actions)                │
│   - AsyncNotifier (Event Controller)    │
│   - AsyncValue<State>                   │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│          Domain Layer                   │
│      (Business Logic, Domain Models)    │
│   - Domain Model                        │
│   - Repository Interface                │
│   - UseCase                             │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           Data Layer                    │
│    (Data Sources, DTOs, Repository)     │
│   - DTO (Data Transfer Object)          │
│   - DataSource (Remote/Local)           │
│   - Repository Implementation           │
└─────────────────────────────────────────┘
```

---

## 계층 책임 및 제약

### Presentation

- 위치: `lib/src/features/<feature>/presentation/`
- Controller는 `EventControllerNotifier`를 상속하고 `switch`로 `onEvent`를
  구현합니다.
- Event는 `sealed`이며 `{Feature}{Action}Event` 네이밍을 따릅니다.
- UI는 `RefEventDispatcherX` (`ref.dispatch(...)`)로 event를 dispatch합니다.
- 핵심 정의는 `lib/src/core/arch/event_controller.dart`에 위치합니다.
- State는 controller 내에 두고, 100줄을 초과하면 분리 파일로 이동합니다.
- Presentation에서는 Data 계층 타입을 import하지 않습니다.
  - `presentation/` 아래에 중첩된 `<feature>` 폴더를 만들지 않습니다.

### Domain

- 위치: `lib/src/features/<feature>/domain/`
- Domain model: 불변 모델(Freezed는 사용성을 높일 때 허용).
- Repository: interface만 정의.
- Use Case: 파일당 하나의 액션, `call(params)`만 사용.
- Presentation 또는 Data를 import하지 않습니다.

### Data

- 위치: `lib/src/features/<feature>/data/`
- Data Source: 원격/로컬 인터페이스와 구현체.
- DTO: domain model과 상호 변환.
- Repository implementation: data source orchestration 및 DTO ↔ domain model 매핑.
- Presentation을 import하지 않습니다.

### Cross-Cutting (Core)

- 위치: `lib/src/core/`
- 여러 feature에서 재사용되는 공통 유틸, 기본 추상화, 인프라를 둡니다.

---

## Core Architecture Source Contract

아키텍처는 아래 세 개의 core 파일에 의존합니다. 이 문서만으로 프로젝트를
부트스트랩할 때는 이 파일들을 먼저 만들고, 아키텍처 자체를 변경하는 경우가
아니라면 public API를 안정적으로 유지합니다.

생성 순서:

1. `lib/src/core/arch/result.dart`
2. `lib/src/core/arch/use_case.dart`
3. `lib/src/core/arch/event_controller.dart`

### `lib/src/core/arch/result.dart`

`Result<T>`는 성공/실패가 있는 작업을 표현하는 domain/data 경계 타입입니다.
Use case와 repository는 예상 가능한 domain/data 실패를 throw하지 않고 이 타입으로
반환합니다.

````dart
// Copyright 2024 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Utility class to wrap result data.
///
/// Evaluate the result using a switch statement:
/// ```dart
/// switch (result) {
///   case Ok(): {
///     print(result.value);
///   }
///   case Error(): {
///     print(result.error);
///   }
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Creates a successful [Result], completed with the specified [value].
  const factory Result.ok(T value) = Ok._;

  /// Creates an error [Result], completed with the specified [error].
  const factory Result.error(Exception error) = Error._;
}

/// Subclass of Result for values.
final class Ok<T> extends Result<T> {
  const Ok._(this.value);

  /// Returned value in result.
  final T value;

  @override
  String toString() => 'Result<$T>.ok($value)';
}

/// Subclass of Result for errors.
final class Error<T> extends Result<T> {
  const Error._(this.error);

  /// Returned error in result.
  final Exception error;

  @override
  String toString() => 'Result<$T>.error($error)';
}
````

### `lib/src/core/arch/use_case.dart`

`UseCase<Output, Params>`는 domain orchestration interface입니다. Use case는 하나의
params 객체를 받고 `Future<Result<Output>>`를 반환합니다. 파라미터가 없는 액션은
`void`, `Null`, 빈 map 대신 `NoParams`를 사용합니다.

```dart
import 'result.dart';

/// Base interface for application use cases.
///
/// Use cases should be pure orchestration: accept [Params], delegate to
/// repositories, and return a [Result] for success/error handling.
abstract class UseCase<Output, Params> {
  const UseCase();

  Future<Result<Output>> call(Params params);
}

/// Marker class for use cases that do not require parameters.
final class NoParams {
  const NoParams();
}
```

### `lib/src/core/arch/event_controller.dart`

`EventControllerNotifier<S, E>`는 presentation state boundary입니다. UI 코드는
`ref.dispatch(...)`로 sealed event를 dispatch하고, controller는 `onEvent` 안에서
event를 라우팅합니다. `log` hook은 기본 no-op이며, dispatch API를 바꾸지 않고
feature별 observability를 선택적으로 연결하기 위한 확장 지점입니다.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class EventController<E> {
  Future<void> dispatch(E event);
}

abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S> implements EventController<E> {
  @override
  Future<void> dispatch(E event) async {
    final before = state;
    try {
      await onEvent(event);
    } finally {
      log(event, before, state);
    }
  }

  @protected
  Future<void> onEvent(E event);

  @protected
  void log(E event, AsyncValue<S> before, AsyncValue<S> after) {}
}

extension RefEventDispatcherX on Ref {
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, E, S>(AsyncNotifierProvider<N, S> provider, E event) {
    return read(provider.notifier).dispatch(event);
  }
}

extension WidgetRefEventDispatcherX on WidgetRef {
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, E, S>(AsyncNotifierProvider<N, S> provider, E event) {
    return read(provider.notifier).dispatch(event);
  }
}
```

### Core Contract Rules

- 이 추상화를 feature 내부에 중복 정의하지 않습니다.
- Domain use case는 `use_case.dart`와 `result.dart`를 import합니다.
- Domain repository는 async operation에 `Future<Result<T>>`를 반환합니다.
- Presentation controller는 `event_controller.dart`를 import하고
  `AsyncNotifierProvider`로 state를 노출합니다.
- Widget은 controller handler를 직접 호출하지 않고 `ref.dispatch(provider, event)`로
  event를 dispatch합니다.
- Controller provider는 일반, `autoDispose`, `family`, `autoDispose.family` variant를
  사용할 수 있습니다.
- Family argument는 controller 생성자로 전달하고 controller field에서 읽습니다.
- `@riverpod`로 controller class를 생성하지 않습니다. 생성된 `_$Controller` 상속은
  `EventControllerNotifier` 상속과 충돌합니다.
- core API가 바뀌면 `docs/ARCHITECTURE.md`와 `docs/ARCHITECTURE-ko.md`를 같은
  변경에서 함께 갱신합니다.

---

## 폴더 구조

### Feature Based

```
lib/
├── main.dart
└── src/
    ├── core/
    │   ├── arch/
    │   │   ├── event_controller.dart
    │   │   ├── result.dart
    │   │   └── use_case.dart
    │   ├── errors/
    │   │   ├── exceptions.dart
    │   │   └── failures.dart
    │   ├── network/
    │   │   └── dio_client.dart
    │   └── providers/
    │       └── dio_provider.dart
    │
    ├── features/
    │   ├── auth/
    │   │   ├── data/
    │   │   │   ├── models/                    # DTO models only
    │   │   │   │   ├── login_request_dto.dart
    │   │   │   │   ├── login_response_dto.dart
    │   │   │   │   └── user_dto.dart
    │   │   │   ├── auth_local_data_source.dart
    │   │   │   ├── auth_remote_data_source.dart
    │   │   │   └── auth_repository_impl.dart
    │   │   │
    │   │   ├── domain/
    │   │   │   ├── entities/                  # Domain models only
    │   │   │   │   └── user.dart
    │   │   │   ├── auth_repository.dart
    │   │   │   ├── login_use_case.dart
    │   │   │   ├── logout_use_case.dart
    │   │   │   └── get_current_user_use_case.dart
    │   │   │
    │   │   └── presentation/
    │   │       ├── widgets/                   # Reusable widgets only
    │   │       │   ├── login_form.dart
    │   │       │   └── password_field.dart
    │   │       ├── auth_controller.dart
    │   │       ├── auth_event.dart
    │   │       ├── auth_state.dart
    │   │       ├── login_page.dart
    │   │       └── register_page.dart
    │   │
    │   └── todo/
    │       ├── data/
    │       │   └── models/
    │       ├── domain/
    │       │   └── entities/
    │       └── presentation/
    │           └── widgets/
```

위 구조는 아래 규칙을 반영합니다 (`data/`, `domain/`, `presentation/` 하위에
중첩 feature 폴더를 두지 않음).

### 주요 구조 결정 사항

**폴더는 최소화되고 목적이 분명해야 합니다:**

- `data/` - API 호출, 로컬 스토리지, data source 관리를 담당하는 data layer
- `domain/` - use case와 domain model을 담는 비즈니스 로직 레이어
  (framework 독립적)
- `presentation/` - page, screen, 재사용 가능한 widget을 담는 UI 레이어
- `data/models/` - DTO 전용 (DTO가 있는 경우에만 생성)
- `domain/entities/` - domain model 전용 (domain model이 있는 경우에만 생성)
- `presentation/widgets/` - 재사용 UI 컴포넌트 전용 (widgets가 있는 경우에만 생성)
- `data/`, `domain/`, `presentation/` 내부에 기능 중첩 폴더는 만들지 않습니다.
- 허용된 하위 폴더만 존재합니다.
  (예: `data/models`, `domain/entities`, `presentation/widgets`).

### 코드 구성 (Feature-First Structure)

이 섹션은 이 프로젝트의 feature-first 코드 구성을 정의하는 기준 문서입니다.

- 기능 기반 폴더 구조를 따릅니다: `lib/src/features/<feature>/{data,domain,presentation}/`
- `data/`, `domain/`, `presentation/` 아래에 중첩 feature 폴더를 만들지 않습니다
- 허용된 하위 폴더만 사용:
  `data/models/`, `domain/entities/`, `presentation/widgets/`
- 빈 디렉토리는 만들지 않습니다. 파일이 있을 때만 디렉토리를 생성합니다
- 최대 파일 길이: 500줄 (초과 시 분리; State가 100줄 초과 시 별도 파일)
- 파일명: `snake_case.dart`, 클래스명: `PascalCase`

⚠️ 규칙: 빈 디렉토리를 절대 만들지 않습니다. 실제 파일이 배치될 때만 폴더를
생성하세요.

**feature 내 파일은 타입별로 정렬됩니다:**

- Repository implementation: `{feature}_repository_impl.dart`
- Data Source: `{feature}_{type}_data_source.dart`
- Use Case: `{action}_use_case.dart`
- Page: `{name}_page.dart` (`presentation/` 내부)
- Controller: `{feature}_controller.dart` (`presentation/` 내부)
- Provider: 순수 controller provider는 controller 근처에 둡니다. Data layer 구현체를 생성하는 dependency provider는 `lib/src/features/<feature>/{feature}_providers.dart`로 이동합니다.

### 설정 및 상수

단일 글로벌 상수 파일은 사용하지 않습니다. 아래 패턴 중 하나를 선택하세요.

- feature 범위 설정: `lib/src/features/<feature>/data/<feature>_config.dart`
- 공유 설정용 Core config: `lib/src/core/config/app_config.dart`
- 런타임 값은 `--dart-define` + 작은 `AppEnv` wrapper로 주입
- 운영 중 조정은 remote config 또는 backend-driven flags 사용

각 상수는 영향 범위가 명확한 코드 근처에 배치하고, 이름과 소유권을 명확히 합니다.

---

## Feature Scaffold Contract

새 feature를 만들 때는 이 scaffold를 사용합니다. Controller provider는 명시적으로
선언하고, controller 상속은 항상 `EventControllerNotifier`로 고정합니다.

### Standard Controller Provider

```dart
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(authRepositoryProvider));
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

final class AuthController extends EventControllerNotifier<AuthState, AuthEvent> {
  @override
  Future<AuthState> build() async {
    final loadSession = ref.watch(loadSessionUseCaseProvider);
    final result = await loadSession(const NoParams());

    return switch (result) {
      Ok(:final value) => AuthState.fromSession(value),
      Error(:final error) => throw error,
    };
  }

  @override
  Future<void> onEvent(AuthEvent event) async {
    switch (event) {
      case AuthSignInEvent e:
        await _onSignIn(e);
      case AuthSignOutEvent e:
        await _onSignOut(e);
    }
  }

  Future<void> _onSignIn(AuthSignInEvent event) async {
    final signIn = ref.read(loginUseCaseProvider);
    final result = await signIn(LoginParams(email: event.email, password: event.password));

    state = switch (result) {
      Ok(:final value) => AsyncData(AuthState.fromUser(value)),
      Error(:final error) => AsyncError(error, StackTrace.current),
    };
  }

  Future<void> _onSignOut(AuthSignOutEvent event) async {
    // Route event-specific work through a private handler.
  }
}
```

### Family and AutoDispose Controllers

controller instance가 ID 같은 안정적인 argument로 scope될 때는 `family`를 사용합니다.
detail screen, tab, dialog처럼 마지막 listener가 사라질 때 state도 사라져야 하는
controller는 `autoDispose.family`를 우선 사용합니다.

```dart
final cartControllerProvider = AsyncNotifierProvider.autoDispose.family<CartController, CartState, CartId>(
  CartController.new,
);

final class CartController extends EventControllerNotifier<CartState, CartEvent> {
  CartController(this.cartId);

  final CartId cartId;

  @override
  Future<CartState> build() async {
    final loadCart = ref.watch(loadCartUseCaseProvider);
    final result = await loadCart(LoadCartParams(cartId: cartId));

    return switch (result) {
      Ok(:final value) => CartState.fromCart(value),
      Error(:final error) => throw error,
    };
  }

  @override
  Future<void> onEvent(CartEvent event) async {
    switch (event) {
      case RefreshCartEvent e:
        await _onRefresh(e);
    }
  }

  Future<void> _onRefresh(RefreshCartEvent event) async {
    ref.invalidateSelf();
  }
}
```

### Provider Rules

- Controller provider는 명시적인 `AsyncNotifierProvider` 선언입니다.
- Controller class는 항상 `EventControllerNotifier<State, Event>`를 상속합니다.
- `@riverpod class FeatureController extends _$FeatureController`는 사용하지 않습니다.
  Dart 단일 상속 때문에 generated base와 `EventControllerNotifier`를 함께 상속할 수
  없습니다.
- Data source, repository, use case dependency에는 기본적으로 `Provider<T>`를
  사용합니다. 값의 lifecycle이 다를 때만 다른 Riverpod provider type을 선택합니다.
- UI는 `ref.watch(featureControllerProvider)`로 state를 받고
  `ref.dispatch(featureControllerProvider, event)`로 action을 전달합니다.

---

## Data Flow

### 전체 Data Flow Diagram

```
User Interaction
      ↓
┌─────────────────────────────────────────┐
│  Presentation Layer                     │
│  Widget → dispatches Event              │
│           ↓                             │
│  AsyncNotifier controller handles Event │
│           ↓                             │
│  calls UseCase                          │
│           ↓                             │
│  updates AsyncValue<State>              │
│  - AsyncLoading                         │
│  - AsyncData<State>                     │
│  - AsyncError                           │
│           ↓                             │
│  Widget rebuilds via ref.watch()        │
└─────────────┬───────────────────────────┘
              ↓ calls
┌─────────────────────────────────────────┐
│  Domain Layer                           │
│  UseCase (Business Logic)               │
│           ↓                             │
│  processes Domain Model                 │
│  - Pure Dart objects                    │
│  - Business rules                       │
│           ↓ through                     │
│  Repository Interface                   │
└─────────────┬───────────────────────────┘
              ↓ implements
┌─────────────────────────────────────────┐
│  Data Layer                             │
│  Repository Implementation              │
│           ↓                             │
│  DataSource (Remote/Local)              │
│           ↓                             │
│  DTO (Data Transfer Object)             │
│  - JSON serialization                   │
│  - API response mapping                 │
│           ↓ converts to                 │
│  Domain Model                           │
└─────────────────────────────────────────┘
```

### AsyncNotifier 기반 Event-Driven Flow

```
1. User Action (Button Click)
      ↓
2. Widget dispatches Event
   ref.dispatch(authControllerProvider, const AuthSignInEvent())
      ↓
3. Controller routes events via `onEvent` (switch) to private handlers
      ↓
4. AsyncValue automatically handles states
   - AsyncLoading (during execution)
   - AsyncData<State> (on success)
   - AsyncError (on failure)
      ↓
5. Widget listens to state changes
   ref.watch(authControllerProvider).when(
     loading: () => CircularProgressIndicator(),
     data: (state) => /* render state */,
     error: (error, stack) => /* show error */,
   )
```

### Event Dispatch Pattern

- UI는 `RefEventDispatcherX` (`ref.dispatch(...)`)로 event를 dispatch합니다.
- Controller는 `EventControllerNotifier`를 상속하고 sealed event에 대한 `switch`
  기반 `onEvent`를 구현합니다.
- 이벤트 라우팅은 `onEvent` 내부에서 수행하며 별도 handler 등록/초기화 훅을
  사용하지 않습니다.
- 선택 사항: `log`를 override해 event observability를 연결할 수 있습니다.
- 참고 구현: `lib/src/core/arch/event_controller.dart`.

### State, Domain Model, DTO 변환 Flow

```
API Response (JSON)
      ↓
Dto.fromJson()
      ↓
DTO (Data Layer)
      ↓
dto.toDomain()
      ↓
Domain Model (Domain Layer)
      ↓
UseCase processes Domain Model
      ↓
AsyncNotifier wraps in State
      ↓
AsyncValue<State> (Presentation Layer)
      ↓
Widget watches AsyncValue
      ↓
Widget displays UI
```

---

## 핵심 규칙

### Critical Architecture Rules

#### 1. Freezed 사용 규칙

```dart
// Correct: Freezed 3 models are abstract classes.
@freezed
abstract class User with _$User {
  const factory User({...}) = _User;
}
```

사용한 annotation에 필요한 generated file은 항상 생성합니다.

- `user.freezed.dart`
- `json_serializable`을 사용하는 경우 `user_dto.g.dart`

Freezed class를 non-abstract로 만들지 않습니다.

```dart
@freezed
class User with _$User { // Missing 'abstract'
```

#### 2. 파일 및 클래스 네이밍 규칙

generic file name은 사용하지 않습니다.

```
- utils.dart
- helpers.dart
- common.dart
- base.dart
```

구체적이고 선언적인 file name을 사용합니다.

```
- email_validator.dart
- date_formatter.dart
- network_error_handler.dart
- auth_token_registry.dart
```

금지되는 모호성: `utils.dart`, `helpers.dart`, `Util`, `Helper`, `Manager`를 피합니다.

```dart
// Correct: class names are explicit.
class EmailValidator { }           // Good: Specific purpose
class DateFormatter { }            // Good: Clear responsibility
class NetworkErrorHandler { }      // Good: Descriptive

// Wrong: generic class names hide responsibility.
class Util { }                     // Wrong: Too generic
class Helper { }                   // Wrong: Unclear purpose
class Manager { }                  // Wrong: Too vague
```

#### 3. 의미 있는 네이밍 규칙

**변수와 파라미터는 다음을 지켜야 합니다:**

- **Specific**: 담고 있는 값이 명확해야 합니다
- **Predictable**: 일관된 패턴을 따라야 합니다
- **Explicit**: 보편적으로 알려진 약어만 사용

```dart
// ✅ CORRECT: Meaningful variable names
final authenticatedUser = await _loginUseCase(...);
final activeTodoList = todos.where((t) => !t.isCompleted).toList();
final emailValidationError = _validateEmail(email);

// ❌ WRONG: Unclear variable names
final data = await _loginUseCase(...);     // 무엇을 담은 데이터인가?
final list = todos.where(...);             // 어떤 리스트인가?
final err = _validateEmail(email);         // 축약어

// ✅ CORRECT: Descriptive event field names
// todoTitle, todoDescription

// ❌ WRONG: Generic event field names
// title, desc
```

#### 4. AsyncValue 기반 State Management

```dart
state = const AsyncLoading();
state = await AsyncValue.guard(() async => /* use case */);
```

State에 별도 loading variant나 `isLoading` field를 추가하지 마세요. AsyncValue가 이미
loading 상태를 포함합니다. 화면이 계속 rendering될 수 있는 recoverable error는
`errorMessage`, `importIssues` 같은 domain-facing field로 State에 둘 수 있습니다.

#### 5. State 파일 위치 규칙

- State 모델이 **100줄 미만**이면 Controller와 같은 파일에 둡니다.
- State 모델이 **100줄 이상**이면 동일 폴더에서 별도 파일로 분리합니다.

#### 6. 계층 의존성 규칙

```dart
// ✅ CORRECT: Dependencies flow inward
// Presentation → Domain ← Data

// Presentation can import:
import 'package:pit_wall/src/features/auth/domain/entities/user.dart';         // ✅
import 'package:pit_wall/src/features/auth/domain/login_use_case.dart';         // ✅

// ❌ WRONG: Presentation importing Data
import 'package:pit_wall/src/features/auth/data/models/user_dto.dart';         // ❌

// ❌ WRONG: Domain importing Presentation or Data
import 'package:pit_wall/src/features/auth/presentation/auth_controller.dart';   // ❌
import 'package:pit_wall/src/features/auth/data/auth_repository_impl.dart';    // ❌
```

#### 7. DTO → Domain Model 변환 규칙

```dart
// ✅ CORRECT: Conversion methods in DTO
class UserDto {
  // toDomain in DTO (Data → Domain)
  User toDomain() {
    return User(...);
  }

  // fromDomain in DTO (Domain → Data)
  factory UserDto.fromDomain(User user) {
    return UserDto(...);
  }
}

// Wrong: conversion in domain model.
class User {
  UserDto toDto() { }  // Domain model should not know about DTO.
}
```

#### 8. Provider 조직 규칙

```dart
// Correct: explicit dependency providers.
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSourceImpl(ref.watch(dioProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(authRepositoryProvider));
});

// Correct: explicit EventControllerNotifier provider.
final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

// Correct: family + autoDispose when the controller is argument-scoped and disposable.
final cartControllerProvider = AsyncNotifierProvider.autoDispose.family<CartController, CartState, CartId>(
  CartController.new,
);

```

`@riverpod`로 controller class를 생성하지 않습니다. generated controller 상속은
`EventControllerNotifier`와 충돌합니다.

Data source나 repository implementation을 생성하는 provider 선언은 `presentation/`
아래에 두지 않습니다. 해당 조립은
`lib/src/features/<feature>/{feature}_providers.dart`에 두어 Presentation이 Data layer
type을 import하지 않게 합니다.

#### 9. Error Handling 규칙

```dart
// Correct: let AsyncValue.guard preserve thrown errors/stacks.
state = await AsyncValue.guard(() async {
  final result = await _useCase(...);
  return switch (result) {
    Ok(:final value) => SuccessState(value),
    Error(:final error) => throw error, // Throw to be caught by guard
  };
});

// Wrong: manual catch with StackTrace.current loses the original stack trace.
try {
  final result = await _useCase(...);
  state = AsyncData(result);
} catch (e) {
  state = AsyncError(e, StackTrace.current);  // Wrong stack trace
}
```

#### 10. Use Case 파라미터 규칙

```dart
// Correct: use a typed params object.
final class LoginParams {
  const LoginParams({required this.email, required this.password});

  final String email;
  final String password;
}

// Correct: use NoParams when no parameters are needed.
class GetCurrentUserUseCase implements UseCase<User, NoParams> {
  Future<Result<User>> call(NoParams params) async { }
}

// Wrong: don't use Map for parameters.
class LoginUseCase {
  Future<Result<User>> call(Map<String, dynamic> params) { }
}
```

#### 11. Dispatch-Only State 변경

- UI는 controller `dispatch`만 호출해야 합니다 (`RefEventDispatcherX` 사용).
- controller 메서드를 직접 호출하거나 `dispatch` 외부에서 state를 직접 변경하는
  행위는 금지됩니다.
- Controller public API는 `dispatch`이며 handler 메서드는 private로 시작해야 하며
  `_on`로 이름을 붙입니다.
- `onEvent`에서 `switch`로 이벤트를 라우팅합니다.
- handler 내부에서는 `AsyncValue.guard` 또는 명시적 `AsyncLoading`으로 상태를 갱신합니다.

```dart
// ✅ Allowed
ref.dispatch(authControllerProvider, const AuthSignInEvent());

// ❌ Forbidden (outside dispatch)
ref.read(authControllerProvider.notifier)._onSignIn(AuthSignInEvent());
state = state.copyWith(...);
```

#### 12. Events는 Sealed여야 함

```dart
sealed class AuthEvent {
  const AuthEvent();
}

final class AuthSignInEvent extends AuthEvent {
  const AuthSignInEvent();
}

final class AuthSignOutEvent extends AuthEvent {
  const AuthSignOutEvent();
}
```

#### 13. Event Observability (Logging)

- `dispatch`마다 이벤트명, timestamp, 변경 전/후 state를 로그로 남깁니다.
- 핵심 `EventLogger` provider 또는 app-level observer로 구현합니다.
- 환경 플래그로 로그 노출을 제어합니다.

```dart
void _log(AuthEvent event, AsyncValue<AuthState> before, AsyncValue<AuthState> after) =>
    ref.read(eventLoggerProvider).log(event: event, before: before, after: after);
```

---

## 네이밍 규칙

### 파일 네이밍 규칙

#### Domain Layer

```
{domain_name}.dart              Example: user.dart, kart_snapshot.dart
{feature}_repository.dart       Example: auth_repository.dart
{action}_use_case.dart          Example: login_use_case.dart
```

domain term이 모호할 때만 `_entity`를 사용합니다. 기계적 suffix보다 ubiquitous domain
name을 우선합니다.

#### Domain/Data 이름 Pairing

Domain model 이름이 기준 이름입니다. Data layer의 transfer/raw type은 domain 이름에
역할 suffix를 붙여 파생합니다.

```
Domain Model: KartSnapshot
DTO:          KartSnapshotDto
Domain File: kart_snapshot.dart
DTO File:    kart_snapshot_dto.dart

Domain Model: SourceIdentity
DTO:          SourceIdentityDto
Domain File: source_identity.dart
DTO File:    source_identity_dto.dart

Domain Model: KartEvent
Raw Row:      OperationRow
Domain File: kart_event.dart
Raw File:    operation_row.dart
```

역할별 suffix는 다음처럼 사용합니다.

- `Dto`: domain model과 매핑되는 serialized transfer shape.
- `Row`: domain mapping 전의 raw imported/tabular source record.
- `RequestDto` / `ResponseDto`: API boundary request/response payload.
- `Params`: use case input object.

추가 단어가 domain 의미를 더하지 않는 한 `KartSnapshotEntity`,
`KartSnapshotModel`, `KartSnapshotData` 같은 parallel name은 만들지 않습니다.

#### Data Layer

```
{domain_name}_dto.dart         Example: user_dto.dart, kart_snapshot_dto.dart
{action}_request_dto.dart      Example: login_request_dto.dart
{action}_response_dto.dart     Example: login_response_dto.dart
{feature}_repository_impl.dart Example: auth_repository_impl.dart
{feature}_{type}_data_source.dart Example: auth_remote_data_source.dart
```

#### Presentation Layer

```
{feature}_state.dart           Example: auth_state.dart
{feature}_event.dart           Example: auth_event.dart
{feature}_controller.dart      Example: auth_controller.dart
{feature}_providers.dart       Example: auth_providers.dart (optional)
{name}_page.dart              Example: login_page.dart
{descriptive}_widget.dart     Example: password_input_field.dart
```

### 클래스 네이밍 규칙

#### Domain Layer

```dart
{DomainName}                   Example: User, KartSnapshot, Todo
{Feature}Repository            Example: AuthRepository
{Action}UseCase               Example: LoginUseCase, GetTodosUseCase
{Action}Params                Example: LoginParams, CreateTodoParams
```

#### Data Layer

```dart
{Name}Dto                     Example: UserDto, TodoDto
{Action}RequestDto            Example: LoginRequestDto
{Action}ResponseDto           Example: LoginResponseDto
{Feature}RepositoryImpl       Example: AuthRepositoryImpl
{Feature}{Type}DataSource     Example: AuthRemoteDataSource
{Feature}{Type}DataSourceImpl Example: AuthRemoteDataSourceImpl
```

#### Presentation Layer

```dart
{Feature}State                Example: AuthState, TodoState
{Feature}Controller           Example: AuthController, TodoController
{Feature}{Action}Event        Example: AuthSignInEvent, TodoCreateEvent
{Name}Page                    Example: LoginPage, TodoListPage
{Descriptive}Widget           Example: PasswordInputField, TodoListItem
```

### Event & Handler 네이밍 규칙

- Events는 `sealed`이며 `Event`로 끝나야 합니다.
- `{Feature}{Action}Event` 사용 (AuthSignInEvent, AuthSignOutEvent, TodoCreateEvent).
- `Feature`는 `lib/src/features/<feature>/`의 최상위 폴더를 뜻합니다.
- snake_case feature folder (예: `pit_wall`)도 클래스명은 UpperCamelCase로 작성합니다
  (PitWallLoadEvent).
- `Requested`, `Started` 같은 요청형 접미사는 도메인상 필요하지 않으면 사용하지 않습니다.
- Handler 메서드는 private이며 `_on`으로 시작해야 합니다.
- `handle` / `_handle` 접두어는 사용하지 않습니다.

```dart
// ✅ CORRECT
Future<void> _onSignIn(AuthSignInEvent event) async { }

// ❌ WRONG
Future<void> handleLogin(...) async { }
```

### Provider 네이밍 규칙

```dart
// Provider naming pattern: {feature}{Type}Provider

// Data Source providers
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) => ...);

final todoLocalDataSourceProvider = Provider<TodoLocalDataSource>((ref) => ...);

// Repository providers
final authRepositoryProvider = Provider<AuthRepository>((ref) => ...);

final todoRepositoryProvider = Provider<TodoRepository>((ref) => ...);

// Use Case providers
final loginUseCaseProvider = Provider<LoginUseCase>((ref) => ...);

final getTodosUseCaseProvider = Provider<GetTodosUseCase>((ref) => ...);

// Controller providers
final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

// Family controller providers
final cartControllerProvider = AsyncNotifierProvider.family<CartController, CartState, CartId>(CartController.new);
```

### 메서드 네이밍 규칙

#### AsyncNotifier의 Event Controllers

```dart
// Route events in onEvent
Future<void> onEvent(AuthEvent event) => switch (event) {
      AuthSignInEvent e => _onSignIn(e),
      AuthSignOutEvent e => _onSignOut(e),
    };

// Handler methods: _on{Action} (private)
Future<void> _onSignIn(AuthSignInEvent event) async { }
Future<void> _onCreateTodo(TodoCreateEvent event) async { }

// Other private controller methods
Future<void> _onTokenRefreshed() async { }
Future<void> _onDataSynced() async { }
```

#### UseCase Methods

```dart
// Always use 'call' method
class LoginUseCase implements UseCase<User, LoginParams> {
  @override
  Future<Result<User>> call(LoginParams params) async { }
}
```

#### Helper Methods (Private)

```dart
// Action-oriented names
List<Todo> _filterCompletedTodos(List<Todo> todos) { }
bool _isEmailValid(String email) { }
String _formatDate(DateTime date) { }

// NOT generic names
void _process() { }        // ❌ Too generic
void _handle() { }         // ❌ Unclear
void _doSomething() { }    // ❌ Meaningless
```

### Freezed Union Variant 네이밍

#### State Variants

```dart
@freezed
abstract class AuthState with _$AuthState {
  // Initial state
  const factory AuthState.initial() = AuthInitial;

  // Success states (past participle or descriptive)
  const factory AuthState.authenticated({
    required User user,
  }) = AuthAuthenticated;

  const factory AuthState.unauthenticated() = AuthUnauthenticated;
}

@freezed
abstract class TodoState with _$TodoState {
  const factory TodoState.initial() = TodoInitial;

  const factory TodoState.loaded({
    required List<Todo> todos,
  }) = TodoLoaded;

  const factory TodoState.empty() = TodoEmpty;
}
```

### 변수 네이밍 Best Practices

```dart
// ✅ CORRECT: Descriptive and specific
final authenticatedUser = result.user;
final completedTodoList = todos.where((t) => t.isCompleted).toList();
final emailValidationErrorMessage = validator.validate(email);
final isUserAuthenticated = authState is AuthAuthenticated;

// ❌ WRONG: Generic or abbreviated
final user = result.user;              // Which user? Current? New?
final list = todos.where(...);         // What list?
final msg = validator.validate(email); // Abbreviation
final isAuth = authState is AuthAuthenticated; // Unclear
```

---

## Dispatch Helper (Recommended)

`lib/src/core/arch/event_controller.dart`에 정의된 shared helper를 사용하세요.

```dart
extension RefEventDispatcherX on Ref {
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, E, S>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) => read(provider.notifier).dispatch(event);
}

extension WidgetRefEventDispatcherX on WidgetRef {
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, E, S>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) => read(provider.notifier).dispatch(event);
}
```

## Build & Test (Short)

- `flutter pub get`
- `dart run build_runner build --delete-conflicting-outputs`
- `flutter test`
