# Architecture

---

## Overview

This guide presents a Flutter Clean Architecture implementation using Riverpod's AsyncNotifier pattern with event-driven state management. It follows a feature-based folder structure with State-Domain-DTO data flow.

### Key Characteristics

- Strict dependency inversion: dependencies flow inward (presentation → domain ← data)
- Feature-based modular structure under `lib/src/features/<feature>/`
- Riverpod 3.x with explicit `Provider` / `AsyncNotifierProvider` declarations
- Freezed for immutable entities and state models (where it improves ergonomics)
- Use case pattern to encapsulate business logic
- Repository pattern to abstract data sources

### Core Principles

- **Separation of Concerns**: Each layer has a clear, distinct responsibility
- **Dependency Inversion**: Higher layers don't depend on lower layers
- **Testability**: Each layer can be tested independently
- **Scalability**: New features can be added with minimal impact on existing code
- **Event-Driven State**: Explicit, traceable state changes through events
- **Type Safety**: Dart sealed events + Riverpod; Freezed where it improves state/DTO ergonomics

---

## Architecture Layers

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

## Layer Responsibilities & Constraints

### Presentation

- Location: `lib/src/features/<feature>/presentation/`
- Controllers extend `EventControllerNotifier` and implement `onEvent` with a `switch`.
- Events are `sealed` and follow `{Feature}{Action}Event` naming.
- UI dispatches events via `RefEventDispatcherX` (`ref.dispatch(...)`).
- Core definitions live in `lib/src/core/arch/event_controller.dart`.
- State lives with the controller unless it exceeds 100 lines.
- Do not import Data layer types in Presentation.
  - Do not create nested `<feature>` folders under `presentation/`.

### Domain

- Location: `lib/src/features/<feature>/domain/`
- Domain models: immutable models (Freezed is allowed where it improves ergonomics).
- Repositories: interfaces only.
- Use Cases: one action per file, `call(params)` only.
- Do not import Presentation or Data.

### Data

- Location: `lib/src/features/<feature>/data/`
- Data Sources: remote/local interfaces + implementations.
- DTOs: conversion to/from domain models.
- Repository implementations: orchestrate data sources and map DTO ↔ domain model.
- Do not import Presentation.

### Cross-Cutting (Core)

- Location: `lib/src/core/`
- Shared utilities, base abstractions, and infrastructure that are reused across features.

---

## Core Architecture Source Contract

The architecture depends on three core files. When bootstrapping this project from this document, create these files first and keep their public API stable unless the architecture itself is being changed.

Create files in this order:

1. `lib/src/core/arch/result.dart`
2. `lib/src/core/arch/use_case.dart`
3. `lib/src/core/arch/event_controller.dart`

### `lib/src/core/arch/result.dart`

`Result<T>` is the shared domain/data boundary for operations that can succeed or fail. Use cases and repositories return this type instead of throwing for expected domain/data failures.

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

`UseCase<Output, Params>` is the domain orchestration interface. A use case accepts one params object and returns `Future<Result<Output>>`. Use `NoParams` for parameterless actions instead of `void`, `Null`, or an empty map.

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

`EventControllerNotifier<S, E>` is the presentation state boundary. UI code dispatches sealed events through `ref.dispatch(...)`; controllers route those events inside `onEvent`. The `log` hook is intentionally a no-op by default so features can opt into observability without changing the dispatch API.

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

- Do not duplicate these abstractions inside features.
- Domain use cases import `use_case.dart` and `result.dart`.
- Domain repositories return `Future<Result<T>>` for async operations.
- Presentation controllers import `event_controller.dart` and expose state through `AsyncNotifierProvider`.
- Widgets dispatch events through `ref.dispatch(provider, event)` instead of calling controller handlers directly.
- Controller providers may use regular, `autoDispose`, `family`, or `autoDispose.family` variants.
- Family arguments are passed through the controller constructor and read from controller fields.
- Do not generate controller classes with `@riverpod`; generated `_$Controller` inheritance conflicts with `EventControllerNotifier`.
- If a core API changes, update both `docs/ARCHITECTURE.md` and `docs/ARCHITECTURE-ko.md` in the same change.

---

## Folder Structure

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

The structure above reflects the rules below (no nested feature folders under `data/`, `domain/`, or `presentation/`).

### Key Structure Decisions

**Folders are minimal and specific:**

