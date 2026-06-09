# Publishing Blocpod Packages

This workspace publishes three public packages:

- `blocpod_arch`
- `blocpod_logger`
- `blocpod_arch_logger`

The root `blocpod_workspace` package remains unpublished.

## Confirmed First-Publish Decisions

- License: BSD 3-Clause.
- Repository URL: `https://github.com/cutehackers/blocpod`.
- First public version: `0.1.0`.
- First publish account: individual Google account, with optional verified-publisher transfer later.

The same `LICENSE` file is included in:

- `packages/arch/LICENSE`
- `packages/logger/LICENSE`
- `packages/arch_logger/LICENSE`

## Preflight

```sh
curl -i https://pub.dev/api/packages/blocpod_arch
curl -i https://pub.dev/api/packages/blocpod_logger
curl -i https://pub.dev/api/packages/blocpod_arch_logger

flutter pub get
dart pub workspace list
flutter analyze
dart format --set-exit-if-changed --line-length 120 .

(cd packages/arch && flutter test)
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
```

## Dry Run

```sh
dart pub -C packages/arch publish --dry-run
dart pub -C packages/logger publish --dry-run
dart pub -C packages/arch_logger publish --dry-run
```

Inspect every file listed by each dry run before publishing.

## Publish Order

Publish the independent packages first:

```sh
dart pub -C packages/arch publish
dart pub -C packages/logger publish
```

Then publish the bridge package:

```sh
dart pub -C packages/arch_logger publish
```

`blocpod_arch_logger` depends on hosted `blocpod_arch` and `blocpod_logger` constraints. Inside this workspace, pub resolves those names to local workspace packages when their versions match the constraints; outside this workspace, consumers receive the hosted pub.dev packages.
