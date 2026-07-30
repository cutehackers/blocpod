# blocpod: `AsyncNotifier` 초기 상태 확립 로깅

**대상 저장소:** https://github.com/cutehackers/blocpod (`blocpod_arch`, 릴리스 대상 `0.2.0`)
**요청 출처:** 9.81 Park 3.0 (`sgp-981-app`) — 세션 상태 추적
**날짜:** 2026-07-30

---

## Problem Statement

`EventControllerNotifier`는 컨트롤러 상태 변화를 `EventLogRecord`로 기록한다. 그런데
**`build()`가 만드는 초기 상태는 어떤 레코드에도 남지 않는다.** `stateLabel`/
`stateMetadata` 훅을 구현한 컨트롤러조차 초기 상태에 대해서는 그 훅이 호출되지 않는다.

### 재현

`AsyncNotifier.build()`에서 영속 세션을 복원하고 `stateLabel`/`stateMetadata`를
오버라이드한 컨트롤러의 콜드 스타트 로그 전체:

```
│ [info] | SessionController controller.created | phase=controller.created,
│         traceId=…, spanId=…, controllerName=SessionController
```

이 한 줄이 끝이다. 복원된 세션이 인증 상태인지 미인증인지 로그에 없다. 반면 같은
컨트롤러에 이벤트를 dispatch하면 정상적으로 남는다:

```
│ SessionController.SessionEstablishedEvent | isAuthenticated=true, isGuest=false
```

즉 훅 구현은 올바르고, 초기화 경로만 비어 있다.

### 원인

두 사실이 겹친다.

1. **`controllerCreated`가 `build()` 이전에 발화한다.** `event_controller.dart:22-26`:

   ```dart
   void Function(void Function())? runBuild() {
     _logControllerCreatedOnce();     // ← build 이전
     _registerControllerDisposedOnce();
     return super.runBuild();          // ← 여기서 build 실행
   }
   ```

   따라서 `controllerMetadata()`도 build 결과를 볼 수 없다. `controllerCreated`
   레코드는 `nextStateLabel`/`stateMetadata`를 채우지 않는다(`event_controller.dart:138-146`).

2. **build 완료를 표현하는 phase가 없다.** `EventLogPhase`의 여섯 값은 컨트롤러
   생성/폐기 아니면 dispatch 생명주기다. 초기 상태 확립에 해당하는 값이 없다.

`transition`으로 대체할 수도 없다. `_logTransitionSafely`는 `dispatchContext`를
요구하고(`event_controller.dart:187-190`), 그 값은 dispatch에서만 나온다.

### 우회가 불가능한 이유

소비자 측에서 메울 수 없다는 점이 이 문제를 업스트림 사안으로 만든다.

- **`build()` 안에서 `dispatch()` 호출 → 데드락.** `dispatch`의 첫 문장이
  `await future`(`event_controller.dart:52`)로 자기 build 완료를 기다린다.
- **`controllerMetadata()` 오버라이드 → 타이밍 불가.** 위 1번 순서 때문에 build
  이전에 평가된다.
- **`build()`에서 `eventLoggerProvider` 직접 기록 → 가능하지만 부적절.** 컨트롤러마다
  같은 코드를 복제해야 하고, 마땅한 `phase` 값이 없어 의미를 왜곡한다.

### 영향 범위

이 워크스페이스의 `EventControllerNotifier` 6개 중 4개가 `async build()`로 의미 있는
초기 상태를 만든다. `build()`에서 저장소·네트워크·캐시를 읽는 컨트롤러는 모두 같은
구멍을 갖는다 — 특정 컨트롤러의 문제가 아니라 계약의 공백이다.

관측 손실이 가장 큰 곳은 인증이다. "이미 로그인된 상태로 부팅해 바로 진입했다"가
로그에 남지 않으면, 세션 복원 실패와 세션 부재를 로그만으로 구분할 수 없다.

---

## Goal

`build()`가 확립한 초기 상태를 기존 `stateLabel`/`stateMetadata` 훅을 통해 기록한다.
**소비자 코드 변경 없이** — 이미 훅을 구현한 컨트롤러는 재컴파일만으로 초기 상태
로그를 얻는다.

Non-goal: dispatch 밖 `state =` 직접 대입 기록(원인 이벤트가 없어 의도적으로 제외된
설계다), 기존 phase의 의미 변경, `EventLogRecord` 필드 추가.

---

## 해결 방향

### 1. `EventLogPhase`에 `initialStateEstablished` 추가

```dart
enum EventLogPhase {
  controllerCreated,
  initialStateEstablished,   // 신규
  eventStarted,
  transition,
  eventCompleted,
  eventFailed,
  controllerDisposed,
}
```

`controllerCreated` 바로 뒤에 둔다 — 열거형 순서가 실제 생명주기 순서와 일치한다.

`AsyncNotifier`의 생명주기는 원래 두 단계(생성 → 초기 상태 확립)인데 로깅 계약이 한
단계만 표현하고 있었다. 빠진 단계를 채우는 것이지 새 개념을 도입하는 것이 아니다.

### 2. `runBuild()`의 완료 콜백에서 발화

