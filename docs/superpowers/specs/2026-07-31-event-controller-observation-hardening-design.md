# Blocpod EventController 관측 경계 강화 설계

**대상 저장소:** `blocpod`의 `blocpod_arch`, `blocpod_arch_logger`
**날짜:** 2026-07-31
**상태:** 승인됨

---

## Problem Statement

`EventControllerNotifier`는 Dart `Zone`에 저장된 `EventDispatchContext`를 이용해
상태 변경을 이벤트에 귀속하고, 동기 `EventLogger` seam으로
`EventLogRecord`를 전달한다. 정상적인 awaited nested dispatch에서는 같은 trace와
부모/자식 span 관계가 유지되지만, 현재 경계에는 다음 네 문제가 있다.

1. `EventDispatchContext`에 controller 소유권과 종료 상태가 없다. 다른 controller의
   직접 상태 변경이나 dispatch 종료 후 실행되는 detached 작업이 이전 이벤트의
   transition으로 잘못 기록될 수 있다.
2. 동시 dispatch 완료 시 공유 controller 상태를 다시 읽는다. 완료 레코드가 다른
   이벤트가 쓴 상태를 자기 결과로 보고할 수 있다.
3. `EventLogger.log`를 상태 setter와 dispatch 처리 중 직접 호출한다. 동기 logger가
   상태 변경이나 dispatch를 재진입시키면 중첩 logger 호출과 잘못된 trace 상속이
   발생할 수 있다.
4. `startedAt`이 dispatch 시작 시각과 record 발생 시각을 동시에 표현하고, formatter는
   이를 sink timestamp로 사용한다. 완료 레코드의 timestamp가 실제 완료 시각보다
   앞서고, 동시 이벤트의 안정적인 발생 순서를 복원할 수 없다.

## Goals

- 기존 `dispatch(event)`, `onEvent(event)`, `state = next` 사용법을 유지한다.
- awaited nested dispatch의 trace/child-span 관계를 유지한다.
- 동시 dispatch를 계속 허용하면서 transition과 완료 결과를 이벤트별로 분리한다.
- cross-controller 및 종료된 dispatch context의 잘못된 상태 귀속을 차단한다.
- logger 호출을 비재진입 FIFO 경계로 만들고 logger 실패를 애플리케이션 흐름에서
  격리한다.
- span 시작 시각, record 발생 시각, 발생 순서, 소요 시간을 서로 다른 개념으로
  정의한다.
- 기존 `EventLogRecord` 직접 생성자와 `EventLogger` 구현의 소스 호환성을 유지한다.

## Non-goals

- dispatch를 controller별로 직렬화하지 않는다.
- Dart isolate 사이의 전역 순서를 제공하지 않는다.
- logger 전송을 비동기 또는 durable queue로 바꾸지 않는다.
- dispatch 밖의 일반적인 `state = next`를 새 이벤트로 기록하지 않는다.
- 모든 fire-and-forget Future를 자동 판별하지 않는다. Dart Zone은 Future가 나중에
  await될지 여부를 표현하지 않는다.
- 공개 `EventDispatchScope` 또는 token 기반 state API를 이번 변경에 추가하지 않는다.

---

## 설계 결정

### 1. 공개 사용법은 유지한다

다음 두 behavioral interface는 변경하지 않는다.

```dart
abstract class EventController<E> {
  Future<void> dispatch(E event);
}

abstract interface class EventLogger {
  void log(EventLogRecord record);
}
```

`EventControllerNotifier` 하위 클래스는 계속 `onEvent`를 구현하고 `state` setter를
사용한다. concurrency option, dispatch token, callback을 공개 API에 추가하지 않는다.

### 2. Zone은 전파 수단이고 소유권 증명이 아니다

각 `EventControllerNotifier` 인스턴스는 외부에 노출되지 않는 identity token을 가진다.

```dart
final Object _dispatchOwner = Object();
```

`EventDispatchContext`에는 다음 정보와 동작을 추가한다.

```dart
final Object owner;
final EventDispatchContext? parent;
bool get isActive;

bool owns(Object candidate);
void close();

static EventDispatchContext? currentFor(Object owner);
static bool get hasAmbientContext;
static TraceContext? get parentTraceContext;
static R runWithoutContext<R>(R Function() body);
```

