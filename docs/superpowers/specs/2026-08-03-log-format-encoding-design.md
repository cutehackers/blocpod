# Blocpod 로그 포맷 및 Encoder 설계

## 1. 목적

Blocpod 0.3.0의 기본 로그 출력을 분석 가능한 JSON Lines로 전환하고,
로컬 개발자를 위한 간결한 사람용 출력을 별도 encoder로 제공한다.

이 설계는 다음 목표를 만족해야 한다.

- 기본 출력은 Blocpod 독립 JSON 스키마를 사용한다.
- 로그 한 건은 물리적으로 JSON 한 줄로 출력한다.
- 외부 관측 플랫폼과의 연동은 이후 별도 adapter가 담당한다.
- 사람용 로그는 짧고 빠르게 읽을 수 있어야 한다.
- 포맷과 출력 위치의 책임을 분리한다.
- `recordSequence`, trace와 구조화 attributes를 문자열 파싱 없이 사용할 수
  있어야 한다.
- logger는 개인정보 또는 비밀정보를 자동으로 판단하거나 제거하지 않는다.
- 지원하지 않는 metadata 값 때문에 애플리케이션 흐름이 실패하지 않는다.

## 2. 릴리즈 범위

이 변경은 아직 배포되지 않은 다음 릴리즈에 포함한다.

- `blocpod_logger`: `0.1.1`에서 `0.2.0`으로 변경
- `blocpod_arch`: `0.3.0` 유지
- `blocpod_arch_logger`: `0.3.0` 유지하고 `blocpod_logger: ^0.2.0` 사용
- sample 앱: 사람용 formatter를 사용하도록 갱신

기본 출력 형식 변경은 `blocpod_logger 0.2.0`의 의도된 breaking change다.

## 3. 책임 분리

로그 처리 경로를 record, entry, encoder와 sink로 분리한다.

```text
EventLogRecord
  -> BlocpodEventLogFormatter
    -> BlocpodLogEntry
      -> BlocpodLogSink.write(entry)
        -> DebugPrintLogSink
          -> BlocpodLogEncoder.encode(entry)
            -> debugPrint(encoded)
```

각 구성 요소의 책임은 다음과 같다.

- `EventLogRecord`: Blocpod 이벤트 관측 사실을 표현한다.
- `BlocpodEventLogFormatter`: 이벤트 관측 사실을 범용 log entry로 변환한다.
- `BlocpodLogEntry`: 출력 방식에 독립적인 구조화 로그 envelope다.
- `BlocpodLogEncoder`: log entry를 JSON 또는 사람용 문자열로 직렬화한다.
- `BlocpodLogSink`: log entry를 출력 위치로 전달한다. 문자열 기반 sink는 내부에서
  encoder를 사용한다.

formatter가 최종 JSON을 `message`에 넣거나 JSON과 사람용 sink를 각각
복제해서 구현하지 않는다. 포맷은 encoder가 소유하고 전송은 sink가 소유한다.

`BlocpodLogEncoder`는 문자열 기반 sink를 위한 선택적 직렬화 도구다. 모든 sink가
encoder를 통과해야 하는 것은 아니다. 외부 로깅 라이브러리 adapter는
`BlocpodLogSink`를 구현하고 구조화된 `BlocpodLogEntry`를 직접 변환한다.

```text
BlocpodLogEntry
  +-> DebugPrintLogSink -> JsonLogEncoder | PrettyLogEncoder -> debugPrint
  +-> TalkerLogSink -----------------------------------------> Talker
  +-> UserProvidedLogSink -----------------------------------> user logger or SDK
```

따라서 `DebugPrintLogSink`는 기본 제공 adapter일 뿐 고정된 하위 의존성이 아니며,
Talker 같은 외부 logger로 완전히 교체할 수 있다.

`UserProvidedLogSink`는 Blocpod이 export하는 실제 클래스명이 아니라 사용자가
`BlocpodLogSink`를 구현해 제공하는 sink를 나타내는 설계 문서상의 역할명이다.
실제 구현은 연결 대상에 맞춰 `TalkerLogSink`처럼 구체적인 이름을 사용한다.

## 4. 공개 API

### 4.1 `BlocpodLogEncoder`

```dart
abstract interface class BlocpodLogEncoder {
  String encode(BlocpodLogEntry entry);
}
```

