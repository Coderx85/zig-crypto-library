# zig-crypto — CONTEXT.md

> **Single source of truth for the `zig-crypto` project.**
> This document is append-only. When something changes, add a dated entry. Do not delete history.

---

## 1. Project Identity

| Field              | Value                                               |
| ------------------ | --------------------------------------------------- |
| **Name**           | `zig-crypto`                                        |
| **Version**        | `0.3.2`                                            |
| **License**        | MIT                                                 |
| **Registry**       | `npm`                                               |
| **Repository**     | `github.com/<user>/zig-crypto`                      |
| **Language**       | Zig (core) + TypeScript (wrapper)                   |
| **Runtime Target** | Node.js 18+ (N-API v9+)                             |
| **Platforms**      | Linux (x64/ARM64), macOS (x64/ARM64), Windows (x64) |

### One-Sentence Pitch

> A zero-allocation, N-API-stable Node.js native extension for high-performance ID generation and encrypted tokens, written in Zig, shipping prebuilt binaries for all desktop platforms.

### Three-Sentence Expansion

Node.js is excellent for I/O but punishes CPU-bound cryptographic operations with GC pressure and interpreter overhead. `zig-crypto` extends the Node.js runtime with a Zig-native layer for deterministic, zero-allocation ID generation, encoding, and encrypted token operations. It provides cryptographically secure nanoid strings, distributed Snowflake 64-bit integers, base64/base58/hex codecs, and XChaCha20-Poly1305 encrypted ZST tokens — all without V8 GC pressure or cross-boundary allocation overhead.

---

## 2. Why This Project Exists

### The Problem

- **nanoid** (pure JS) allocates a new string per ID. At 10k IDs/sec, V8 GC stalls the event loop.
- **Snowflake** requires 64-bit integer math that JavaScript `number` cannot represent safely past `2^53`.
- **JWT libraries** (`jsonwebtoken`, `jose`) are pure JS — sign/verify incurs GC pressure from multiple `Uint8Array` allocations per operation.
- **Existing native addons** use `node-gyp`, `nan`, or C++ — breaking on every Node major version and requiring Python/Visual Studio on user machines.
- No existing package combines **IDs, codecs, and encrypted tokens** in one N-API-native module.

### The TigerBeetle Inspiration

TigerBeetle writes one Zig core (`tb_client`) and wraps it for every language via FFI/N-API. Their insight: **write the hard stuff once in a systems language, expose a thin C ABI, ship prebuilt binaries.** We apply the same pattern to ID generation, codecs, and token cryptography.

### Success Criteria

1. `npm install zig-crypto` works on all 5 target platforms without `node-gyp` or compilation.
2. `nanoid()` returns a valid 21-char string in < 1µs (single call).
3. `snowflake()` returns a valid `bigint` with extractable timestamp.
4. Batch generation crosses the JS↔native boundary **once** for 1000 IDs.
5. ZST sign/verify is **3–5× faster** than pure-JS equivalents (`jose`, `@noble/ciphers`).
6. Binary size < 500KB per platform.

---

## 3. Architecture

### Layer Cake

```
┌──────────────────────────────────────────────┐
│  index.ts / index.d.ts                       │  ← TypeScript API, user-facing
│  (runtime arch/platform detection)           │
├──────────────────────────────────────────────┤
│  N-API C ABI Boundary                        │  ← Exports, type marshalling
│  src/napi.zig  (12 exports)                  │
├──────────────────────────────────────────────┤
│  Zig Core Engine                             │  ← Zero-allocation logic
│  ├── src/id/nanoid.zig                       │
│  ├── src/id/snowflake.zig                    │
│  ├── src/codec/{base64,base58,hex}.zig       │
│  └── src/token/                              │
│       ├── zst.zig        (sign/verify/...)   │
│       ├── claims.zig     (JSON serialization)│
│       ├── xchacha20.zig  (AEAD cipher)       │
│       └── errors.zig     (error types)       │
├──────────────────────────────────────────────┤
│  Crypto Primitives                           │
│  ├── src/crypto/blake2b.zig  (KDF)           │
│  ├── src/crypto/rand.zig     (CSPRNG)        │
│  └── src/token/xchacha20.zig (AEAD)          │
├──────────────────────────────────────────────┤
│  N-API Helpers                               │  ← Reusable error/string/BigInt
│  src/translate.zig                           │
├──────────────────────────────────────────────┤
│  Module root                                 │
│  src/main.zig                                │
└──────────────────────────────────────────────┘
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

### Data Flow: ZST Sign / Verify

```
JS → N-API: parse args                           JS → N-API: parse args
  │                                                 │
  ▼ (sign)                                          ▼ (verify)
