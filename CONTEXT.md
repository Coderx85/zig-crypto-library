# zig-id — CONTEXT.md

> **Single source of truth for the `zig-id` project.**
> This document is append-only. When something changes, add a dated entry. Do not delete history.

---

## 1. Project Identity

| Field              | Value                                               |
| ------------------ | --------------------------------------------------- |
| **Name**           | `zig-id`                                            |
| **Version**        | `1.0.0` (target)                                    |
| **License**        | MIT                                                 |
| **Registry**       | `npm`                                               |
| **Repository**     | `github.com/<user>/zig-id`                          |
| **Language**       | Zig (core) + TypeScript (wrapper)                   |
| **Runtime Target** | Node.js 16+ (N-API v6+)                             |
| **Platforms**      | Linux (x64/ARM64), macOS (x64/ARM64), Windows (x64) |

### One-Sentence Pitch

> A zero-allocation, N-ABI-stable Node.js native extension for high-performance ID generation, written in Zig, shipping prebuilt binaries for all desktop platforms.

### Three-Sentence Expansion

Node.js is excellent for I/O but punishes CPU-bound string and integer manipulation. `zig-id` extends the Node.js runtime with a Zig-native layer for deterministic, zero-allocation ID operations. It provides cryptographically secure nanoid strings and distributed Snowflake 64-bit integers without V8 GC pressure or cross-boundary allocation overhead.

---

## 2. Why This Project Exists

### The Problem

- **nanoid** (pure JS) allocates a new string per ID. At 10k IDs/sec, V8 GC stalls the event loop.
- **Snowflake** requires 64-bit integer math that JavaScript `number` cannot represent safely past `2^53`.
- Existing native addons use `node-gyp`, `nan`, or C++ — breaking on every Node major version and requiring Python/Visual Studio on user machines.
- No existing package combines **both** random-string and time-ordered-integer IDs in one N-API-native module.

### The TigerBeetle Inspiration

TigerBeetle writes one Zig core (`tb_client`) and wraps it for every language via FFI/N-API. Their insight: **write the hard stuff once in a systems language, expose a thin C ABI, ship prebuilt binaries.** We apply the same pattern to ID generation.

### Success Criteria

1. `npm install zig-id` works on all 5 target platforms without `node-gyp` or compilation.
2. `nanoid()` returns a valid 21-char string in < 1µs (single call).
3. `snowflake()` returns a valid `bigint` with extractable timestamp.
4. Batch generation (Phase 3) crosses the JS↔native boundary **once** for 1000 IDs.
5. Binary size < 500KB per platform.

---

## 3. Architecture

### Layer Cake

```
┌──────────────────────────────────────────┐
│  index.ts / index.d.ts                   │  ← TypeScript API, user-facing
│  (node-gyp-build loader)                 │
├──────────────────────────────────────────┤
│  N-API C ABI Boundary                    │  ← Exports, type marshalling
│  src/napi.zig  (5 exports)               │
├──────────────────────────────────────────┤
│  Zig Core Engine                         │  ← Zero-allocation logic
│  src/internal/nanoid.zig                 │
│  src/internal/snowflake.zig              │
├──────────────────────────────────────────┤
│  N-API Helpers                           │  ← Reusable error/string/BigInt
│  src/translate.zig                       │
├──────────────────────────────────────────┤
│  Module root (stub)                      │
│  src/root.zig                            │
└──────────────────────────────────────────┘
```

### Data Flow: Batch nanoid (strings)

```
JS: nanoid.Batch(500, 21)
  │
  ▼
N-API: napi_get_cb_info → parse count (int32), length (int32)
  │
  ▼
Zig: for 0..500:
  ├─→ buf[0..21] = nanoid.generate(len)  (stack buffer)
  ├─→ napi_create_string_utf8(buf, 21)   (copy to V8)
  └─→ napi_set_element(array, i, str)
  │
  ▼
JS: receives ["V1StGXR8_Z5jdHi6B-myT", ...] (Array<string>, 1 crossing)
```

No heap allocation. No finalizer. No Buffer.toString().
500 individual `napi_create_string_utf8` calls create V8 strings directly — avoids JS-level UTF-8 decoder overhead that plagues Bun.

### Data Flow: Single nanoid

