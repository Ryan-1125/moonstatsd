# Sources and scope (2026-10-20)

The supplied handoff is a design, not implemented API. Work began in an empty
D:/GitHub/MoonStatsD; no original files or Git history existed. `moon new` generated
AGENTS.md, read before implementation. No MoonFCGI files were modified.

Registry index refreshed successfully with `moon add moonbitlang/async@0.20.0`.
`rg -i -l 'statsd|dogstatsd' C:/Users/Lenovo/.moon/registry/index` returned no matches.
Broader metrics/telemetry/monitoring search returned related observability, Prometheus,
OpenTelemetry and unrelated font metrics packages. This is a limited index search,
not evidence that the ecosystem has no competing library. Related API review is
recorded below; no claim of unique ecosystem coverage is made.

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

## Final audit additions (2026-10-21)

Official DogStatsD protocol documentation was read at fixed DataDog/documentation
commit `41384078b8ba37e2cd12e825584ffa8cd66703f7`,
`content/en/developers/dogstatsd/datagram_shell.md` (BSD-3-Clause documentation
license). The old URL had moved; the GitHub rename commit was inspected and its
parent selected, rather than treating a failed fetch as having read the document.
https://github.com/DataDog/documentation/blob/41384078b8ba37e2cd12e825584ffa8cd66703f7/content/en/developers/dogstatsd/datagram_shell.md
This audit tightened DogStatsD names to ASCII alphanumerics/underscore/period.
Relative gauge updates were restricted to StatsD mode: exporter behavior alone is
not proof of Datadog Agent relative gauge semantics. DogStatsD example now uses
absolute nonnegative snapshots; the separate actual StatsD test covers deltas.
Zero rate, negative absolute gauge, and unsupported protocol extensions remain
explicitly rejected subsets of the wider protocol.

Related package review in an isolated .local/research module:
- guiqi695/moon-prometheus-sdk@0.1.0: inspected generated root/metric/http APIs.
  Counter/Gauge registry plus encode_registry/handle_metrics expose Prometheus /
  OpenMetrics text, not this project's StatsD wire and UDP lifecycle.
- 668xin/moonbit-observe@0.1.0: inspected README and src/lib public definitions.
  Stopwatch, AsyncTimer, snapshots, console/JSON reporting are locally useful
  timer/observation components; no full StatsD/DogStatsD UDP client was found in
  these reviewed surfaces. No implementation from either package was copied.
- ryota0624/moonbit_otel@0.1.0: index describes OTEL with protobuf and async
  dependencies. Download resolution failed on its mizchi/x@0.1.3 old moon.mod.json
  format, so this package's implementation was not fully audited. Product
  dependencies were not altered to bypass this research limitation.
The first two reviews support a distinct protocol-client scope; they do not prove
absence of all competitors. Broad index terms used: statsd, dogstatsd, metrics,
telemetry, monitoring; web exact StatsD/DogStatsD Mooncakes searches returned no
results during this session. Index and web coverage are incomplete by nature.

statsd_exporter v0.28.0 README and Apache-2.0 LICENSE were read, and official
Windows amd64 ZIP SHA256 was matched against the release checksum file:
`2270601d87b78200e485731755c3d99f0aa7c68da92801e56bbfe031ad81e257`.
The actual receiver binary reports revision c0a390a2c43f77863278615b47d46e886bdca726.
StatsD v0.9.0 source archive SHA256:
`e30a298c5a3d99bf5dc6a2ff69aadcd4df188b5eae2deb4dfb391f3e183517ff`.
Download installer preserves both upstream license files locally. No binaries or
third-party source archives are included in the Moon package.

Actual datadog-go v5.8.3 differential was subsequently run (Go 1.23.2). Six common
wire cases agree after numeric normalization of Timer 12.500000 vs 12.5. The first
proxy.golang.org download timed out; a process-local GOPROXY=https://goproxy.cn
retry completed with Go checksum validation. No global Go settings were changed.

## Official DogStatsD test setup (verification initially pending)

Added an Ubuntu-only Docker integration using official datadog/dogstatsd 7.60.0,
Linux amd64 digest
sha256:e4cbd4b82011b3dec10d7598e51d766e5a4ba9d4fe372f54197daeccb27529ee.
Digest was obtained from Docker Hub tag metadata. Fixed Agent source README,
Dockerfile, entrypoint, probe, configuration setup and serializer were inspected.
Apache-2.0 LICENSE was checked. Configuration uses the actual `use_v2_api.series`
key via DD_USE_V2_API_SERIES=false, not a guessed serializer option.

The official parser/aggregator/forwarder runs in an internal Docker network;
its output goes to a bounded local HTTP sink using a deliberately dummy API key.
The sink decodes Agent output JSON only and never parses input StatsD packets.
Assertions target sampled counts (accounting for the Agent rate interval), gauge,
Timer/Histogram averages, Set uniqueness and tags. Distribution sketches are not
claimed by this test; their existing exporter/wire verification remains separate.

Local Windows cannot execute this integration: Docker is absent and WSL has no
Linux distribution. The Agent workload compiles, the Node script parses, and CI
will supply the real Linux runtime. Until an actual successful job is observed,
this setup is not evidence that Agent interoperability passed.