- `data/` - Data layer handling API calls, local storage, and data source management
- `domain/` - Business logic layer containing use cases and domain entities (framework-independent)
- `presentation/` - UI layer with pages, screens, and reusable widgets
- `data/models/` - DTOs only (create only if DTOs exist)
- `domain/entities/` - Domain models only (create only if domain models exist)
- `presentation/widgets/` - Reusable UI components only (create only if widgets exist)
- **No nested feature folders** inside `data/`, `domain/`, or `presentation/`.
- Only the allowed subfolders may exist (e.g., `data/models`, `domain/entities`, `presentation/widgets`).

### Code Organization (Feature-First Structure)

This section is the project source of truth for feature-first code organization.

- Follow feature-based folder structure: `lib/src/features/<feature>/{data,domain,presentation}/`
- No nested feature folders under `data/`, `domain/`, or `presentation/`
- Only allowed subfolders: `data/models/`, `domain/entities/`, `presentation/widgets/`
- Never create empty directories; only create folders when files will occupy them
- Maximum file length: 500 lines (split if exceeded; State exceeds 100 lines → separate file)
- File naming: `snake_case.dart`; class naming: `PascalCase`

⚠️ Rule: Never create empty directories. Only create folders when you have files to place in them.

**Files are organized by type within a feature:**

- Repository implementations: `{feature}_repository_impl.dart`
- Data Sources: `{feature}_{type}_data_source.dart`
- Use Cases: `{action}_use_case.dart`
- Pages: `{name}_page.dart` (inside `presentation/`)
- Controllers: `{feature}_controller.dart` (inside `presentation/`)
- Providers: keep pure controller providers near the controller. Move dependency providers that instantiate Data layer implementations to `lib/src/features/<feature>/{feature}_providers.dart`.

### Configuration and Constants

Avoid single, global constants files. Use one of these patterns instead:

- Feature-scoped config: `lib/src/features/<feature>/data/<feature>_config.dart`
- Core config for shared settings: `lib/src/core/config/app_config.dart`
- Environment values via `--dart-define` + a small `AppEnv` wrapper
- Remote config or backend-driven flags for runtime tuning

Each constant should live near the code it affects, with clear naming and ownership.

---

## Feature Scaffold Contract

Use this scaffold when creating a new feature. Keep the controller provider explicit and keep the controller inheritance fixed on `EventControllerNotifier`.

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

Use `family` when a controller instance is scoped by a stable argument such as an ID. Prefer `autoDispose.family` for detail screens, tabs, dialogs, and any controller whose state should disappear when the last listener is gone.

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

- Controller providers are explicit `AsyncNotifierProvider` declarations.
- Controller classes always extend `EventControllerNotifier<State, Event>`.
- Do not use `@riverpod class FeatureController extends _$FeatureController`; Dart single inheritance prevents that generated base from composing with `EventControllerNotifier`.
- Use plain `Provider<T>` for data source, repository, and use case dependencies unless a different Riverpod provider type is required by the value lifecycle.
- UI receives controller state with `ref.watch(featureControllerProvider)` and sends actions with `ref.dispatch(featureControllerProvider, event)`.

---

## Data Flow

### Complete Data Flow Diagram

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

### Event-Driven Flow with AsyncNotifier

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

- UI dispatches events through `RefEventDispatcherX` (`ref.dispatch(...)`).
- Controllers extend `EventControllerNotifier` and implement `onEvent` with a `switch` over sealed events.
- Event routing lives in `onEvent`; no handler registration or init hooks.
- Optional: override `log` to plug in event observability.
- Reference implementation: `lib/src/core/arch/event_controller.dart`.

### State, Domain Model, DTO Conversion Flow

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

## Key Rules

### Critical Architecture Rules

#### 1. Freezed Usage Rules

```dart
// Correct: Freezed 3 models are abstract classes.
@freezed
abstract class User with _$User {
  const factory User({...}) = _User;
}
```

Always generate the files required by the annotations you use:

- `user.freezed.dart`
- `user_dto.g.dart` when using `json_serializable`

Do not make a Freezed class non-abstract:

```dart
@freezed
class User with _$User { // Missing 'abstract'
```

#### 2. File and Class Naming Rules

Do not use generic file names:

```
- utils.dart
- helpers.dart
- common.dart
- base.dart
```

Use specific, declarative file names:

```
- email_validator.dart
- date_formatter.dart
- network_error_handler.dart
- auth_token_registry.dart
```

Forbidden ambiguity: avoid `utils.dart`, `helpers.dart`, `Util`, `Helper`, and `Manager`.

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

#### 3. Meaningful Naming Rules

**Variables and parameters should be:**

- **Specific**: Describe exactly what they contain
- **Predictable**: Follow consistent patterns
- **Explicit**: No abbreviations unless universally known