```
JS: nanoid(21)
  │
  ▼
N-API: napi_get_cb_info → parse length (int32)
  │
  ▼
Zig: var buf: [MAX_LENGTH]u8 = undefined;  (stack)
  │
  ▼
Zig: nanoid.generate(buf[0..21])
  ├─→ read 21 bytes from CPU-local CSPRNG pool
  │   (threadlocal 64KB pool, refilled via getrandom())
  ├─→ writeLookup: map each byte via LOOKUP[byte]
  │   (comptime-generated 256-entry table, 8-byte stride unrolled)
  └─→ (no allocator — pool + stack only)
  │
  ▼
N-API: napi_create_string_utf8(buf, 21)  (copy to V8)
  │
  ▼
JS: receives "V1StGXR8_Z5jdHi6B-myT"
```

### Data Flow: Snowflake

```
JS: Snowflake.Id()
  │
  ▼
N-API: napi_get_cb_info → no args
  │
  ▼
Zig: snowflake_state.generate()
  ├─→ std.time.milliTimestamp()
  ├─→ auto nodeId from hostname hash (Wyhash, cached)
  ├─→ bit pack: (timestamp - EPOCH) << 22 | nodeId << 12 | sequence
  ├─→ mutex protects last_timestamp / sequence for thread safety
  └─→ return u64
  │
  ▼
N-API: napi_create_bigint_uint64(id)
  │
  ▼
JS: receives 1577836800000000001n (BigInt)
```

### Memory Ownership Rules

| Memory                         | Owner                | Lifetime                    | Free Point                                                   |
| ------------------------------ | -------------------- | --------------------------- | ------------------------------------------------------------ |
| nanoid single `[MAX_LENGTH]u8` | Stack (caller)       | Function call               | Never allocated (napi_create_string_utf8 copies)             |
| Snowflake `u64`                | Stack value          | Function call               | Never allocated (returned by value)                          |
| Batch buffer slab              | page_allocator heap  | Until JS GC collects Buffer | Finalizer callback (`batchBufferFinalizer`)                  |
| Batch strings array            | Stack buffers per ID | Function call               | Never allocated (napi_create_string_utf8 copies per element) |
| JS String/BigInt               | V8 heap              | Until JS GC collects        | N/A (V8 manages)                                             |

**Golden Rule:** Heap-allocated Zig memory passed to JS via `napi_create_external_*` **must** have a finalizer. Stack or function-local memory **must never** be passed as external.

---

## 4. Design Decisions

### Decision: N-API (C ABI) over node-addon-api (C++)

- **Status:** Accepted
- **Rationale:** N-API guarantees ABI stability across Node versions. C++ wrappers (`node-addon-api`) require recompilation when V8 changes. We want "compile once, run forever."
- **Consequence:** We write more boilerplate (manual `napi_property_descriptor` arrays), but gain zero maintenance across Node 16→22+.

### Decision: 64-Character Alphabet for nanoid

- **Status:** Accepted
- **Rationale:** $64 = 2^6$. A random byte `& 0x3F` (bit mask) maps exactly to the alphabet with **zero modulo bias** and zero branching. No rejection sampling needed.
- **Consequence:** Alphabet is fixed at 64 URL-safe chars. Custom alphabets (e.g., base58) will require rejection sampling or multiplication method (Phase 3+).

### Decision: Stack Buffer + CSPRNG Pool (no allocator for single IDs)

- **Status:** Accepted
- **Rationale:** `generate()` uses a fixed `[MAX_LENGTH]u8` stack buffer (128 bytes) and a 64KB threadlocal CSPRNG pool. No heap allocation per ID. Stack allocation is zero-overhead — the buffer is always on the caller's frame. `generateBuffer()` (batch) takes an allocator because the slab size is unbounded (up to 1000 × 128 = 128KB).
- **Consequence:** Single ID generation has zero GC pressure and no allocator overhead. Batch generation uses `page_allocator` directly.

### Decision: Snowflake Mutex (Not Lock-Free)

- **Status:** Accepted for v1.0
- **Rationale:** Node.js Worker Threads can call `snowflake()` concurrently. A single `std.Thread.Mutex` protects `last_timestamp` and `sequence`. Lock-free atomics are possible but complex; correctness first.
- **Consequence:** Peak single-node throughput is ~4096 IDs/ms (12-bit sequence limit). For higher throughput, users should shard by `nodeId` across Workers.

### Decision: No Batch in v1.0 Core

