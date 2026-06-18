# zig-crypto

Zero-allocation N-API native extension for high-performance ID generation, encoding, and encrypted tokens. Written in Zig — prebuilt binaries for Linux (x64/ARM64), macOS (x64/ARM64), Windows (x64). No `node-gyp` or compilation.

```bash
npm install zig-crypto
```

---

## Quick Start

```ts
import { nanoid, Snowflake, codec, zst } from "zig-crypto";

nanoid(); // "V1StGXR8_Z5jdHi6B-myT"
nanoid(10); // "IRFa-VaY2b"
nanoid.Batch(1000, 21); // string[1000] — one JS↔native crossing

Snowflake.Id(); // 1577836800000000001n (BigInt)
extractSnowflakeTime(id); // Date.now()

codec.base64.encode(Buffer.from("hello")); // "aGVsbG8="
codec.base58.encode(Buffer.from("hello")); // "Cn8eVd3"
codec.hex.encode(Buffer.from("hello")); // "68656c6c6f"

// ZST: XChaCha20-Poly1305 + BLAKE2b KDF encrypted tokens
const key = zst.generateKey(32);
const token = zst.sign({ sub: "user_123" }, key, {
  expiresIn: "1h",
  audience: "api.example.com",
});
const claims = zst.verify(token, key, { audience: "api.example.com" });
const header = zst.decode(token); // no crypto, header only
```

---

## API

### nanoid

| Method                        | Returns    | Description                                                                                                                                      |
| ----------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `nanoid(length?)`             | `string`   | Crypto random ID, 64-char URL-safe alphabet. Length 1–128 (default 21). Zero modulo bias (`byte & 0x3F`), zero branching, no rejection sampling. |
| `Batch(count, length?)`       | `string[]` | Generate IDs in a single native call. Count 1–1000. No `Buffer.toString()` — creates V8 strings directly.                                        |
| `BatchBuffer(count, length?)` | `Buffer`   | Zero-copy batch — all IDs concatenated in one Buffer.                                                                                            |

### Snowflake

64-bit distributed IDs: 41-bit timestamp (`EPOCH=2026-01-01`) + 10-bit node ID (auto-derived from hostname hash) + 12-bit sequence (mutex-protected).

| Method         | Returns    | Description            |
| -------------- | ---------- | ---------------------- |
| `Id()`         | `bigint`   | One snowflake ID       |
| `Batch(count)` | `bigint[]` | Multiple IDs, one call |

Extractors: `extractSnowflakeTime(id)` → `number`, `extractSnowflakeNodeId(id)` → `number`, `extractSnowflakeSequence(id)` → `number`.

### codec

| Module   | Methods                                        | Options                                      |
| -------- | ---------------------------------------------- | -------------------------------------------- |
| `base64` | `encode`, `encodeBuf`, `decode`, `decodeConst` | `{ urlSafe?: boolean }` — ±/ vs -\_ alphabet |
| `base58` | `encode`, `decode`                             | —                                            |
| `hex`    | `encode`, `decode`                             | `{ upper?: boolean }` — uppercase hex        |

`decodeConst` is constant-time (timing-safe). All implemented in Zig with SIMD where applicable.

### zst — Zig Secure Tokens

**Sign (encrypt) a payload:**

```ts
zst.sign(payload, key, options?): string
```

| Param     | Type                             | Notes             |
| --------- | -------------------------------- | ----------------- |
| `payload` | `object \| string \| Buffer`     | JSON-serializable |
| `key`     | `string \| Buffer \| Uint8Array` | Must be ≥32 bytes |
| `options` | `ZstSignOptions`                 | See below         |

`ZstSignOptions`:

| Option          | Type                  | Description                                   |
| --------------- | --------------------- | --------------------------------------------- |
| `expiresIn`     | `number \| string`    | e.g. `3600`, `"1h"`, `"7d"`                   |
| `notBefore`     | `string`              | e.g. `"5m"`                                   |
| `audience`      | `string`              | Claim `aud`                                   |
| `issuer`        | `string`              | Claim `iss`                                   |
| `subject`       | `string`              | Claim `sub`                                   |
| `jwtid`         | `string`              | Claim `jti` (explicit)                        |
| `rev`           | `number`              | Revocation counter — O(1) "logout everywhere" |
| `header`        | `Record<string, any>` | Custom header fields                          |
| `mutatePayload` | `boolean`             | Inject `iat`/`exp` into payload               |

**Verify (decrypt) a token:**

```ts
zst.verify(token, key, options?): ZstPayload
```

`ZstVerifyOptions`:

| Option             | Type               | Description                        |
| ------------------ | ------------------ | ---------------------------------- |
| `audience`         | `string`           | Reject if `aud` mismatch           |
| `issuer`           | `string`           | Reject if `iss` mismatch           |
| `subject`          | `string`           | Reject if `sub` mismatch           |
| `jwtid`            | `string`           | Reject if `jti` mismatch           |
| `currentRev`       | `number`           | Reject if token `rev` ≠ this value |
| `clockTolerance`   | `number`           | Leeway (seconds) for `exp`/`nbf`   |
| `clockTimestamp`   | `number`           | Fixed time for testing             |
| `maxAge`           | `number \| string` | Reject tokens older than this      |
| `ignoreExpiration` | `boolean`          | Skip `exp` check                   |
| `ignoreNotBefore`  | `boolean`          | Skip `nbf` check                   |

**Decode (header only, no crypto):**

```ts
zst.decode(token): ZstDecodedHeader
// → { ver: "1", typ: "ZST", mode: "local", encrypted: true }
```