```dart
// ✅ CORRECT: Meaningful variable names
final authenticatedUser = await _loginUseCase(...);
final activeTodoList = todos.where((t) => !t.isCompleted).toList();
final emailValidationError = _validateEmail(email);

// ❌ WRONG: Unclear variable names
final data = await _loginUseCase(...);     // What data?
final list = todos.where(...);             // What list?
final err = _validateEmail(email);         // Abbreviation

// ✅ CORRECT: Descriptive event field names
// todoTitle, todoDescription

// ❌ WRONG: Generic event field names
// title, desc
```

#### 4. State Management with AsyncValue

```dart
state = const AsyncLoading();
state = await AsyncValue.guard(() async => /* use case */);
```

Do not add loading variants or `isLoading` fields to State; AsyncValue already covers loading. State may still contain recoverable, domain-facing error fields such as `errorMessage` or `importIssues` when the screen can continue rendering.

#### 5. State File Placement Rule

- If the State model is **under 100 lines**, keep it in the same file as its Controller.
- If the State model is **100 lines or more**, move it to its own file in the same folder.

#### 6. Layer Dependency Rules

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

#### 7. DTO to Domain Model Conversion Rules

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

#### 8. Provider Organization Rules

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

Do not generate controller classes with `@riverpod`; generated controller inheritance conflicts with `EventControllerNotifier`.

Provider declarations that instantiate data sources or repository implementations must not live under `presentation/`; place that composition in `lib/src/features/<feature>/{feature}_providers.dart` so Presentation imports no Data layer types.

#### 9. Error Handling Rules

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

#### 10. Use Case Parameter Rules

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

#### 11. Dispatch-Only State Changes

- UI must call controller `dispatch` only (via `RefEventDispatcherX`).
- Forbidden: calling controller methods directly or mutating state outside `dispatch`.
- Controller public API = `dispatch`; handler methods are private and start with `_on`.
- Route events in `onEvent` using a `switch` over sealed events.
- Inside handlers, update state via `AsyncValue.guard` or explicit `AsyncLoading`.

```dart
// ✅ Allowed
ref.dispatch(authControllerProvider, const AuthSignInEvent());

// ❌ Forbidden (outside dispatch)
ref.read(authControllerProvider.notifier)._onSignIn(AuthSignInEvent());
state = state.copyWith(...);
```

#### 12. Events Must Be Sealed

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

- Log every `dispatch` with event name, timestamp, and state before/after.
- Implement via a core `EventLogger` provider or app-level observer.
- Keep logs behind environment flags.

```dart
void _log(AuthEvent event, AsyncValue<AuthState> before, AsyncValue<AuthState> after) =>
    ref.read(eventLoggerProvider).log(event: event, before: before, after: after);
```

---

## Naming Conventions

### File Naming Rules

#### Domain Layer

```
{domain_name}.dart              Example: user.dart, kart_snapshot.dart
{feature}_repository.dart       Example: auth_repository.dart
{action}_use_case.dart          Example: login_use_case.dart
```

Use `_entity` only when the domain term would otherwise be ambiguous. Prefer the ubiquitous domain name over a mechanical suffix.

#### Domain/Data Name Pairing

Domain model names are the source name. Data-layer transfer/raw types derive from the domain name by adding a role suffix.

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

Use these suffixes by role:

- `Dto`: serialized transfer shape that maps to/from a domain model.
- `Row`: raw imported or tabular source record before domain mapping.
- `RequestDto` / `ResponseDto`: API boundary request/response payloads.
- `Params`: use case input object.

Do not create parallel names such as `KartSnapshotEntity`, `KartSnapshotModel`, or `KartSnapshotData` unless the extra word adds domain meaning.

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

### Class Naming Rules

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

### Event & Handler Naming Rules

- Events are `sealed` and end with `Event`.
- Use `{Feature}{Action}Event` (AuthSignInEvent, AuthSignOutEvent, TodoCreateEvent).
- `Feature` refers to the top-level folder under `lib/src/features/<feature>/`.
- For snake_case feature folders (e.g., `pit_wall`), use UpperCamelCase in class names (PitWallLoadEvent).
- Avoid request-style suffixes like `Requested`/`Started` unless the domain requires it.
- Handler methods are private and must start with `_on`.
- Do not use `handle` / `_handle` prefixes.

```dart
// ✅ CORRECT
Future<void> _onSignIn(AuthSignInEvent event) async { }

// ❌ WRONG
Future<void> handleLogin(...) async { }
```

### Provider Naming Rules

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

### Method Naming Rules

#### Event Controllers in AsyncNotifier

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

### Freezed Union Variant Naming

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

### Variable Naming Best Practices

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

Use the shared helper defined in `lib/src/core/arch/event_controller.dart`:

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
