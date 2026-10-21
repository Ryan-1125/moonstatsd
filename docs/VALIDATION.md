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

## First official Agent run and readiness correction

Run 39540842638 at 614bdde: Windows all steps passed, Ubuntu native 19/19 and
wasm-gc 6/6 passed, but the new real Agent stage timed out. Official binary output:
`DogStatsD 7.60.0 - Commit: 799e298 - Serialization version: v5.0.134 - Go version: go1.22.8`.
HTTP intake received valid compressed JSON containing only Agent started/running
metrics, with no moonagent workload metrics. No decoding errors were observed.
The workload reported seven local submissions; that did not establish receipt.
Raw logs/series are retained under .local/evidence/agent-ci-first.

The Agent also logged an unavailable default UDS directory; fixed source shows
that this warning alone does not prevent an independent UDP listener. The test
was corrected to explicitly disable UDS in its mounted YAML, verify UDP port 8125
in the real container socket table, and send directly to the internal container IP
instead of relying on published-port routing in an internal Docker network.
The health probe is retained but is no longer the sole readiness condition.
This describes observed failure and corrective changes, not an inferred upstream
Agent defect or a successful run before the rerun completes.

## Constructor resource-bound correction

Review found that fixed_tags was copied before applying encoder input bounds, and
configuration overhead was checked against 65507 instead of the configured packet
budget. The constructor now validates a minimal `x:0|c` metric with the actual
prefix, fixed tags and max_bytes before copying the bounded array. This rejects
unusable configurations early and avoids a redundant potentially large copy of
invalid caller input. Individual records still undergo full independent size
validation. The existing five-byte packet tests continue to pass.

Added regression cases reject oversized prefix overhead, fixed-tag overhead and
excessive tag count without entering the callback. Local result:
`moon test --target native --deny-warn`: 20 passed, 0 failed. This is a bound/order
correction, not a measured heap or throughput claim.

## Second Agent run: entrypoint/version-check race

Run 39541417346 at 1dc67ac failed before workload submission: immediate
`docker exec /dogstatsd version` returned exit 126 (permission denied). The fixed
image entrypoint performs chmod and sync before launching DogStatsD, so invoking
the binary immediately after `docker run -d` raced that initialization. Version
inspection was moved after both the real health and UDP socket readiness checks.
Command failures now include bounded stdout/stderr in the CI assertion message;
the original command logs and empty intake output are retained locally under
.local/evidence/agent-ci-second. This was a test-driver startup race, not evidence
of a MoonBit encoding or send failure.

## Official Agent and platform completion

Run https://github.com/Ryan-1125/moonstatsd/actions/runs/39542103570 at a547b5b
completed successfully on both Windows and Ubuntu. Actual Ubuntu job 119031942897:

```
Total tests: 20, passed: 20, failed: 0.
Total tests: 6, passed: 6, failed: 0.
Official Agent health and UDP listener ready; version verified
Official DogStatsD Agent 7.60.0: sampled count=4, gauge=7, timer.avg=250ms, histogram.avg=42, set=2; tags verified
datadog-go v5.8.3: 6 wire cases semantically equal (timer decimal formatting normalized)
Independent published-ZIP consumer: codec and real UDP passed
Actual ZIP audit passed: 39 entries, no private/build artifacts.
```

The official binary reports commit 799e298, serialization v5.0.134, Go 1.22.8.
Downloaded output assertions show:

| Actual Agent metric | Type / interval | Point value |
|---|---|---|
| moonagent.count | rate / 10s | 0.4 (estimated count 4) |
| moonagent.queue | gauge / 10s | 7 |
| moonagent.timer.avg | gauge / 10s | 250 (input ms retained) |
| moonagent.payload.avg | gauge / 10s | 42 |
| moonagent.unique | gauge / 10s | 2 |

All five series include env:test, service:demo and route:home. Real outputs,
version, container socket table, image metadata, request sizes and command logs
were downloaded to .local/evidence/agent-ci-passed. Distribution sketches are
explicitly disabled/not asserted, and the remote commercial backend is not used.
The local HTTP sink only accepts forwarded Agent output, not StatsD input.

Git HTTPS connections reset repeatedly during this round. Two existing commits
were uploaded through official Git Data API with exact blob/tree/commit SHA
checks before a non-forced ref update. The local and remote a547b5b match exactly;
author, timestamps and parent history were not rewritten. No credentials were
written to files or logs. The operations helper itself remains ignored in .local.

STATUS.md was added after the 39-entry CI artifact above; the final local package
contains 40 entries. No package registry publication or hackathon submission was
performed in this round.

## 2026-10-21：发布文档与 Mooncakes 消费验收

发布依据：用户终端 `moon publish` 返回 `Server status: 200 OK`；本轮从 registry 解析 `Ryan-1125/moonstatsd@0.1.0`，不使用 path 依赖或 moon.work 源码覆盖。

