# Phase 1 — Zig Core Base64

**Goal:** `zig build test` passes for base64 encode/decode.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Comptime encode/decode lookup tables + alphabet validation | `src/codec/tables.zig` | Pending |
| 2 | Scaffold `base64.zig` with function stubs, register in `build.zig` | `src/codec/base64.zig` | Pending |
| 3 | Scalar base64 encode (standard + URL-safe) | `src/codec/base64.zig` | Pending |
| 4 | Scalar base64 decode (standard + URL-safe) | `src/codec/base64.zig` | Pending |
| 5 | SIMD encode (12→16 byte chunks via `@Vector`) | `src/codec/base64.zig` | Pending |
| 6 | SIMD decode (16→12 byte chunks via `@Vector`) | `src/codec/base64.zig` | Pending |
| 7 | Zig unit tests: roundtrip, padding, alphabets, invalid input | `src/codec/base64.zig` | Pending |
| 8 | Edge cases: padding, invalid chars, leftovers, overflow | `src/codec/base64.zig` | Pending |

---

# Phase 2 — N-API Integration (future)

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Add `Base64EncodeNapi` / `Base64DecodeNapi` to `root.zig` | `src/root.zig` | Pending |
| 2 | Options parsing (`{ urlSafe: true }`) | `src/root.zig` | Pending |
| 3 | JS wrapper: `codec.base64.encode/decode` | `index.ts` | Pending |
| 4 | TypeScript definitions | `index.d.ts` | Pending |
| 5 | Smoke tests: roundtrip, urlSafe, invalid input | `test/` | Pending |

---

# Phase 3 — Constant-Time Security (future)

| # | Task | File | Status |
|---|------|------|--------|
| 1 | `decodeConstantTime(input, output)` — no timing side channels | `src/codec/base64.zig` | Pending |
| 2 | N-API constant-time export | `src/root.zig` | Pending |
| 3 | Security docs in README | `README.md` | Pending |

---

# Phase 4 — Benchmark & Ship (future)

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Benchmark suite vs Node Buffer.toString | `bench/codec-bench.js` | Pending |
| 2 | GC pressure test | `bench/gc-profile.js` | Pending |
| 3 | CI integration | `.github/workflows/release.yml` | Pending |
| 4 | npm publish v2.0.0 | — | Pending |
