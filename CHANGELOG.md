# Changelog

## 0.1.0 — local development, 2026-10-21

- Add native MoonBit StatsD/DogStatsD codec with explicit gauge delta and safe rejection of negative absolute gauges.
- Add finite-number, sampling, field-injection, duplicate-tag and UTF-8 byte validation.
- Add indivisible message packing with per-datagram and aggregate limits.
- Add bounded structured async UDP client with local statistics and flush/close barriers.
- Add real UDP/cancellation/error tests, two fixed real collector integrations, reference-client wire comparison and independent ZIP consumption.
- Add CI definition and subsequent real Windows/Ubuntu run evidence (snapshot details in docs/VALIDATION.md). Registry remains unpublished; no benchmark claim.

### Follow-up hardening

- Preserve the most recent local send failure in Stats.last_send_error.
- Explain InvalidConfig rejections and reject destination UDP port zero before socket creation.
- Normalize repository checkout line endings; repaired Windows CI format checking.
- Create and upload the authorized private GitHub repository; preserve exact per-commit CI evidence.