- **Status:** Deferred to Phase 3
- **Rationale:** v1.0 proves the N-API pipeline end-to-end. Batch generation adds external ArrayBuffer complexity (finalizers, JS slicing). Ship the simple case first.
- **Consequence:** `nanoidBatch` and `snowflakeBatch` are documented in `index.d.ts` but marked as `@deprecated until v1.1` or omitted entirely until implemented.

### Decision: Native String Array Batch over Buffer.toString()

- **Status:** Accepted
- **Rationale:** Original `nanoid.Batch()` created an external Buffer via `nanoidBatchBuffer` then called `buf.toString()` N times in JS. This was 12× slower than pure-JS nanoid in Bun because `Buffer.toString()` in JavaScriptCore has high JS-level UTF-8 decoder overhead. Replaced with a single native function that creates JS strings directly via `napi_create_string_utf8` and returns a JS array. One boundary crossing, zero Buffer.toString() calls.
- **Consequence:** Batch strings are created in C with `napi_create_string_utf8` (V8/JS engine primitives) instead of JS UTF-8 decoding. The `Buffer` path (`nanoidBatchBuffer`) is retained for zero-copy use cases but is no longer the default Batch path.

### Decision: `node-gyp-build` over `prebuildify` CLI

- **Status:** Accepted
- **Rationale:** `node-gyp-build` is a 20-line runtime loader with zero configuration. `prebuildify` is a build-time tool that requires careful integration. We use `prebuildify` in CI to generate binaries, but `node-gyp-build` at runtime to load them.
- **Consequence:** `package.json` has a runtime dependency on `node-gyp-build` (~5KB).

---

## 5. File Inventory

| File                            | Purpose                                                                           | Stability |
| ------------------------------- | --------------------------------------------------------------------------------- | --------- |
| `build.zig`                     | Shared library target, cross-compilation, strip symbols                           | Stable    |
| `src/root.zig`                  | Module root (stub, re-exports `internal/snowflake.zig`)                           | Stable    |
| `src/napi.zig`                  | N-API layer: 5 exports (Id, Batch, nanoid, nanoidBatchBuffer, nanoidBatchStrings) | Stable    |
| `src/nanoid.zig`                | Core nanoid: CSPRNG, alphabet mapping, batch                                      | Stable    |
| `src/snowflake.zig`             | Core Snowflake: bit packing, timestamp, mutex                                     | Stable    |
| `index.js`                      | JS loader: `node-gyp-build` + re-exports                                          | Stable    |
| `index.d.ts`                    | TypeScript declarations                                                           | Stable    |
| `package.json`                  | npm manifest, `files` whitelist, dependencies                                     | Stable    |
| `.github/workflows/release.yml` | Matrix CI: 5 targets + publish                                                    | Stable    |
| `test/test.js`                  | Smoke tests: types, uniqueness, timestamp                                         | Evolving  |
| `README.md`                     | User-facing documentation                                                         | Evolving  |

---

## 6. Build System Reference

### Local Development

```bash
# Install N-API headers
npm install

# Build for current machine (debug)
zig build -Dnapi-include=node_modules/node-api-headers/include

# Build for current machine (release, stripped)
zig build -Doptimize=ReleaseSmall -Dnapi-include=node_modules/node-api-headers/include

# Copy binary to prebuilds/ for local testing
mkdir -p prebuilds/$(node -e "console.log(process.platform+'-'+process.arch)")
cp zig-out/lib/libzig_id.* prebuilds/*/zig-id.node  # Unix
cp zig-out/bin/zig_id.dll prebuilds/*/zig-id.node    # Windows

# Test
npm test
```

### Cross-Compilation Matrix

| Target      | Command                                 | Output            |
| ----------- | --------------------------------------- | ----------------- |
| Linux x64   | `zig build -Dtarget=x86_64-linux-gnu`   | `libzig_id.so`    |
| Linux ARM64 | `zig build -Dtarget=aarch64-linux-gnu`  | `libzig_id.so`    |
| macOS x64   | `zig build -Dtarget=x86_64-macos`       | `libzig_id.dylib` |
| macOS ARM64 | `zig build -Dtarget=aarch64-macos`      | `libzig_id.dylib` |
| Windows x64 | `zig build -Dtarget=x86_64-windows-gnu` | `zig_id.dll`      |

### CI Artifact Naming

Each binary is renamed to `zig-id.node` and placed in:

```
prebuilds/
├── linux-x64/
│   └── zig-id.node
├── linux-arm64/
│   └── zig-id.node
├── darwin-x64/
│   └── zig-id.node
├── darwin-arm64/
│   └── zig-id.node
└── win32-x64/
    └── zig-id.node
```