불변 조건:

- 소유권 비교는 이름이나 runtime type이 아니라 `identical` identity 비교를 사용한다.
- `currentFor(owner)`는 context가 active이고 owner가 일치할 때만 context를 반환한다.
- `hasAmbientContext`는 Zone에 active 또는 closed dispatch context가 원래 존재하는지
  나타낸다. stale dispatch Zone과 명시적 `TraceContext.run`만 사용한 Zone을 구분하기
  위한 값이다.
- `close()`는 idempotent하다.
- 닫힌 context를 상속한 Zone에서는 `current`와 `currentFor`가 모두 `null`로 취급된다.
- `runWithoutContext`는 dispatch context와 trace context를 모두 명시적으로 가린다.
- `transitionIndex`는 context별로 1부터 증가한다.

state setter는 `EventDispatchContext.current`가 아니라
`EventDispatchContext.currentFor(_dispatchOwner)`를 사용한다. context가 없거나 소유권이
다르면 상태 변경 자체는 기존처럼 수행하되 transition으로 기록하지 않는다.

이 규칙은 다음을 자동으로 차단한다.

- controller A의 이벤트 Zone에서 controller B의 state를 직접 변경하는 경우
- dispatch가 끝난 뒤 해당 Zone을 상속한 detached callback이 state를 변경하는 경우
- logger callback에서 시작한 작업이 관찰 중인 이벤트의 context를 상속하는 경우

새 dispatch의 parent trace는 다음 규칙으로 선택한다.

```dart
final parentTrace = EventDispatchContext.parentTraceContext;
```

- active dispatch context가 있으면 해당 span의 child를 만든다.
- dispatch context가 전혀 없는 Zone에서는 기존처럼 명시적 `TraceContext.current`를
  존중한다.
- closed dispatch context가 남은 stale Zone에서 현재 trace가 그 context의 trace와
  동일하면 상속된 trace를 버리고 root span을 만든다.
- stale Zone 안에서 `TraceContext.run`으로 다른 trace를 명시적으로 설치했다면 해당
  trace를 존중해 child span을 만든다.

따라서 detached callback이 종료된 dispatch의 `TraceContext`만 상속하고 있더라도 새
dispatch가 완료된 span의 child로 잘못 연결되지 않는다.

### 3. 이벤트별 상태 observation ledger를 둔다

각 notifier는 활성 context를 key로 하는 내부 observation map을 가진다.

```dart
final Map<EventDispatchContext, _DispatchObservation<S>> _observations =
    Map.identity();
```

개념적인 observation 값은 다음과 같다.

```dart
final class _DispatchObservation<S> {
  _DispatchObservation(this.stateAtStart);

  final AsyncValue<S> stateAtStart;
  AsyncValue<S>? latestOwnedState;
  int transitionCount = 0;

  AsyncValue<S> get outcome => latestOwnedState ?? stateAtStart;
}
```

dispatch 시작 시 시작 상태를 보관하고, 해당 context가 소유한 state assignment가
성공할 때마다 `latestOwnedState`를 갱신한다. terminal record는 공유 `state`를 다시
읽지 않고 다음 의미를 사용한다.

| 필드 | 의미 |
|---|---|
| `previousState*` | dispatch admission 시점의 `stateAtStart` |
| `nextState*` | 해당 dispatch가 소유한 마지막 상태, 없으면 시작 상태 |
| `hasChanged` | 위 두 `AsyncValue`의 identity 비교 |

같은 controller의 awaited nested dispatch가 끝나면 child outcome을 아직 active인
same-owner parent observation에 합친다. 따라서 parent가 child 뒤에 직접 상태를 쓰면
그 상태가 최종 outcome이고, parent가 직접 쓰지 않으면 child outcome이 parent의
causal subtree outcome이 된다.

동시 sibling dispatch는 서로의 observation에 합쳐지지 않는다. fire-and-forget child가
parent 종료 후 끝나면 parent가 이미 닫혔으므로 합쳐지지 않는다. parent가 종료되기 전에
끝나는 unawaited child와 awaited child는 Zone만으로 구분할 수 없으므로 둘 다 causal
child로 취급한다. 이 제한은 API 문서에 명시한다.

### 4. transition은 성공한 state assignment를 기록한다