해결 시점의 workspace resolution은 Riverpod/flutter_riverpod `3.4.2`를 선택한다. Riverpod의
`runBuild()`는 `WhenComplete`(`void Function(void Function())?`)를 반환하고,
이것이 build 완료 훅이다. Riverpod 문서(`notifier_provider.dart:35-49`)가 build 전후
로직에 `runBuild()` 오버라이드와 `listenSelf`를 권장하며 "It is safe to use ref here"를
명시한다.

```dart
@mustCallSuper
@override
void Function(void Function())? runBuild() {
  _logControllerCreatedOnce();
  _registerControllerDisposedOnce();
  final whenComplete = super.runBuild();
  return whenComplete == null
      ? null
      : (onComplete) {
          whenComplete(() {
            _logInitialStateEstablishedOnce();
            onComplete();
          });
        };
}
```

반환된 콜백을 직접 등록하는 대신 합성한다. 이로써 build가 끝난 뒤 초기 상태를 먼저 한 번만
기록하고 Riverpod이 원래 전달한 완료 콜백을 보존해 호출한다. `_didLogControllerCreated`와
같은 플래그 방식으로 재빌드 시 중복을 막는다.

레코드는 **이미 존재하는 필드만** 채운다 — 새 필드가 필요 없다:

| 필드 | 값 |
|---|---|
| `phase` | `EventLogPhase.initialStateEstablished` |
| `nextStateKind` | `asyncValueKindOf(state)` |
| `nextStateLabel` | `_safeStateLabel(state)` |
| `stateMetadata` | `_safeStateMetadata(previous: state, next: state)` |
| `metadata` | `_safeControllerMetadata()` |
| `previousStateKind` / `previousStateLabel` | `null` — 이전 상태가 존재하지 않는다 |
| `hasChanged` | `null` — 전이가 아니다 |
| `eventName` | `null` — 원인 이벤트가 없다 |

`previousStateLabel`을 비우는 것이 이 phase의 정의다. 초기화는 변이가 아니므로 "이전"이
없고, 빈칸을 남기는 대신 phase 자체가 그 사실을 말한다.

### 3. 실패 경로

`build()`가 던지면 상태는 `AsyncError`다. 그때도 레코드를 남긴다 — `nextStateKind:
error`, `error`/`stackTrace` 채움. 세션 복원 실패와 세션 부재를 구분하려는 원래 목적이
바로 이 경로에 달려 있다.

`_writeRecordSafely`를 그대로 쓰므로 로깅 자체가 던져도 컨트롤러를 깨지 않는다.

### 4. `stateMetadata` 훅 시그니처

현재 `stateMetadata({required previous, required next})`는 두 인자를 요구한다. 초기화에는
`previous`가 없다. 두 선택:

- **(a) `previous`에 `next`와 같은 값을 넘긴다.** 시그니처 변경 없음, 하위 호환.
  구현자가 `previous`를 비교에 쓰면 "변화 없음"으로 읽힌다 — 초기화에서는 사실이다.
- **(b) `previous`를 nullable로 완화.** 더 정직하지만 breaking change다.

**(a) 추천.** `0.1.x`에서 breaking change를 만들 이유가 없고, 대부분의 구현은
`next`만 읽는다(이 워크스페이스의 두 구현 모두 그렇다).

---

## 하위 호환

- 기존 phase의 발화 시점·필드 의미 변경 없음
- `EventLogRecord` 필드 추가·삭제 없음
- 훅 시그니처 변경 없음
- `EventLogPhase`에 값이 추가되므로, phase를 **exhaustive switch**로 다루는 소비자는
  컴파일 에러가 난다. `blocpod_arch_logger`의 포매터가 해당하므로 같은 릴리스에서
  함께 갱신해야 한다. 이것이 유일한 breaking 지점이며 minor 범프가 적절하다.

---

## 검증

blocpod 측:

1. `async build()`가 데이터를 반환하면 `initialStateEstablished` 레코드 1건, `nextStateLabel`이
   훅 반환값과 일치
2. `build()`가 던지면 `nextStateKind: error` + `error` 채움
3. 훅 미구현 컨트롤러는 `nextStateLabel: null` — 레코드는 여전히 남는다
4. 재빌드(의존성 무효화) 시 중복 기록 없음
5. `sync build()`에서도 동작
6. 기존 dispatch 경로 레코드가 변하지 않음(회귀)

소비자 측(이 워크스페이스, 릴리스 후):

7. `SessionController` 콜드 스타트 로그에 `isAuthenticated`/`isGuest`가 나타남 —
   `session_controller.dart`의 기존 훅만으로, 코드 변경 없이

---

## Open Decisions

| 질문 | 선택지 | 추천 |
|---|---|---|
| `stateMetadata`의 `previous` 처리 | (a) `next`와 동일값 (b) nullable로 완화 | (a) — 하위 호환 유지, 실사용 대부분이 `next`만 읽는다 |
| `initialStateEstablished`를 `controllerCreated`와 병합 | (a) 별도 phase (b) `controllerCreated`를 build 후로 이동 | (a) — (b)는 build가 던질 때 레코드가 사라지고 기존 로그 독자에게 침묵의 회귀다 |
| 이 워크스페이스의 임시 우회 | (a) 업스트림만 기다린다 (b) `build()` 직접 기록 후 릴리스 시 삭제 | 릴리스 리드타임에 따라 판단 — 즉시 필요하면 (b), `ponytail:` 주석으로 삭제 예정 표기 |