---

## 7. N-API Type Mapping

| JS Type           | N-API Function                 | Zig Type | Used For                    |
| ----------------- | ------------------------------ | -------- | --------------------------- |
| `number` (int32)  | `napi_get_value_int32`         | `i32`    | nanoid length, nodeId       |
| `string`          | `napi_create_string_utf8`      | `[]u8`   | nanoid result               |
| `bigint`          | `napi_create_bigint_uint64`    | `u64`    | Snowflake result            |
| `bigint`          | `napi_get_value_bigint_uint64` | `u64`    | extractSnowflakeTime input  |
| `number` (double) | `napi_create_double`           | `f64`    | extractSnowflakeTime result |
| `object`          | `napi_get_named_property`      | —        | Snowflake options           |
| `undefined`       | `napi_get_undefined`           | —        | Default args                |

---

## 8. Security Considerations

### CSPRNG Source

- 64KB threadlocal pool refilled via OS entropy (amortizes syscall cost).
- **Linux:** `getrandom()` syscall (blocks until entropy pool initialized, then non-blocking).
- **macOS:** `arc4random_buf()` (never blocks, cryptographically secure).
- **Windows:** `BCryptGenRandom()` (CNG API, FIPS 140-2 compliant when available).
- **Pool refill:** `inline fn refillPool()` at pool exhaustion; `fillRandom()` switches on `builtin.os.tag` at comptime.

### Side-Channel Resistance

- Current: Not constant-time. Alphabet mapping (`byte & 0x3F`) is data-independent, but memory access pattern (`ALPHABET[idx]`) could theoretically leak via cache timing. **Not a concern for ID generation** (no secret key material).
- Future (zig-codec): Constant-time base64 decode for JWT/session tokens.

### Input Validation

- `nanoid(length)`: Range-checked `1..128`. Rejects `0`, negative, and >128.
- `Snowflake.Id()`: Auto-derives nodeId from hostname hash (Wyhash, cached). No user-facing parameter.
- All invalid inputs throw JS `TypeError` or `RangeError` before touching Zig core.

---

## 9. Performance Budget

| Operation                                    | Target   | Current | Notes                                                   |
| -------------------------------------------- | -------- | ------- | ------------------------------------------------------- |
| `nanoid()` single                            | < 1 µs   | TBD     | Measured with `benchmark.js`                            |
| `snowflake()` single                         | < 0.5 µs | TBD     | Mostly bit ops + mutex lock                             |
| `nanoidBatch(1000)` boundary crossings       | 1        | 1 ✓     | `nanoidBatchStrings` creates native strings, 1 crossing |
| `nanoidBatchBuffer(1000)` boundary crossings | 1        | 1 ✓     | Zero-copy Buffer path, 1 crossing + finalizer           |
| Binary size (per platform)                   | < 500 KB | TBD     | `ReleaseSmall` + strip                                  |
| `npm install` time                           | < 3 sec  | —       | Prebuilt, no compile                                    |

---

## 10. Roadmap

### v1.0.0 (Current — Ship First)

- [x] `nanoid(length?)` → string
- [x] `Snowflake.Id()` → bigint (auto nodeId from hostname hash)
- [x] `extractSnowflakeTime(bigint)` → number
- [x] N-API module registration
- [x] Cross-compilation CI (5 targets)
- [x] TypeScript definitions
- [x] npm publish with prebuilds

### v1.1.0 (Batch Generation — Phase 3)

- [x] `nanoidBatch(count, length?)` → `Array<string>` (native strings, 1 boundary crossing, no Buffer.toString)
- [ ] `snowflakeBatch(count, {nodeId}?)` → `Array<<bigint>`
- [ ] Finalizer callbacks for slab memory
- [ ] Benchmark suite in `/bench`

### v2.0.0 (zig-codec Integration)

- [ ] `codec.encode(buffer, 'base58')` → string
- [ ] `codec.decode(string, 'base58')` → Buffer
- [ ] SIMD base64 encode/decode
- [ ] Constant-time decode option for crypto

### v2.1.0 (Advanced IDs)

- [ ] ULID support (Snowflake + base32 encoding)
- [ ] UUIDv7 support (modern sortable UUID)
- [ ] Custom alphabet support with comptime validation

---

## 11. Troubleshooting Log

### 2024-06-07: Initial scaffold