기존 구현은 logger를 호출한 후 `super.state = next`를 수행한다. 이를 다음 순서로
변경한다.

1. 현재 state를 안전하게 읽는다.
2. write ordinal, transition index, transition occurrence를 예약한다.
3. `super.state = next`로 상태 변경을 완료한다.
4. active owned observation을 예약한 write ordinal로 갱신한다.
5. 예약한 transition을 logger emission queue에 publish한다.

`super.state`가 실패하면 transition은 기록하지 않고 원래 오류를 그대로 전파한다.
이 경우 transition occurrence와 최신 transition-index 예약을 취소한다. 예약을 상태
커밋보다 먼저 수행하므로 Riverpod listener가 setter 안에서 같은 notifier를 동기적으로
다시 변경해도 바깥 write가 먼저, 재진입 write가 나중 순서로 기록된다.
logger는 반쯤 반영된 상태를 관찰할 수 없다.

state summary hook과 metadata hook 실패는 기존처럼 안전한 fallback을 사용한다.

### 5. EventLogRecord의 시간과 순서를 분리한다

`EventLogRecord`에 다음 optional constructor parameter와 field를 추가한다.

```dart
EventLogRecord({
  // 기존 인자
  required DateTime startedAt,
  DateTime? occurredAt,
  int? recordSequence,
});

final DateTime startedAt;
final DateTime occurredAt;
final int? recordSequence;
```

constructor는 다음 호환 규칙을 사용한다.

```dart
occurredAt = occurredAt ?? startedAt;
```

의미:

- `startedAt`: controller lifecycle occurrence 또는 dispatch span이 시작된 UTC 시각
- `occurredAt`: 이 record의 phase가 실제로 발생한 UTC 시각
- `recordSequence`: Blocpod이 생성한 record의 Dart isolate 내 1-based 발생 순서
- `transitionIndex`: 기존과 동일한 dispatch-local transition 순서
- `duration`: dispatch 시작부터 terminal phase까지의 monotonic elapsed time

Blocpod 내부에서 생성한 모든 record에는 `occurredAt`과 `recordSequence`가 들어간다.
직접 생성한 호환 record는 `recordSequence == null`일 수 있다.

하나의 dispatch에서 모든 record의 `startedAt`은 동일하다. phase별 `occurredAt`은
다음 시점에 잡는다.

| Phase | `occurredAt` |
|---|---|
| lifecycle phases | lifecycle 사실을 관찰한 시점 |
| `eventStarted` | handler 진입 직전 |
| `transition` | state assignment 성공 직후 |
| `eventCompleted` / `eventFailed` | handler settle 및 context close 직후 |

소요 시간은 system clock 차이가 아니라 dispatch마다 생성한 `Stopwatch.elapsed`를
사용한다. 시스템 시각 보정으로 음수 duration이 생기지 않는다.

### 6. isolate 단위 observation emitter를 둔다

`blocpod_arch` 내부에 isolate 단위 sequence allocator와 FIFO emission gate를 둔다.
새 공개 port나 provider override는 만들지 않는다.

개념적 동작:

```dart
void emit(EventLogger? logger, EventLogRecord record) {
  if (logger == null) return;

  _pending.addLast((logger, record));
  if (_isDraining) return;

  _isDraining = true;
  try {
    while (_pending.isNotEmpty) {
      final (target, next) = _pending.removeFirst();
      EventDispatchContext.runWithoutContext(() {
        try {
          target.log(next);
        } catch (_) {
          // Logger failures never affect application flow.
        }
      });
    }
  } finally {
    _isDraining = false;
  }
}
```

불변 조건:

- sequence는 record occurrence를 만들 때 할당한다.
- queue는 sequence 발생 순서대로 FIFO 전달한다.
- logger callback은 같은 isolate에서 재귀적으로 중첩되지 않는다.
- callback 중 발생한 record는 현재 callback이 반환된 뒤 전달된다.
- 각 logger 오류는 해당 invocation에만 영향을 주고 이후 queue drain은 계속된다.
- logger callback에서는 ambient dispatch/trace context를 볼 수 없다.
- sink 전달 시각과 `occurredAt`은 별개다.

queue에는 그 record를 생성할 때 읽은 logger를 함께 저장한다. 따라서 dispose callback이
미리 캡처한 logger를 사용하는 기존 동작도 유지한다.

