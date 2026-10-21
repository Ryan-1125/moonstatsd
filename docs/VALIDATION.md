# Validation record

Date: 2026-10-21, Asia/Shanghai. Initial observations are local; subsequent GitHub observations are recorded in
the follow-up section. No registry publication occurred. Raw logs and metrics are
in .local/evidence.

## Environment and initial state

- Working directory: D:/GitHub/MoonStatsD (same Windows directory as moonstatsd).
  Initially empty, no Git repository or pre-existing applicable AGENTS.md. `moon new`
  initialized an independent repository and generated AGENTS.md, subsequently read.
- moon 0.1.20261020 (2284bd2); moonc v0.10.16+b1a0e846e.
- Git 2.53.0.windows.3; Node v22.22.1; Go go1.23.2 windows/amd64.
- PATH Go was absent; differential testing used the existing read-only executable
  D:/GitHub/moonfcgi/.local/work/go/bin/go.exe through GO_EXE. All new Go caches and
  module downloads were redirected into this project's .local. No MoonFCGI files
  were modified and no SDK credentials were copied.
- Sandboxed moon current-directory resolution and Git index creation returned
  access-denied errors. Authorized elevated local runs succeeded. Initial template
  check/build succeeded with 0 tests; it is not counted as functional validation.

## Core and lifecycle

Final functional test commands and actual output:

```
moon test --target native --deny-warn
Total tests: 15, passed: 15, failed: 0.

moon test --target wasm-gc --package Ryan-1125/moonstatsd --deny-warn
Total tests: 6, passed: 6, failed: 0.
```

Coverage includes fixed wire vectors for six types; explicit negative absolute
gauge rejection; signed zero; deterministic sampling; protocol-mode and DogStatsD
name restrictions; duplicate tag keys; field injection; UTF-8 and exact packet
boundaries; batch budget; actual local UDP data and packet boundaries; queue full;
idle periodic send; concurrent producers and flush/close/repeat close; callback
failure; scope cancellation; flush waiter cancellation; close waiter cancellation;
actual already-closed socket send error accounting.

Two internal deterministic timeout checks use an unstarted owner, so the state
cannot progress before its deadline. Those checks validate waiting/state logic,
not an induced network stall. Real socket tests and collector tests are separate;
no mock is substituted for UDP acceptance. No claim of exhaustive schedule or
network-fault coverage is made.

## Actual collectors

```
./tools/install-collectors.ps1
Fixed collectors downloaded and SHA256 verified (no npm install needed).

node tools/test-interop.mjs
submitted=9 send_errors=0 dropped=0 closed=true
statsd_exporter v0.28.0: 12 collector assertions passed
submitted=7 errors=0
StatsD v0.9.0: sampled counter=4, gauge=7, timer=250ms, unique set=2
```

Exporter revision: c0a390a2c43f77863278615b47d46e886bdca726, windows/amd64,
Go 1.23.2. Arguments: --web.listen-address=127.0.0.1:19102,
--statsd.listen-udp=127.0.0.1:19125, --statsd.listen-tcp= (disabled).
Actual GET /metrics excerpts:

```
moon_requests{env="test",route="home",service="demo",status="200"} 2
moon_queue{env="test",service="demo"} 7
moon_active{env="test",service="demo"} 2
moon_latency_sum{env="test",route="home",service="demo"} 0.25
moon_latency_count{env="test",route="home",service="demo"} 1
moon_jobs{env="test",result="success",service="demo"} 1
moon_job_time_sum{env="test",service="demo"} 1.5
moon_payload_sum{env="test",service="demo"} 42
moon_payload_count{env="test",service="demo"} 1
moon_distribution_sum{env="test",service="demo"} 5
moon_distribution_count{env="test",service="demo"} 1
statsd_exporter_lines_total 9
```

The final DogStatsD example uses nonnegative absolute queue snapshots (10 then 7),
not deltas. The independent official StatsD 0.9.0 process receives seven basic
StatsD messages. Its real aggregate output contains:

```
"plain.count": 4
"plain.queue": 7
"plain.time": [250]
"plain.unique": ["alice", "bob"]
```

Counter input=2, rate=0.5, injected draw=0.1; receiver rescales to 4. Gauge inputs
10 then delta -3; Set inputs alice, alice, bob. Official receiver performs parsing,
sampling correction, arithmetic, storage and uniqueness. The custom backend only
serializes aggregate output. Config binds UDP 19126 and management TCP 19127 to
127.0.0.1, flush interval 1000ms, with no Graphite/Datadog account or remote sink.
Processes started by the tests are stopped in finally blocks. Local tests
observe collector receipt; public flush still cannot acknowledge UDP delivery.

## Reference client

```
$env:GO_EXE='D:/GitHub/moonfcgi/.local/work/go/bin/go.exe'
$env:GOPROXY='https://goproxy.cn'
node tools/test-reference.mjs

datadog-go v5.8.3: 6 wire cases semantically equal (timer decimal formatting normalized)
```

The first default proxy download timed out; a process-local mirror retry completed
with module checksum validation. Common cases cover c/g/ms/s/h/d, prefix and fixed
plus per-call tags at rate=1. The real reference client's aggregation, telemetry
and origin detection are disabled; its writer captures actual formatted payloads.
Timer emits 12.500000 in Go and 12.5 in MoonBit, compared numerically. No performance
or full compatibility conclusion is drawn from these six cases.

## Package and independent consumer

```
./tools/test-consumer.ps1
Independent published-ZIP consumer: codec and real UDP passed
```