**Generate key:**

```ts
zst.generateKey(length?): Buffer
// length default 32, minimum 32
```

**Error hierarchy:**

```ts
ZstError
├── ZstExpiredError     // token exp passed
├── ZstNotBeforeError   // used before nbf
├── ZstAudienceError    // aud mismatch
├── ZstIssuerError      // iss mismatch
├── ZstSubjectError     // sub mismatch
├── ZstJwtIdError       // jti mismatch
└── ZstRevokedError     // rev counter mismatch
```

**Token format:**

```
zst_v1.local.<header_b64>.<nonce_b64>.<ciphertext_b64>.<tag_b64>
```

| Part             | Contents                                             |
| ---------------- | ---------------------------------------------------- |
| `header_b64`     | `{"ver":"1","typ":"ZST","mode":"local"}` (base64url) |
| `nonce_b64`      | XChaCha20 192-bit random nonce (base64url)           |
| `ciphertext_b64` | Encrypted claims JSON (base64url)                    |
| `tag_b64`        | Poly1305 128-bit auth tag (base64url)                |

---

## Performance

### Zig-native primitives

| Operation            | Latency  | Notes                                        |
| -------------------- | -------- | -------------------------------------------- |
| `nanoid()`           | < 1 µs   | Stack buf + 64KB CSPRNG pool, zero alloc     |
| `nanoid.Batch(1000)` | < 80 µs  | 1 JS↔native crossing, native strings         |
| `Snowflake.Id()`     | < 0.5 µs | Bit ops + mutex lock                         |
| `zst.sign()`         | < 20 µs  | BLAKE2b KDF + XChaCha20-Poly1305 + base64url |
| `zst.verify()`       | < 30 µs  | base64url decode + AEAD decrypt + claims     |
| `zst.decode()`       | < 10 µs  | Parse only, no crypto                        |
| Binary size          | < 500 KB | `ReleaseSmall` + strip                       |
| `npm install`        | < 3 sec  | Prebuilt, no compile                         |

### vs pure-JS (Bun v1.3.14, Linux x64, 1000 iter)

| Scenario     | zig-crypto | JS competitor                               | Speed-up |
| ------------ | ---------- | ------------------------------------------- | -------- |
| Token sign   | **15 µs**  | 80 µs (`jose` HS256)                        | **×5.3** |
| Token verify | **26 µs**  | 102 µs (`jose` HS256)                       | **×4.0** |
| AEAD encrypt | **15 µs**  | 40 µs (`@noble/ciphers` XChaCha20-Poly1305) | **×2.6** |
| AEAD decrypt | **12 µs**  | 12 µs (`@noble/ciphers`)                    | **×1.0** |

**Why faster?** Zig runs the full pipeline in native code with arena-allocated temp memory and no JS object allocations. Pure-JS libs allocate multiple `Uint8Array`/`ArrayBuffer` per operation, triggering GC pressure. The gap widens with larger payloads and higher throughput.

---

## Architecture

```
┌──────────────────────────────────────────────┐
│  index.ts  (runtime arch/platform detection)  │  ← User-facing
├──────────────────────────────────────────────┤
│  N-API C ABI  (src/napi.zig — 12 exports)    │  ← Boundary, marshalling
├──────────────────────────────────────────────┤
│  Zig Core Engine                              │  ← Zero-allocation
│  ├── src/id/nanoid.zig                        │
│  ├── src/id/snowflake.zig                     │
│  ├── src/codec/{base64,base58,hex}.zig        │
│  └── src/token/{zst,claims,xchacha20}.zig     │
├──────────────────────────────────────────────┤
│  Crypto Primitives                            │
│  ├── src/crypto/blake2b.zig  (KDF)           │
│  ├── src/crypto/rand.zig     (CSPRNG pool)   │
│  └── src/token/xchacha20.zig (AEAD cipher)   │
├──────────────────────────────────────────────┤
│  src/translate.zig                            │  ← N-API helpers
└──────────────────────────────────────────────┘
```

**CSPRNG:** 64KB threadlocal pool refilled via OS entropy (`getrandom`/`arc4random_buf`/`BCryptGenRandom`).
**Snowflake:** Mutex-protected sequence for thread safety across Worker Threads.
**ZST:** XChaCha20-Poly1305 AEAD + BLAKE2b KDF for domain separation. Inspired by PASETO. `rev` counter for O(1) revocation. Arena allocator per N-API call — all temp memory freed at once on return.

---

## Supported Platforms

| Platform | Arch       | Binary            |
| -------- | ---------- | ----------------- |
| Linux    | x64, ARM64 | `libzig_id.so`    |
| macOS    | x64, ARM64 | `libzig_id.dylib` |
| Windows  | x64        | `zig_id.dll`      |

Requires Node.js 18+. Runtime loader auto-detects arch, platform, and Linux glibc/musl ABI.

---

## Build from Source

Requires [Zig](https://ziglang.org/) 0.11+.

```bash
npm install
zig build -Doptimize=ReleaseSmall -Dnapi-include=node_modules/node-api-headers/include
mkdir -p dist/bin/$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')
cp zig-out/lib/libzig_id.* dist/bin/*/zig-id.node
npm test
```

Cross-compilation:

```bash
zig build -Dtarget=x86_64-linux-gnu    # Linux x64
zig build -Dtarget=aarch64-linux-gnu   # Linux ARM64
zig build -Dtarget=x86_64-macos        # macOS x64
zig build -Dtarget=aarch64-macos       # macOS ARM64
zig build -Dtarget=x86_64-windows-gnu  # Windows x64
```

---

## License

MIT