- **Issue:** `node_api.h not found` during `zig build`.
- **Fix:** Added `-Dnapi-include=node_modules/node-api-headers/include` to build command. Documented in `build.zig` options.
- **Lesson:** N-API headers are a dev dependency, not a system dependency. The build must be hermetic.

### 2025-06-09: Bun — Buffer.toString() bottleneck in Batch

- **Issue:** Nanoid Batch(500) was 12× slower than npm nanoid in Bun (2.1ms vs 0.18ms). Single `nanoid()` also 2× slower than pure-JS nanoid.
- **Root cause:** `Buffer.toString("utf-8", start, end)` in Bun's JavaScriptCore is a slow JS-level UTF-8 decoder path. Snowflake (which returns `bigint[]` directly) was competitive, isolating the bottleneck to string creation from Buffer.
- **Fix:** New `nanoidBatchStrings` native export. Creates an empty JS array via `napi_create_array_with_length`, then in C: `nanoid.generate()` into a stack buffer, `napi_create_string_utf8()` (direct V8 string creation), and `napi_set_element()` to populate the array. One N-API boundary crossing for the entire batch. No Buffer allocation, no Buffer.toString() calls.
- **Lesson:** `napi_create_string_utf8` is the lowest-overhead path to create JS strings from native code in any runtime (Node/V8, Bun/JavaScriptCore). Avoid Buffer.toString() in hot native-addon paths.

### 2024-06-07: Memory ownership confusion

- **Issue:** Initial draft used `defer allocator.free(id)` before `napi_create_string_utf8`.
- **Fix:** Moved `allocator.free(id)` to **after** the N-API string creation. JS copies the bytes; Zig can then free.
- **Lesson:** The N-API `create_string` functions **copy** data. External ArrayBuffers (Phase 3) do **not** copy — they require finalizers.

---

## 12. Glossary

| Term                  | Definition                                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **N-API**             | Node.js API for native addons. C ABI, stable across Node versions.                                                                          |
| **ABI**               | Application Binary Interface. The calling convention and memory layout contract between Zig and Node.js.                                    |
| **CSPRNG**            | Cryptographically Secure Pseudo-Random Number Generator. Unpredictable even to adversaries with computation power.                          |
| **Modulo Bias**       | Statistical skew when mapping a random number from a larger range to a smaller range using `%`.                                             |
| **Snowflake ID**      | 64-bit distributed ID: 41-bit timestamp + 10-bit node + 12-bit sequence. Invented by Twitter.                                               |
| **ULID**              | Universally Unique Lexicographically Sortable Identifier. 26-char Crockford base32 string with embedded timestamp.                          |
| **Zero-Copy**         | Passing data between JS and native without duplicating memory. Achieved via ArrayBuffer views or external buffers.                          |
| **Finalizer**         | A callback invoked by V8 GC when a JS object (e.g., external ArrayBuffer) is garbage collected. Used to free native memory.                 |
| **comptime**          | Zig's compile-time code execution. Used here for alphabet validation and lookup table generation.                                           |
| **errdefer**          | Zig's "deferred cleanup on error" mechanism. Ensures allocations are freed if a function returns an error.                                  |
| **Custom Epoch**      | The base timestamp from which Snowflake time offsets are measured. For zig-id, `2026-01-01T00:00:00.000Z` (`1767225600000`).                |
| **nodeId**            | 10-bit machine identifier, auto-derived from hostname via Wyhash. Stable per machine, collision-tolerant at 1024-granularity.               |
| **Sequence Overflow** | When 4096 IDs have been generated in a single millisecond. Resolved by blocking until the clock advances to the next millisecond.           |
| **Clock Rollback**    | When the system clock jumps backwards (NTP/timezone correction). Handled by blocking until the clock catches up to the last-used timestamp. |

---

## 13. References

- [TigerBeetle Node.js Client](https://github.com/tigerbeetle/tigerbeetle/tree/main/src/clients/node) — The reference architecture for Zig + N-API.
- [Node-API Documentation](https://nodejs.org/api/n-api.html) — Official N-API reference.
- [nanoid](https://github.com/ai/nanoid) — The original pure-JS implementation.
- [Twitter Snowflake](https://github.com/twitter-archive/snowflake) — Original 64-bit ID service.
- [Zig Language Reference](https://ziglang.org/documentation/master/) — `std.crypto.random`, `comptime`, allocators.

---

_Last updated: 2025-06-09_
_Next review: After v1.0.0 npm publish_
