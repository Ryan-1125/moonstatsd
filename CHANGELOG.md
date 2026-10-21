# Changelog

## 0.1.0 — 2026-10-21

- Add native MoonBit StatsD/DogStatsD codec with explicit gauge delta and safe rejection of negative absolute gauges.
- Add finite-number, sampling, field-injection, duplicate-tag and UTF-8 byte validation.
- Add indivisible message packing with per-datagram and aggregate limits.
- Add bounded structured async UDP client with local statistics and flush/close barriers.
- Add real UDP/cancellation/error tests, two fixed real collector integrations, reference-client wire comparison and independent ZIP consumption.
- Publish Ryan-1125/moonstatsd 0.1.0 to Mooncakes.
- Verify registry consumption in an independent application: encoding, packing and real DogStatsD UDP reception.
- Add CI definition and real Windows/Ubuntu run evidence (snapshot details in docs/VALIDATION.md).

### Follow-up hardening

- Preserve the most recent local send failure in Stats.last_send_error.
- Explain InvalidConfig rejections and reject destination UDP port zero before socket creation.
- Normalize repository checkout line endings; repaired Windows CI format checking.
- Create and upload the GitHub repository, then make it public after user selection; preserve exact per-commit CI evidence.

### Concurrency and official-Agent validation work

- Add real UDP regression for flush snapshot isolation from later admissions,
  close racing an active producer, and fixed/per-call tag mutation isolation.
- Add a digest-pinned official DogStatsD 7.60.0 Docker test with a bounded local
  HTTP output sink, internal network, dummy key and exact aggregate/tag assertions.
- Keep Agent execution on Linux CI; Windows has no Docker runtime in the local
  environment. Actual Ubuntu run a547b5b passed the official Agent aggregate/tag assertions.
- Add docs/STATUS.md as a compact current summary alongside historical logs.
- Validate fixed configuration against actual packet budget before copying tags; reject unusable prefix/tag overhead at construction.
- Native regressions: 20/20; pure wasm-gc core: 6/6; Windows and Ubuntu CI passed at a547b5b.