두 기본 구현을 제공한다.

```dart
final class JsonLogEncoder implements BlocpodLogEncoder {
  const JsonLogEncoder({this.maxDepth = 8}) : assert(maxDepth > 0);

  final int maxDepth;
}
```

```dart
enum PrettyLogDetail {
  compact,
  verbose,
}

final class PrettyLogEncoder implements BlocpodLogEncoder {
  const PrettyLogEncoder({
    this.detail = PrettyLogDetail.compact,
  });

  final PrettyLogDetail detail;
}
```

사람용 encoder 이름에는 `HumanReadable` 대신 프로젝트 용어와 기존 formatter
이름에 맞는 `Pretty`를 사용한다.

### 4.2 `BlocpodLogEntry`

`metadata`를 범용 관측 용어인 `attributes`로 변경하고 sequence와 trace를 전용
필드로 승격한다.

```dart
final class BlocpodLogEntry {
  const BlocpodLogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.sequence,
    this.traceId,
    this.spanId,
    this.parentSpanId,
    this.attributes = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  final BlocpodLogLevel level;
  final String message;
  final DateTime timestamp;
  final int? sequence;
  final String? traceId;
  final String? spanId;
  final String? parentSpanId;
  final Map<String, Object?> attributes;
  final Object? error;
  final StackTrace? stackTrace;
}
```

`metadata` deprecated alias는 제공하지 않는다. 이 변경은
`blocpod_logger 0.2.0` migration에 명시한다.

### 4.3 `DebugPrintLogSink`

`DebugPrintLogSink`는 encoder를 주입받으며 JSON을 기본값으로 사용한다.

```dart
final class DebugPrintLogSink implements BlocpodLogSink {
  DebugPrintLogSink({
    BlocpodLogEncoder encoder = const JsonLogEncoder(),
    DebugPrintCallback? debugPrintOverride,
  });
}
```

기본 사용은 JSON Lines를 출력한다.

```dart
BlocpodEventLogger(DebugPrintLogSink())
```

사람용 출력은 encoder를 명시한다.

```dart
BlocpodEventLogger(
  DebugPrintLogSink(
    encoder: const PrettyLogEncoder(),
  ),
  formatter: const PrettyEventLogRecordFormatter(),
)
```

기존 공개 함수 `formatBlocpodLogEntry`는 제거하지 않고 기본 JSON encoder로
연결한다.

```dart
String formatBlocpodLogEntry(BlocpodLogEntry entry) {
  return const JsonLogEncoder().encode(entry);
}
```

호출 코드는 유지되지만 반환 형식은 0.2.0부터 평문이 아니라 JSON 한 줄이다.

### 4.4 외부 logger 교체 지점

`BlocpodLogSink`는 외부 logger를 연결하는 공식 port다. 인터페이스는 구조화된
entry를 그대로 전달하는 현재 형태를 유지한다.

```dart
abstract interface class BlocpodLogSink {
  void write(BlocpodLogEntry entry);
}
```

Talker adapter의 개념적 형태는 다음과 같다.

```dart
final class TalkerLogSink implements BlocpodLogSink {
  TalkerLogSink(this.talker);

  final Talker talker;

  @override
  void write(BlocpodLogEntry entry) {
    talker.logCustom(BlocpodTalkerLog(entry));
  }
}
```

