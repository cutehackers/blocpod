# Coding Conventions

**Project Baseline:** 2026-06-01

This document defines mechanical coding conventions only. Architecture decisions such as layer boundaries, controller inheritance, provider lifecycle, event dispatch, state lifecycle, and `Result<T>` handling live in `docs/ARCHITECTURE.md`.

## Naming Patterns

**Files:**

- Use `snake_case.dart` for Dart files.
- Use domain language for domain model files, such as `kart_snapshot.dart` or `source_identity.dart`.
- Derive data file names from the domain name when the type maps directly to a domain model: `KartSnapshot` → `kart_snapshot.dart`, `KartSnapshotDto` → `kart_snapshot_dto.dart`.
- Add suffixes only when they clarify ownership or role: `_dto.dart`, `_row.dart`, `_request_dto.dart`, `_response_dto.dart`, `_repository.dart`, `_repository_impl.dart`, `_use_case.dart`, `_controller.dart`, `_event.dart`, `_state.dart`.
- Generated files end with `.freezed.dart` or `.g.dart`; do not edit them directly.
- Test files end with `_test.dart`.

**Functions and Methods:**

- Use `camelCase`.
- Use `call(params)` on use case classes.
- Prefix private methods and fields with `_`.
- Controller event handlers are private and start with `_on`.

**Variables:**

- Use `camelCase`.
- Prefer `final` for local variables.
- Use specific names that describe the value, not generic names like `data`, `item`, `list`, or `result` when a more precise term is available.

**Types:**

- Use `UpperCamelCase` for classes, enums, sealed classes, and typedefs.
- Repository implementations end with `Impl`.
- Events end with `Event`.
- DTOs that map directly to a domain model use `{DomainName}Dto`, such as `KartSnapshotDto`.
- Raw imported/tabular records use a source-shape name with `Row`, such as `OperationRow`.
- API boundary payloads use `RequestDto` / `ResponseDto`.
- Use `const` constructors where values are immutable.
- When using Freezed 3, declare models as `@freezed abstract class Name with _$Name`.

## Code Style

**Formatting:**

- Run `dart format --line-length 120`.
- Use 2-space indentation.
- Keep maximum line length at 120 characters.
- Use trailing commas for multi-line argument lists, collection literals, and constructors.

**Linting:**

- Run `flutter analyze`.
- The project uses `flutter_lints` from `analysis_options.yaml`.
- Use `dart fix --apply` only for auto-fixable issues that do not change architecture or behavior unexpectedly.

## Import Organization

Order imports in this sequence:

1. Dart SDK imports.
2. Package imports.
3. Relative imports.
4. Exports.

Use `package:pit_wall/...` for internal imports across feature/core boundaries:

```dart
import 'package:pit_wall/src/features/dashboard/domain/entities/kart_snapshot.dart';
```

Relative imports are allowed inside a tiny core micro-module when they keep embedded source snippets stable, such as `lib/src/core/arch/use_case.dart` importing `result.dart`.

## Error Handling

Do not define screen loading/error architecture here. Follow `docs/ARCHITECTURE.md` for `AsyncValue`, `Result<T>`, controller dispatch, and recoverable state error fields.

Mechanical conventions:

- Convert expected repository/use case failures into `Result.error`.
- Use `try-catch` at external boundaries, such as file IO, network, parsing, and platform APIs, to translate external exceptions into domain-level errors.
- Preserve stack traces when rethrowing or wrapping unexpected failures.
- Use typed exceptions for domain-significant failures.
- Avoid `UnimplementedError` in production code paths.

## Logging

- Use `debugPrint()` for development logging.
- Prefer controller event logs through `EventControllerNotifier.log`.
- Keep verbose or diagnostic logs behind an environment/debug flag.
- Do not log secrets, tokens, credentials, or full raw payloads that may contain private data.

## Comments

- Use Dart doc comments (`///`) for public APIs.
- Comment complex business rules, non-obvious invariants, and integration constraints.
- Avoid comments that merely restate the code.
- Keep TODOs close to the owning code and write them as `// TODO: description`.

## Function Design

- Keep functions focused on one responsibility.
- Keep use cases small, usually 3-20 lines.
- Keep controller handlers short enough to scan; extract private helpers when a handler mixes routing, validation, IO orchestration, and state mapping.
- Use named parameters with `required` when arguments are easy to confuse.
- Use positional parameters only for one or two obvious values.
- Return `Future<Result<T>>` for async use case and repository operations governed by the architecture.

## Module Design

- Avoid barrel files unless a feature has enough public exports to justify one.
- Do not create empty directories.
- Keep generated `part` directives next to the annotated source file.
- Keep provider declarations near the controller when they exist only to assemble controller dependencies.
- Move provider declarations to `{feature}_providers.dart` when they instantiate Data layer implementations or when the controller file becomes difficult to scan.
- Do not create `@riverpod` controller classes; controllers inherit `EventControllerNotifier`.

## Testing

- Name test files after the unit or behavior under test: `dashboard_controller_test.dart`, `jsonl_row_parser_test.dart`.
- Prefer behavior-focused test names.
- Add tests when changing architecture primitives, provider lifecycle, parser behavior, repository mapping, or user-visible controller behavior.
- For provider lifecycle changes, cover regular, `autoDispose`, `family`, and `autoDispose.family` variants when relevant.

---

*Convention baseline adapted for Pit Wall on 2026-06-01.*