命令：`./tools/test-registry-consumer.ps1`。

```text
Registry index updated successfully
Symbols updated successfully
Registry 0.1.0 consumer: codec, packing and real DogStatsD UDP passed
```

独立应用断言纯核心编码、pack 结果，以及带固定和调用级标签的三条指标在真实 UDP 接收端的完整字节；同时检查 submitted=3、send_errors=0。源文件保留在 `.local/registry-consumer-*`，运行日志为 `.local/evidence/registry-consumer.log`。

本轮首次运行因受限环境不能写 registry 更新锁而失败；允许写依赖缓存及联网后重跑成功。现有 native 测试在受限网络环境首次为 16/20（四项 UDP TimeoutError），允许本机 UDP 后同一代码重跑为：

```text
moon test --target native
Total tests: 20, passed: 20, failed: 0.
moon test --target wasm-gc --package Ryan-1125/moonstatsd
Total tests: 6, passed: 6, failed: 0.
```

本次整理发布后的 README、使用约定、状态与版本记录；历史“未发布”描述保留在本文件早期记录中，仅反映当时状态。

README 的两个 MoonBit 示例已原样提取至上述 registry 消费项目的独立包：最初纯核心示例缺少 `fn main raise`，编译检查发现后已修正。最终 `moon check --target native` 通过；纯核心示例运行断言通过；UDP 示例运行输出：

```text
local submitted=3, send errors=0
```

此 UDP 示例输出是本机发送结果；接收字节断言由前述 registry UDP 测试独立覆盖。README、使用约定和状态文档的本地链接检查，以及 `git diff --check` 均通过。`moon info --target native` 与 `moon fmt` 通过，公开 `.mbti` 接口无变化。

最终包审计发现 `shenbao.md` 未被原 `.moonignore` 排除；首次审计只检查通用私有目录，未识别该文件。补充 `.gitignore`、`.moonignore` 规则及审计断言后，重新打包结果为：

```text
Actual ZIP audit passed: 42 entries, no private/build artifacts.
```

registry 下载的既有 0.1.0 中仍有该文件；本地排除规则不修改已经发布的版本。本轮没有替换或删除线上版本。

## 2026-10-21：README 示例自动验收

新增 `tools/test-readme.ps1`：从 README 原样提取两组 `moon.pkg` / `main.mbt`，创建无 workspace 覆盖的独立 registry 消费应用，以 deny-warn 检查并运行。Windows/Ubuntu CI 增加 registry 消费与该示例校验步骤。

本轮 `moon update` 两次因 Mooncakes 443 连接失败而停止，未将其计为通过。随后显式运行 `./tools/test-readme.ps1 -SkipUpdate`，使用此前从 registry 下载的依赖缓存（不替换为本地源码），结果：

```text
Using cached moonbitlang/async@0.20.0
Using cached Ryan-1125/moonstatsd@0.1.0
Finished. moon: ran 21 tasks, now up to date
local submitted=3, send errors=0
README examples passed: published dependency, exact source, compile and run (UDP output is local submission only).
```

`-SkipUpdate` 只跳过索引刷新，默认 CI 仍执行线上索引检查。完整本地日志：`.local/evidence/readme-examples-cached.log`；线上失败日志：`.local/evidence/readme-examples.log`。

## 2026-10-21：发布工具随模块版本自动定位 ZIP

`tools/module-metadata.ps1` 读取 moon.mod 的模块名和语义版本，供包审计与 ZIP 独立消费共同使用，消除写死的 0.1.0 归档及消费依赖。缺失或非字面量元数据会显式报错。Registry 和 README 验证仍固定为实际已发布的 0.1.0，避免把未发布版本当作线上包。

实测 `./tools/test-consumer.ps1 -SkipUpdate`（缓存模式）：

```text
Independent published-ZIP consumer: codec and real UDP passed
```

在实际 ZIP 的隔离解压副本中只将版本改为 0.1.1，执行其包审计脚本：

```text
Package to .../Ryan-1125-moonstatsd-0.1.1.zip
Actual ZIP audit passed: 44 entries, no private/build artifacts.
```

最初副本位于 .local 下，父目录忽略规则导致归档为空，审计正确拒绝缺失源码；临时移至工作区非隐藏目录后真实生成并审计 0.1.1 包，完成后移回 .local。主项目版本仍为 0.1.0，没有发布新版本。日志：`.local/evidence/version-consumer.log`、`.local/evidence/version-next-package.log`。

最终回归：`moon info --target native`、`moon fmt`、`git diff --check` 通过，公开接口无变化；native 20/20、纯核心 wasm-gc 6/6；主项目实际 0.1.0 ZIP 审计通过，44 个条目。两项新增脚本和验证记录均进入包，个人申报材料继续排除。