BLAKE2b KDF → enc_key[32]                        split token → [prefix,H,N,C,T]
CSPRNG → nonce[24]                               base64url decode N, C, T
xchacha20.encrypt(claims, key, nonce)            BLAKE2b KDF → enc_key[32]
  → { ciphertext, tag }                           xchacha20.decrypt(C, tag, key, nonce)
base64url encode [H,N,C,T]                         → plaintext JSON
assemble "zst_v1.local.H.N.C.T"                  parse claims + validate (exp/aud/rev/...)
  │                                                 │
  ▼                                                 ▼
JS ← token string                                JS ← { sub, aud, exp, rev, ... }
```

### Memory Ownership Rules

| Memory                      | Owner          | Lifetime | Free                                              |
| --------------------------- | -------------- | -------- | ------------------------------------------------- |
| `[MAX_LENGTH]u8` (nanoid)   | Stack          | Call     | Never alloc'd (copied by napi_create_string_utf8) |
| `u64` (Snowflake)           | Register       | Call     | Return by value                                   |
| Buffer slab (batch)         | page_allocator | Until GC | Finalizer callback                                |
| key/nonce `[32/24]u8` (ZST) | Stack          | Call     | Never alloc'd (comptime-sized arrays)             |
| ciphertext (ZST)            | Arena          | Call     | arena.deinit() at end of N-API call               |
| JS String/BigInt            | V8 heap        | Until GC | V8 manages                                        |

**Golden Rule:** Heap memory passed to JS via `napi_create_external_*` must have a finalizer. Stack memory must never be passed as external. ZST uses an arena per N-API call — all temp memory freed at once when the function returns.

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

### Decision: XChaCha20-Poly1305 + BLAKE2b KDF + Rev Counter

- **Status:** Accepted
- **Rationale (cipher):** XChaCha20's 192-bit nonce makes random nonce collisions impossible (~2^64 msgs). AES-GCM and ChaCha20-Poly1305 use 96-bit nonces requiring stateful counters — unacceptable for stateless tokens.
- **Rationale (KDF):** `BLAKE2b("zst-v1-local-encryption" || master_key)` provides domain separation. The same master key can derive subkeys for different purposes/versions. Cost is ~1µs, negligible vs ~15µs total.
- **Rationale (rev):** Traditional JWT needs either short expirations (poor UX) or server-side blocklists (O(n)). ZST's `rev` counter gives O(1) "logout everywhere" — increment a per-user counter, reject tokens with older values at verify time.
- **Consequence:** Tokens are ~256B vs JWT's ~113B (nonce + tag overhead). Confidentiality + no nonce management + O(1) revocation outweighs size cost. Apps store a monotonic `rev` per user. Arena allocator per N-API call frees all temp memory at once.

### Decision: Runtime Detection over `node-gyp-build`

- **Status:** Accepted
- **Rationale:** Inspired by TigerBeetle's approach. Custom IIFE loader in `index.ts` detects `process.arch`, `process.platform`, and Linux ABI (glibc/musl) at runtime. Zero runtime dependencies. Binaries shipped in `dist/bin/{arch}-{platform}/`.
- **Consequence:** No `node-gyp-build` dependency. Loader is ~30 lines of TypeScript. Supports glibc/musl detection for Linux.

---

## 5. File Inventory

| File                                | Purpose                                                 | Stability |
| ----------------------------------- | ------------------------------------------------------- | --------- |
| `build.zig`                         | Build target, cross-compilation                         | Stable    |
| `src/main.zig`                      | Module root                                             | Stable    |
| `src/napi.zig`                      | N-API layer: 12 exports (nanoid, Snowflake, codec, zst) | Stable    |
| `src/id/nanoid.zig`                 | CSPRNG, alphabet mapping, batch                         | Stable    |
| `src/id/snowflake.zig`              | Bit packing, timestamp, mutex                           | Stable    |
| `src/codec/{base64,base58,hex}.zig` | Encoding/decoding                                       | Stable    |
| `src/token/zst.zig`                 | ZST sign/verify/decode/generateKey                      | Stable    |
| `src/token/xchacha20.zig`           | XChaCha20-Poly1305 AEAD                                 | Stable    |
| `src/token/claims.zig`              | JSON claims serialization                               | Stable    |
| `src/token/errors.zig`              | ZstExpiredError, ZstRevokedError, etc.                  | Stable    |
| `src/crypto/blake2b.zig`            | BLAKE2b KDF                                             | Stable    |
| `src/crypto/rand.zig`               | CSPRNG pool                                             | Stable    |
| `index.ts` / `index.d.ts`           | JS loader + TypeScript declarations                     | Stable    |
| `package.json`                      | npm manifest                                            | Stable    |
| `.github/workflows/release.yml`     | Matrix CI: 5 targets + publish                          | Stable    |
| `test/test.js`                      | Smoke tests                                             | Evolving  |
| `README.md`                         | User-facing docs                                        | Evolving  |

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

# Copy binary to dist/bin/ for local testing
ARCH=$(uname -m | sed 's/x86_64/x86_64/' | sed 's/aarch64/aarch64/')
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
mkdir -p dist/bin/${ARCH}-${PLATFORM}
cp zig-out/lib/libzig_id.* dist/bin/${ARCH}-${PLATFORM}/zig-id.node  # Unix
cp zig-out/bin/zig_id.dll dist/bin/x86_64-windows/zig-id.node        # Windows

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
dist/bin/
├── x86_64-linux-gnu/
│   └── zig-id.node
├── aarch64-linux-gnu/
│   └── zig-id.node
├── x86_64-macos/
│   └── zig-id.node
├── aarch64-macos/
│   └── zig-id.node
└── x86_64-windows/
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

| Operation                        | Target     | Notes                                               |
| -------------------------------- | ---------- | --------------------------------------------------- |
| `nanoid()`                       | < 1 µs     | Stack buf + 64KB CSPRNG pool                        |
| `snowflake()`                    | < 0.5 µs   | Bit ops + mutex                                     |
| `nanoid.Batch(1000)`             | 1 crossing | Native strings, no Buffer.toString()                |
| `zst.sign()`                     | < 20 µs    | BLAKE2b KDF + XChaCha20-Poly1305 + base64url        |
| `zst.verify()`                   | < 30 µs    | base64url decode + AEAD decrypt + claims validation |
| `zst.decode()`                   | < 10 µs    | Parse only, no crypto                               |
| vs `jose` HS256 sign             | ×5         | ZST is 5.3× faster (15 vs 80 µs)                    |
| vs `@noble/ciphers` AEAD encrypt | ×2.6       | ZST is 2.6× faster (15 vs 40 µs)                    |
| Binary size                      | < 500 KB   | ReleaseSmall + strip                                |
| `npm install`                    | < 3 sec    | Prebuilt, no compile                                |

---

## 10. Roadmap

### ✅ Implemented (current)

- [x] `nanoid()` + `nanoid.Batch()` + `nanoid.BatchBuffer()`
- [x] `Snowflake.Id()` + `Snowflake.Batch()` + extract helpers
- [x] `codec.base64` (encode/decode, urlSafe, constant-time decode)
- [x] `codec.base58` (encode/decode)
- [x] `codec.hex` (encode/decode, upper option)
- [x] `zst.sign()` + `zst.verify()` + `zst.decode()` + `zst.generateKey()`
- [x] N-API module registration + cross-compilation CI (5 targets)
- [x] TypeScript definitions + npm publish with prebuilt binaries

### 🔜 Next

- [ ] `snowflakeBatch(count, {nodeId}?)` → `bigint[]`
- [ ] Finalizer callbacks for slab memory
- [ ] Benchmark suite (`/bench`)
- [ ] `public` mode for ZST (signed, not encrypted)
- [ ] Key rotation via `kid` header
- [ ] Asymmetric ZST mode (Ed25519)

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

### 2026-06-18: v0.3.1 — Type consolidation + README overhaul

- **Removed dead code:** `throwZstError()` defined but never called.
- **Consolidated types:** `ZstPayload`, `ZstHeader`, `ZstCompleteResult`, `ZstDecodedHeader`, `ZstSignOptions`, `ZstVerifyOptions`, `ZstDecodeOptions`, `ZstModule`, all ZST error classes, `NanoidFunction`, and `SnowflakeModule` were defined across 4 files (`index.ts`, `zst.types.ts`, `nanoid.types.ts`, `snowflake.types.ts`). All now live in `native.types.ts`. Deleted 3 redundant files.
- **Extracted helper:** `toBuffer()` in `index.ts` replaces duplicated `Buffer.isBuffer` pattern in `zst.sign()` and `zst.verify()`.
- **README compressed:** 410→247 lines, same technical detail. Tables replace prose sections throughout.
- **Version bump:** `0.2.56` → `0.3.2` (auto-incremented by pre-commit hook)

### 2026-06-18: ZST benchmarked against pure-JS competitors

- **Benchmarks:** ZST sign ×5.3 faster than `jose` HS256, ×2.6 faster than `@noble/ciphers` raw XChaCha20-Poly1305 encrypt. Verify ×4.0 faster than `jose`, ×1.0–1.3 vs `@noble/ciphers` decrypt. Decode-only is slower than `jose`/`@noble/ciphers` (no crypto to amortize native call overhead).
- **Root cause:** Pure-JS libraries allocate multiple `Uint8Array`/`ArrayBuffer` objects per crypto operation, triggering GC pressure. Zig runs the full pipeline in native code with arena-allocated temp memory.
- **Lessons:** (1) The biggest ZST advantage is in sign/encrypt where key derivation + nonce generation + AEAD + encoding all run in native code with zero JS allocations. (2) Decode-only is slower than pure JS because there's no crypto work to amortize the N-API boundary crossing — but decode is the least performance-critical path. (3) Token size (256B vs 113B for JWT) is the cost of encryption vs signing.

---

## 12. Glossary

| Term                   | Definition                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **N-API**              | Node.js API for native addons. C ABI, stable across Node versions.                                                                          |
| **ABI**                | Application Binary Interface — calling convention and memory layout between Zig and Node.js.                                                |
| **CSPRNG**             | Cryptographically Secure Pseudo-Random Number Generator.                                                                                    |
| **XChaCha20-Poly1305** | AEAD cipher with 192-bit nonce — safe for random nonces. Used by ZST for token encryption.                                                  |
| **BLAKE2b**            | Hash function used by ZST for domain-separated key derivation.                                                                              |
| **ZST**                | Zig Secure Token — encrypted token format using XChaCha20-Poly1305 + BLAKE2b KDF.                                                           |
| **rev**                | Monotonic revocation counter embedded in ZST tokens for O(1) "logout everywhere".                                                           |
| **Modulo Bias**        | Statistical skew when mapping random bytes to a smaller range using `%`.                                                                    |
| **Snowflake ID**       | 64-bit distributed ID: 41-bit timestamp + 10-bit node + 12-bit sequence.                                                                    |
| **ULID**               | Universally Unique Lexicographically Sortable Identifier. 26-char base32 with embedded timestamp.                                           |
| **Zero-Copy**          | Passing data between JS and native without duplicating memory. Achieved via ArrayBuffer views or external buffers.                          |
| **Finalizer**          | A callback invoked by V8 GC when a JS object (e.g., external ArrayBuffer) is garbage collected. Used to free native memory.                 |
| **comptime**           | Zig's compile-time code execution. Used here for alphabet validation and lookup table generation.                                           |
| **errdefer**           | Zig's "deferred cleanup on error" mechanism. Ensures allocations are freed if a function returns an error.                                  |
| **Custom Epoch**       | The base timestamp from which Snowflake time offsets are measured. For zig-id, `2026-01-01T00:00:00.000Z` (`1767225600000`).                |
| **nodeId**             | 10-bit machine identifier, auto-derived from hostname via Wyhash. Stable per machine, collision-tolerant at 1024-granularity.               |
| **Sequence Overflow**  | When 4096 IDs have been generated in a single millisecond. Resolved by blocking until the clock advances to the next millisecond.           |
| **Clock Rollback**     | When the system clock jumps backwards (NTP/timezone correction). Handled by blocking until the clock catches up to the last-used timestamp. |

---

## 13. References

- [TigerBeetle Node.js Client](https://github.com/tigerbeetle/tigerbeetle/tree/main/src/clients/node) — The reference architecture for Zig + N-API.
- [Node-API Documentation](https://nodejs.org/api/n-api.html) — Official N-API reference.
- [nanoid](https://github.com/ai/nanoid) — The original pure-JS implementation.
- [Twitter Snowflake](https://github.com/twitter-archive/snowflake) — Original 64-bit ID service.
- [Zig Language Reference](https://ziglang.org/documentation/master/) — `std.crypto.random`, `comptime`, allocators.

---

_Last updated: 2026-06-18_
_Next review: After next benchmark pass_