The script builds the local Moon ZIP, extracts it into a fresh .local/consumer-GUID
workspace, creates a separate application, updates dependencies, compiles, checks
a fixed codec vector, sends a real metric and asserts receiver bytes. The workspace
links the extracted library, never the working-tree library. First successful
consumer: consumer-5acf0cc4bb614c98bbe8f0f046e3797b. This is local ZIP consumption,
not a registry install test.

```
./tools/audit-package.ps1
Actual ZIP audit passed: 35 entries, no private/build artifacts.
```

Final independent consumer: consumer-7f8fed28f16b485a8b9367051619f735.
The final audit read 35 entries directly from the actual ZIP. `.local`, logs, credentials, SDKs, build
outputs, Git metadata and downloaded third-party artifacts are excluded. The
missing repository field produces a packaging warning, deliberately retained
rather than inventing a remote URL.

## Initially unverified (superseded where noted below)

- Remote GitHub Actions runs (workflow delivered only), Linux execution and
  non-amd64 platforms; no throughput benchmark.
- Commercial Datadog Agent end-to-end behavior; only shared wire and the actual
  receivers above are validated. Negative absolute gauge and DogStatsD relative
  gauge are deliberately unsupported.
- Registry publication/new-install consumption and hackathon submission/review.
- Exhaustive competing-package audit: related package review and its OTEL old
  dependency-format limitation are documented in SOURCES.md.

At the initial handoff no remote repository creation, push, package publication
or registration submission had been performed. Subsequent GitHub authorization
and upload are recorded below. No Mooncakes publication or registration occurred.

## Follow-up: GitHub and diagnostic hardening (2026-10-21)

The user subsequently authorized GitHub creation and upload. Repository created as
private at https://github.com/Ryan-1125/moonstatsd, with existing commits pushed.
First actual run: https://github.com/Ryan-1125/moonstatsd/actions/runs/39462578339
Ubuntu completed all steps successfully. Windows failed at `moon fmt --check`:
Git could not open/hash the formatter's extended-path temporary outputs. Its
installed CLI was 0.1.20261016. The same CLI passes locally on LF source files;
we are adding repository LF attributes to eliminate checkout line-ending drift
before rerunning. No successful Windows CI result is inferred from this change.

Client follow-up adds InvalidConfig(reason), rejects destination port zero before
opening a socket, and preserves the latest local send error in Stats.last_send_error.
An actual closed-socket test checks that an error message is retained. Invalid
capacity/datagram/interval/timeout/wire-budget inputs are tested to reject without
entering the callback. Local native result: 16 passed, 0 failed.

### Confirmed follow-up evidence

Repository: https://github.com/Ryan-1125/moonstatsd (private; no visibility answer
was received, so upload used the conservative private default).

| Platform / snapshot | Actual result | Evidence |
|---|---|---|
| Ubuntu, 280bf37 | All workflow steps passed; native 15/15, wasm-gc 6/6 | run 39462578339, job 118765568834 |
| Windows, 39db0b3 | All workflow steps passed; native 16/16, wasm-gc 6/6 | run 39462963061, job 118766868244 |
| Ubuntu, 39db0b3 | Still queued at last observation | run 39462963061, job 118766868611 |

Run links:
- https://github.com/Ryan-1125/moonstatsd/actions/runs/39462578339
- https://github.com/Ryan-1125/moonstatsd/actions/runs/39462963061

Both successful jobs actually ran the two fixed collectors, six-case reference
comparison, independent ZIP consumer and 35-entry ZIP audit. This is not a claim
that the queued Ubuntu job has passed. CI SDK for these runs: moon 0.1.20261016,
moonc v0.10.16+b1a0e846e. Logs retained locally as
.local/evidence/ci-ubuntu-280bf37.log and ci-windows-39db0b3.log.

With .gitattributes enforcing LF, a fresh local clone explicitly using
core.autocrlf=true had zero CR bytes in client/client.mbt and passed the same
0.1.20261016 CLI format check. The next remote Windows run passed all steps.
This records the observed correction without inferring a broader upstream cause.

The improved client's independent local ZIP consumer also passed at
consumer-0fdceb72f14d4f719938c7da90582b20; final package audit still found 35
entries without private/build artifacts. Normal VS Code was launched with
`code --new-window D:/GitHub/MoonStatsD`; no isolated profile or global SDK switch.

### Visibility update

The user subsequently selected public visibility. Repository visibility was changed
to public and anonymous GitHub API access to Ryan-1125/moonstatsd was verified.
The earlier private-creation statements above describe the historical upload.

### CI completion update

Runs 39462963061 (39db0b3) and 39463913880 (accf41c) subsequently
completed successfully. Both Windows and Ubuntu jobs passed; the queued statuses
above are historical observations, not current failures.
https://github.com/Ryan-1125/moonstatsd/actions/runs/39463913880

## Continued production and caller-owned tag snapshots

Three additional native real-UDP regression groups now verify that a flush
barrier returns for its captured admissions while a later batch remains pending;
that close racing an active producer rejects new admissions and drains accepted
ones; and that mutations to fixed/call tag arrays cannot alter already captured
configuration or wire messages. Each uses a real ephemeral loopback UDP socket.

`moon test --target native --deny-warn`: Total tests: 19, passed: 19, failed: 0.
These tests assert local submission/accounting and selected received bytes, not
reliable delivery of every UDP datagram. Timeout-based schedule assumptions are
avoided: task yields and a backlog larger than a single packet establish the
competition under test.
