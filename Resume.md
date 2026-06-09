# zig-crypto — Project Summary

## What it is

A zero-allocation, N-API-stable Node.js native addon for high-performance ID generation — nanoid (URL-safe random strings) and Snowflake (distributed 64-bit integers) — written in Zig with prebuilt binaries for Linux, macOS, and Windows.

---

## Achievements

### Performance

- **Nanoid single ID (21 chars):** 179 ns/op in Node.js (2.6× faster than npm nanoid), 632 ns/op in Bun (1.7× faster than npm nanoid).
- **Batch nanoid (500 IDs):** 54.7 µs in Bun — 2.9× faster than npm nanoid loop, fixed from a 12× regression caused by `Buffer.toString()` overhead.
- **BatchBuffer (100 IDs, zero-copy):** 7.3 µs in Node.js — 3.7× faster than npm nanoid loop.
- **Snowflake batch (1000 IDs):** 67 µs in Bun — 3× faster than Bun's native `randomUUIDv7()`.
- Single N-API boundary crossing for batch operations of any size.
- 64KB threadlocal CSPRNG pool amortizes syscall overhead to zero per ID.

### Architecture

- **Native string array batch:** Replaced Buffer + N× `toString()` with a single N-API function that creates JS strings directly via `napi_create_string_utf8` — eliminating JS-level UTF-8 decoder overhead.
- **Stack buffer allocation:** Single IDs use a fixed 128-byte stack buffer — zero heap allocation, zero GC pressure.
- **8-byte stride unrolling:** `inline fn` with `inline while (j < 8)` eliminates 87.5% of loop branches vs byte-at-a-time approaches.
- **Comptime LOOKUP table:** 256-entry alphabet mapping table generated at compile time — zero runtime computation per byte.
- **TigerBeetle-inspired pattern:** Systems-level Zig core wrapped by a thin N-API C ABI, shipped as prebuilt binaries.

### Engineering

- **N-API v6+ (C ABI):** ABI-stable across Node.js 16→24+, no recompilation needed — unlike C++ wrappers (`node-addon-api`) that break on V8 changes.
- **5 native exports:** `Id()`, `Batch()` (Snowflake), `nanoid()`, `nanoidBatchStrings()`, `nanoidBatchBuffer()` (zero-copy).
- **Cross-platform:** Prebuilt binaries for linux-x64, linux-arm64, darwin-x64, darwin-arm64, win32-x64 — `npm install` in < 3s, no `node-gyp` on user machines.
- **CSPRNG:** OS-native entropy via `getrandom()` (Linux), `arc4random_buf()` (macOS), `BCryptGenRandom()` (Windows).
- **450+ tests:** 209 JavaScript tests + 241 Zig tests, all passing.
- **Zero npm dependencies at runtime** (only `node-gyp-build` for binary loading).