`BlocpodTalkerLog`는 adapter가 소유하며 level, timestamp, trace, attributes, error와
stack trace를 Talker 데이터 모델로 변환한다. adapter는 JSON이나 pretty 문자열을
재파싱하지 않는다. 문자열 입력만 지원하는 외부 logger라면 adapter가 필요에 따라
`JsonLogEncoder` 또는 `PrettyLogEncoder`를 명시적으로 사용할 수 있다.

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(
    TalkerLogSink(talker),
  ),
)
```

`blocpod_logger`와 `blocpod_arch_logger`는 Talker를 포함한 특정 외부 logger에
의존하지 않는다. Talker adapter는 애플리케이션 또는 향후 별도 integration
패키지가 소유한다.

## 5. 기본 JSON Lines 스키마

### 5.1 Envelope

```json
{
  "schema": "blocpod.log",
  "schemaVersion": 1,
  "timestamp": "2026-08-03T01:00:01.001Z",
  "sequence": 104,
  "level": "info",
  "message": "CounterController IncrementEvent state.transition",
  "trace": {
    "traceId": "trace-ab12",
    "spanId": "span-cd34",
    "parentSpanId": "span-parent"
  },
  "attributes": {
    "phase": "state.transition",
    "controllerName": "CounterController",
    "eventName": "IncrementEvent",
    "transitionIndex": 1,
    "previousStateKind": "data",
    "nextStateKind": "data",
    "hasChanged": true,
    "previousStateLabel": "count:0",
    "nextStateLabel": "count:1",
    "eventMetadata": {
      "amount": 1
    },
    "stateMetadata": {
      "changedBy": 1
    }
  }
}
```

스키마 규칙은 다음과 같다.

- `schema`, `schemaVersion`, `timestamp`, `level`, `message`는 항상 존재한다.
- `schema` 값은 `blocpod.log`다.
- 최초 `schemaVersion`은 정수 `1`이다.
- `timestamp`는 UTC ISO-8601 문자열이다.
- `sequence`는 `BlocpodLogEntry.sequence`가 있을 때만 존재한다.
- `trace`는 trace 관련 필드가 하나라도 있을 때만 존재한다.
- `trace` 안에서도 null 필드는 생략한다.
- `attributes`는 비어 있지 않을 때만 존재한다.
- `error`는 error 또는 stack trace가 있을 때만 존재한다.
- 각 JSON 객체는 개행을 포함하지 않는 한 줄이어야 한다.
- top-level 키와 framework가 생성하는 attribute 키의 출력 순서는 고정한다.
- JSON object key 순서를 의미론적 정렬 기준으로 사용해서는 안 된다.

`EventLogRecord.recordSequence`는 Dart API에서 이름을 유지하지만
`BlocpodLogEntry.sequence` 및 JSON의 `sequence`로 변환한다.

### 5.2 오류 표현

```json
{
  "schema": "blocpod.log",
  "schemaVersion": 1,
  "timestamp": "2026-08-03T01:00:02.000Z",
  "sequence": 108,
  "level": "error",
  "message": "CounterController SaveEvent event.failed",
  "trace": {
    "traceId": "trace-ab12",
    "spanId": "span-cd34"
  },
  "attributes": {
    "phase": "event.failed",
    "controllerName": "CounterController",
    "eventName": "SaveEvent",
    "durationMicros": 12000
  },
  "error": {
    "type": "StateError",
    "message": "Bad state: save failed",
    "stackTrace": "..."
  }
}
```

- `type`은 `error.runtimeType.toString()`이다.
- `message`는 `error.toString()`이다.
- `stackTrace`는 `stackTrace.toString()`이다.
- error가 없고 stack trace만 있으면 `type`과 `message`는 생략한다.

### 5.3 이벤트 attributes

`EventLogRecordFormatter`는 sequence와 trace를 `BlocpodLogEntry` 전용 필드로
매핑하고 나머지 이벤트 정보를 attributes로 변환한다.

framework attributes는 해당 값이 존재할 때 다음 순서로 추가한다.

1. `phase`
2. `controllerName`
3. `eventName`
4. `durationMicros`
5. `transitionIndex`
6. `previousStateKind`
7. `nextStateKind`
8. `hasChanged`
9. `previousStateLabel`
10. `nextStateLabel`
11. `eventMetadata`
12. `stateMetadata`

사용자 event metadata는 framework attributes와 평면 병합하지 않고
`eventMetadata` 객체에 둔다. 상태 metadata는 `stateMetadata` 객체에 둔다.
이 경계는 사용자 key가 `phase`, `sequence` 또는 trace 같은 시스템 의미를
덮어쓰지 못하게 한다.

## 6. JSON 값 정규화

`JsonLogEncoder`는 attributes와 오류 표현을 JSON-safe 값으로 정규화한다.

| Dart 값 | JSON 표현 |
| --- | --- |
| `null`, `String`, `bool`, 유한 `num` | 원래 값 |
| `DateTime` | UTC ISO-8601 문자열 |
| `Duration` | microseconds 정수 |
| `Enum` | `name` 문자열 |
| `Map` | key를 문자열로 바꾼 뒤 value를 재귀 정규화 |
| `Iterable` | JSON 배열로 재귀 정규화 |
| `NaN`, 양/음의 infinity | `NaN`, `Infinity`, `-Infinity` 문자열 |
| 그 밖의 객체 | 안전한 `toString()` 결과 |

순환 참조가 발견되면 해당 위치를 `"<cycle>"`로 표현한다. `maxDepth`를
초과하면 `"<max-depth-exceeded>"`로 표현한다. 객체의 `toString()`이 예외를
던지면 `"<RuntimeType>"` 형태의 타입 설명만 남긴다.

서로 다른 map key가 문자열 변환 후 같아지면 iteration에서 나중에 만난 값이
앞선 값을 대체한다. `maxDepth`는 1 이상이어야 하며 그렇지 않은 구성은 생성 시
assertion으로 거부한다.

최종 envelope 인코딩까지 실패하면 다음 필드만 가진 최소 JSON을 출력한다.

```json
{"schema":"blocpod.log","schemaVersion":1,"timestamp":"2026-08-03T01:00:01.001Z","level":"error","message":"Blocpod log encoding failed"}
```

fallback도 유효한 한 줄 JSON이어야 한다. 인코딩 실패는 애플리케이션 예외로
전파하지 않는다.

## 7. 개인정보 및 비밀정보 계약

logger, formatter와 encoder는 자동 redaction을 수행하지 않는다. 다음 데이터의
안전성은 로그를 생성하거나 attributes를 제공하는 사용자의 책임이다.

- attributes와 중첩 값
- event metadata
- state metadata
- error message
- stack trace

기존 `DebugPrintLogSink`의 key 이름 기반 redaction은 제거한다. 자동으로 일부
키만 제거하면 로그가 안전하다는 잘못된 보장을 만들 수 있기 때문이다. 특정
플랫폼 또는 애플리케이션에서 redaction이 필요하면 별도 adapter, encoder wrapper
또는 sink wrapper로 구현한다.

## 8. Pretty 출력

### 8.1 기본 형식

`PrettyLogEncoder`는 짧은 UTC 시각, level과 formatter가 만든 message를 한 줄로
출력한다. ANSI color는 사용하지 않는다.

```text
10:00:00.000Z INFO  🟢 CounterController created
10:00:00.010Z INFO  🔵 CounterController established data(count:0)
10:00:01.000Z INFO  🟡 CounterController · IncrementEvent started from data(count:0)
10:00:01.001Z INFO  ✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)
10:00:01.002Z INFO  ✅ CounterController · IncrementEvent completed data(count:0) → data(count:1) in 2ms
10:00:05.000Z INFO  ⚪ CounterController disposed
```

`PrettyEventLogRecordFormatter`가 이벤트 단계별 문장을 만들고
`PrettyLogEncoder`가 시각과 level을 붙인다. 기존 여러 줄 pretty event message는
위와 같은 한 줄 문장으로 변경한다.

### 8.2 상세 수준

`PrettyLogDetail.compact`가 기본값이다.

- 짧은 UTC 시각
- level
- message
- error와 stack trace

compact에서는 sequence, trace와 attributes를 숨긴다.

`PrettyLogDetail.verbose`는 두 번째 줄 이후에 진단 정보를 추가한다.

```text
10:00:01.001Z INFO  ✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)
  sequence=104 trace=trace-ab12/span-cd34 parent=span-parent
  attributes={phase: state.transition, controllerName: CounterController, eventName: IncrementEvent, transitionIndex: 1, eventMetadata: {amount: 1}, stateMetadata: {changedBy: 1}}