queue는 동기적으로 drain되므로 정상적인 호출이 끝나면 비어 있다. 별도 bounded queue나
drop policy는 도입하지 않는다. 무한히 새 dispatch를 만드는 악성 logger는 지원 계약
밖이며, 비동기 내구성은 adapter 책임이다.

### 7. Formatter는 실제 occurrence를 사용한다

`EventLogRecordFormatter`는 다음처럼 변경한다.

```dart
BlocpodLogEntry(
  timestamp: record.occurredAt,
  metadata: <String, Object?>{
    if (record.recordSequence != null)
      'recordSequence': record.recordSequence,
    // 기존 구조화 metadata
  },
);
```

`recordSequence`를 reserved metadata key에 추가해 사용자 metadata가 관측 순서를
덮어쓰지 못하게 한다. pretty formatter가 compact formatter에 위임하는 기존 구조는
유지한다.

---

## Dispatch Data Flow

```text
dispatch(event)
  ├─ await initial future
  ├─ capture stateAtStart
  ├─ create owner-scoped active context + observation + Stopwatch
  ├─ emit eventStarted
  ├─ run onEvent inside context
  │    ├─ nested dispatch → child context/span
  │    └─ owned state write
  │         ├─ commit super.state
  │         ├─ update event-local observation
  │         └─ enqueue transition
  └─ finally
       ├─ close context
       ├─ stop Stopwatch
       ├─ fold same-owner child outcome when applicable
       ├─ remove active observation
       └─ emit eventCompleted or eventFailed from event-local outcome
```

Terminal logger record가 만들어진 뒤 handler error가 있었다면 원래 error와 stack trace를
`Error.throwWithStackTrace`로 다시 던진다. logger나 summary 실패가 원래 오류를
대체해서는 안 된다.

## Ordering Contract

Blocpod이 생성한 record는 다음 계약을 제공한다.

1. `recordSequence`는 하나의 Dart isolate 안에서 유일하고 엄격히 증가한다.
2. 하나의 span에서는 `eventStarted < transition* < terminal`이다.
3. start가 성공적으로 기록된 dispatch에는 `eventCompleted` 또는 `eventFailed`가 정확히
   하나 존재한다.
4. `transitionIndex`는 dispatch마다 1부터 시작한다.
5. 동시 dispatch record는 서로 interleave될 수 있으며 `recordSequence`가 관찰된 실제
   순서를 정의한다.
6. awaited child는 parent와 같은 trace ID, 새 span ID, parent span ID를 가진다.
7. parent/child 관계는 record 인접성이 아니라 trace/span field로 판단한다.
8. closed dispatch Zone에서 나중에 시작된 dispatch는 새 root trace를 가진다.
9. dispatch context가 없는 명시적 `TraceContext.run` Zone에서는 해당 trace의 child를
   계속 만들 수 있다.
10. wall clock이 같거나 역행해도 sequence와 monotonic duration 계약은 유지된다.

## Error and Reentrancy Contract

- handler 실패: terminal failure record를 생성하고 원래 error/stack을 다시 던진다.
- state assignment 실패: transition을 생성하지 않고 원래 오류를 전파한다.
- logger 실패: 해당 호출을 삼키고 이후 record 전달을 계속한다.
- metadata/label hook 실패: 빈 metadata 또는 `null` label fallback을 사용한다.
- cross-controller 직접 write: state 변경은 수행되지만 현재 이벤트 transition으로
  기록하지 않는다.
- closed-context write: state 변경은 수행되지만 종료된 이벤트로 기록하지 않는다.
- logger 재진입: 새 record는 FIFO 뒤에 추가되며 callback depth는 1을 넘지 않는다.
- logger에서 시작한 dispatch: neutral context에서 시작하므로 root trace가 된다.

## Compatibility

유지되는 사항:

- `EventController.dispatch(E)`
- `EventControllerNotifier.onEvent(E)`
- 하위 클래스의 `state = next`
- `EventLogger.log(EventLogRecord)`
- 기존 custom logger 구현
- 기존 `EventLogRecord` constructor 호출
- awaited nested dispatch와 concurrent dispatch 지원

의도적으로 바뀌는 관찰 의미:

- completion의 `nextState*`는 공유 state의 completion-time snapshot이 아니라
  dispatch-local causal outcome이다.
