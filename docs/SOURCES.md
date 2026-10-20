# Sources and scope (2026-10-20)

The supplied handoff is a design, not implemented API. Work began in an empty
D:/GitHub/MoonStatsD; no original files or Git history existed. `moon new` generated
AGENTS.md, read before implementation. No MoonFCGI files were modified.

Registry index refreshed successfully with `moon add moonbitlang/async@0.20.0`.
`rg -i -l 'statsd|dogstatsd' C:/Users/Lenovo/.moon/registry/index` returned no matches.
Broader metrics/telemetry/monitoring search returned related observability, Prometheus,
OpenTelemetry and unrelated font metrics packages. This is a limited index search,
not evidence that the ecosystem has no competing library. Related API review remains
open; no claim of unique ecosystem coverage is made.

Fixed sources read before implementation:
- statsd/statsd v0.9.0 docs/metric_types.md and LICENSE (MIT).
  https://github.com/statsd/statsd/blob/v0.9.0/docs/metric_types.md
- DataDog/datadog-go v5.8.3 statsd/format.go and LICENSE.txt (MIT).
  https://github.com/DataDog/datadog-go/blob/v5.8.3/statsd/format.go
- moonbitlang/async 0.20.0 installed source, generated interfaces and LICENSE
  (Apache-2.0). src/socket/udp.mbt, task_group.mbt, cond_var/cond_var.mbt.

These are protocol/behavior references; no reference implementation code or test
fixtures have been copied into the library. Project license: Apache-2.0 (template).
DogStatsD grammar uses the fixed reference client's c/g/ms/s/h/d and rate/tags;
this is not a complete Datadog SDK or a claim of full Agent compatibility.
Negative absolute gauges are explicitly rejected in both modes. StatsD v0.9.0
requires zero then negative delta; splitting those into independent updates creates
race/delivery hazards. Explicit GaugeDelta remains available.

SDK observed: moon 0.1.20261020 (2284bd2), moonc v0.10.16+b1a0e846e.
Native Windows minimum check/build succeeded. Initial generated template had zero tests.
Core tests subsequently: `moon test --target native`: Total tests: 4, passed: 4,
failed: 0. Includes fixed wire vectors, rejection cases, UTF-8 packet bounds and
sampling thresholds. Compiler deprecation warnings are being cleaned up.

UDP API verified: UdpClient(Addr), send(Bytes), close(); server supports ephemeral
port binding and recvfrom(FixedArray[Byte]). TaskGroup.spawn + Task.cancel/wait,
Cond.wait/broadcast, sleep, with_timeout, protect_from_cancel exist in 0.20.0.
No TCP-to-UDP interface inference is used.

Default datagram limit 512 follows the conservative Internet guidance in fixed
StatsD metric_types.md; no setting can guarantee path MTU or delivery. Configurable
up to IPv4 UDP payload ceiling 65507; operators must choose receiver/network limits.