```

verbose 모드에서 값이 없는 sequence, trace line이나 비어 있는 attributes line은
생략한다.

### 8.3 오류 출력

```text
10:00:02.000Z ERROR 🔴 CounterController · SaveEvent failed data(ready) → error(saveFailed) in 12ms
  StateError: Bad state: save failed
  #0 SaveController.onEvent (...)
  #1 EventControllerNotifier.dispatch (...)
```

stack trace가 존재하면 compact와 verbose 모두 출력한다. 오류와 stack trace는
여러 줄을 허용하는 유일한 기본 예외다.

### 8.4 duration 표현

- 1 millisecond 미만: 정수 microseconds와 `µs`
- 1 second 미만: 정수 milliseconds와 `ms`
- 1 second 이상: 불필요한 후행 0을 제거한 최대 소수점 둘째 자리 seconds와 `s`

예: `840µs`, `2ms`, `124ms`, `1.24s`, `2s`.

## 9. Sample 앱

sample 앱의 in-memory sink는 문자열 인코딩 전 `BlocpodLogEntry`를 저장한다.
화면은 사람이 읽는 UI이므로 `PrettyEventLogRecordFormatter`를 사용해 message를
다음과 같이 표시한다.

```text
✨ SampleCounterController · CounterIncremented transition[1] data(count:0) → data(count:1)
```

sequence, trace와 attributes는 기본 목록에서 숨긴다. 상세 화면은 이번 범위에
추가하지 않는다.

## 10. 외부 adapter 경계

이번 릴리즈는 OpenTelemetry, Datadog, CloudWatch, Firebase, Sentry 등의 특정
플랫폼에 의존하지 않는다. 이후 adapter는 JSON 문자열을 재파싱하지 않고
`BlocpodLogEntry`의 전용 필드와 attributes를 직접 읽어 플랫폼 데이터 모델로
변환한다.

외부 adapter의 교체 지점은 `BlocpodLogEncoder`가 아니라 `BlocpodLogSink`다.
encoder는 `debugPrint`, 파일 또는 문자열 stream처럼 문자열이 필요한 sink에서만
사용한다. Talker처럼 자체 데이터 모델과 출력 파이프라인이 있는 라이브러리는
user-provided sink에서 `BlocpodLogEntry`를 직접 매핑한다.

외부 adapter는 다음 책임을 가진다.

- Blocpod level을 외부 logger level로 매핑
- message, timestamp와 sequence 전달
- trace/span과 attributes 전달 또는 외부 모델에 맞게 변환
- error와 stack trace 전달
- 외부 logger의 filtering, history, formatting 및 전송 API 호출
- 필요하다면 해당 플랫폼 정책에 맞는 redaction 수행

Blocpod core와 기본 logger 패키지는 외부 SDK type, level 또는 lifecycle을 알지
않는다.

파일 또는 네트워크 sink, batching, retry, sampling, 앱 인스턴스 ID와 isolate ID
자동 생성도 이번 범위에 포함하지 않는다.

## 11. 오류 격리

- encoder는 지원하지 않는 값을 정규화하고 가능한 한 레코드를 보존한다.
- encoder의 최종 실패는 최소 fallback 문자열로 바꾼다.
- `DebugPrintLogSink`는 선택된 encoder 결과를 한 번의 `debugPrint` 호출로 전달한다.
- `BlocpodEventLogger`의 기존 sink 실패 격리를 유지한다.
- formatter, encoder 또는 sink 실패는 controller 상태, dispatch 결과, 원래 handler
  오류, provider lifecycle과 disposal을 변경하지 않는다.
- Blocpod core의 동기 FIFO logger 전달 계약은 변경하지 않는다. 느린 encoder나
  sink는 emitter를 지연시킬 수 있다.

## 12. 문서 및 Migration

다음 내용을 CHANGELOG와 README에 반영한다.

- `blocpod_logger 0.2.0`부터 `DebugPrintLogSink` 기본 출력이 JSON Lines라는 점
- `metadata`가 `attributes`로 변경됐다는 점
- sequence와 trace가 `BlocpodLogEntry` 전용 필드로 승격됐다는 점
- 기존 `formatBlocpodLogEntry`가 JSON을 반환한다는 점
- 사람용 출력에 `PrettyLogEncoder`와 `PrettyEventLogRecordFormatter`를 함께
  사용한다는 점
- 자동 redaction이 제거됐으며 데이터 안전성은 사용자 책임이라는 점
- 외부 플랫폼 연동은 별도 adapter가 담당한다는 점

## 13. 테스트 전략

### 13.1 `blocpod_logger`

- `JsonLogEncoder` 결과가 유효한 JSON 한 줄인지 검증한다.
- `schema`와 `schemaVersion`의 고정 값을 검증한다.
- top-level key 순서를 snapshot으로 고정한다.
- UTC timestamp 직렬화를 검증한다.
- null sequence와 trace 필드가 생략되는지 검증한다.
- 일부 trace 필드만 존재하는 경우의 출력을 검증한다.
- attributes가 비어 있으면 생략되는지 검증한다.
- error와 stack trace 구조를 검증한다.
- 따옴표, 역슬래시와 줄바꿈 escape를 검증한다.
- map, iterable, enum, `DateTime`, `Duration` 변환을 검증한다.
- `NaN`, infinity를 검증한다.
- 순환 map, 순환 iterable과 최대 깊이 처리를 검증한다.
- 예외를 던지는 `toString()`과 최종 fallback을 검증한다.
- encoder가 어떤 key도 자동 redaction하지 않는지 검증한다.
- `PrettyLogEncoder` compact의 정확한 한 줄을 검증한다.
- verbose에 sequence, trace와 attributes가 선택적으로 포함되는지 검증한다.
- 오류와 stack trace 출력 형식을 검증한다.
- duration 표현 경계는 arch logger formatter 테스트에서 검증한다.
- `DebugPrintLogSink`의 기본 encoder가 JSON인지 검증한다.
- user-provided encoder 주입과 `formatBlocpodLogEntry`의 JSON 위임을 검증한다.
- encoder를 사용하지 않는 user-provided `BlocpodLogSink`가 원본 entry 필드를 직접
  수신하는지 검증한다.
- `blocpod_logger`가 외부 logger 패키지를 import하지 않는지 dependency-direction
  테스트로 검증한다.

### 13.2 `blocpod_arch_logger`

- `recordSequence`가 `BlocpodLogEntry.sequence`로 매핑되는지 검증한다.
- trace/span/parent span이 전용 필드로 매핑되는지 검증한다.
- framework attributes의 값과 순서를 검증한다.
- 사용자 metadata가 `eventMetadata` 아래에 보존되는지 검증한다.
- state metadata가 `stateMetadata` 아래에 보존되는지 검증한다.
- 사용자 key가 system field를 덮어쓰지 못하는지 검증한다.
- 각 phase의 compact message를 검증한다.
- 각 phase의 pretty 한 줄 message를 검증한다.
- duration의 microsecond, millisecond와 second 표현 경계를 검증한다.
- 실패 레코드가 error-level entry와 구조화 오류로 이어지는지 검증한다.

### 13.3 통합 및 sample

- 실제 event dispatch에서 JSON 레코드가 sequence 순서로 생성되는지 검증한다.
- JSON으로 decode한 phase 흐름이 실제 dispatch 흐름과 일치하는지 검증한다.
- encoder 또는 sink 실패가 dispatch 결과를 변경하지 않는지 검증한다.
- sample 화면이 pretty message를 표시하고 sequence와 내부 attributes를 기본으로
  노출하지 않는지 검증한다.

## 14. 수용 조건

1. `DebugPrintLogSink()`는 별도 설정 없이 JSON Lines를 출력한다.
2. 모든 기본 JSON 레코드는 `schema=blocpod.log`, `schemaVersion=1`을 가진다.
3. 모든 기본 JSON 레코드는 유효한 물리적 한 줄 JSON이다.
4. `recordSequence`는 JSON `sequence`로 표현되고 사람이 보는 compact 로그에서는
   숨겨진다.
5. trace/span은 JSON 전용 객체로 표현된다.
6. 사용자 event metadata와 state metadata는 서로 분리된다.
7. `PrettyLogEncoder` compact는 이벤트 한 건을 한 줄로 표현한다.
8. `PrettyLogEncoder` verbose는 sequence, trace와 attributes를 제공한다.
9. 오류와 stack trace는 JSON에서 구조화되고 pretty 출력에서 읽을 수 있다.
10. 지원하지 않는 metadata 값과 순환 참조가 애플리케이션 흐름을 깨뜨리지 않는다.
11. logger, formatter와 encoder는 자동 redaction을 수행하지 않는다.
12. 기존 FIFO 전달, event-local outcome과 trace attribution 계약은 유지된다.
13. user-provided `BlocpodLogSink`는 encoder와 `DebugPrintLogSink` 없이 구조화된
    entry를 직접 수신할 수 있다.
14. Blocpod 패키지는 Talker를 포함한 외부 logger SDK에 의존하지 않는다.
15. `blocpod_logger`, `blocpod_arch_logger`와 sample의 관련 테스트 및 정적 분석이
    통과한다.