- transition callback은 state assignment 성공 후 호출된다.
- formatter timestamp는 `startedAt`이 아니라 `occurredAt`이다.
- logger callback은 dispatch/trace context가 제거된 상태에서 실행된다.
- Blocpod 생성 record에는 `recordSequence`가 포함된다.

## Alternatives Rejected

### Controller별 dispatch 직렬화

completion snapshot은 단순해지지만 기존 concurrency를 깨고, 같은 controller에서
awaited nested dispatch를 사용할 때 reentrant lock이 없으면 교착된다. lock을
재진입 가능하게 만들면 현재 문제보다 복잡한 dispatch scheduler가 된다.

### 공개 scope/token API

`onEventScoped`, `scope.setState`, `scope.detached` 같은 API는 in-flight detached Future까지
명시적으로 구분할 수 있다. 그러나 모든 사용자에게 새 개념을 노출하고 기존
`state = next` locality를 약화한다. 현재 확인된 문제는 owner/active context와
event-local observation으로 해결하며, 명시적 scope는 별도 요구가 생길 때 검토한다.

### 전역 state revision journal

모든 interleaving을 재구성할 수 있지만 completion 의미를 위해 필요 이상으로 많은
필드와 상태를 노출한다. transition record와 isolate sequence, dispatch-local outcome이면
현재 logger 요구를 충족한다.

---

## Verification

`blocpod_arch`:

1. controller A의 event Zone에서 controller B를 직접 변경해도 A transition이 생기지 않는다.
2. dispatch 종료 뒤 inherited Zone에서 상태를 변경해도 종료된 event transition이 생기지 않는다.
3. 같은 controller의 concurrent dispatch는 각자의 transition index와 completion outcome을 가진다.
4. concurrent sibling이 마지막으로 쓴 공유 state가 다른 event completion에 섞이지 않는다.
5. awaited same-controller child는 child span을 만들고 child outcome이 active parent causal
   outcome에 합쳐진다.
6. child 뒤 parent가 직접 상태를 쓰면 parent의 직접 상태가 parent completion outcome이다.
7. fire-and-forget child가 parent 종료 후 끝나면 parent outcome에 합쳐지지 않는다.
8. failed `super.state` assignment는 transition을 만들지 않는다.
9. transition logger callback은 이미 반영된 state를 관찰한다.
10. reentrant logger의 최대 callback depth는 1이다.
11. logger가 첫 record에서 던져도 다음 record는 전달된다.
12. logger에서 시작한 dispatch는 관찰 중 span의 child가 아니라 root span이다.
13. closed dispatch Zone을 상속한 detached callback의 dispatch는 새 root span이다.
14. dispatch context 없이 명시적으로 설정한 `TraceContext`에서는 기존 child-span
    동작을 유지한다.
15. closed dispatch Zone 안에서 명시적으로 새 `TraceContext`를 설정하면 해당
    trace의 child-span 동작을 유지한다.
16. 동기 listener가 같은 notifier state를 재진입 변경해도 transition과 terminal
    outcome은 실제 커밋 순서를 유지한다.
17. 한 dispatch의 모든 record는 같은 `startedAt`을 갖고 서로 다른 phase별
    `occurredAt`을 가질 수 있다.
18. Blocpod 생성 record의 `recordSequence`는 isolate 안에서 엄격히 증가한다.
19. handler failure는 event-local failure record를 만들고 원래 error/stack을 보존한다.
20. 기존 lifecycle, metadata snapshot, nested trace 테스트는 그대로 통과한다.

`blocpod_arch_logger`:

19. formatter timestamp가 `record.occurredAt`과 같다.
20. `recordSequence`가 structured metadata에 포함된다.
21. 사용자 metadata의 `recordSequence`는 reserved key를 덮어쓰지 못한다.
22. `recordSequence == null`인 기존 수동 record도 정상 formatting된다.
23. `BlocpodEventLogger`는 record당 sink write를 한 번만 수행한다.
24. compact/pretty formatter의 기존 message와 error 표현은 회귀하지 않는다.

전체 패키지:

25. `packages/arch`, `packages/arch_logger`, `packages/logger`, `packages/sample`의
    `flutter test`가 통과한다.
26. 위 네 패키지의 `flutter analyze`가 통과한다.
