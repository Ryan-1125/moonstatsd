# Changelog

## 0.1.0 — local development, 2026-10-21

- Add native MoonBit StatsD/DogStatsD codec with explicit gauge delta and safe rejection of negative absolute gauges.
- Add finite-number, sampling, field-injection, duplicate-tag and UTF-8 byte validation.
- Add indivisible message packing with per-datagram and aggregate limits.
- Add bounded structured async UDP client with local statistics and flush/close barriers.
- Add real UDP/cancellation/error tests, two fixed real collector integrations, reference-client wire comparison and independent ZIP consumption.
- Add CI definition. No remote CI execution, registry publication or benchmark claim.
