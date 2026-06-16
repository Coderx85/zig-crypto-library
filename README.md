# zig-crypto

A zero-allocation, N-API-stable Node.js native extension for high-performance cryptographic primitives and ID generation, written in Zig.

Prebuilt binaries for Linux (x64/ARM64), macOS (x64/ARM64), and Windows (x64). No `node-gyp` or compilation required.

---

## Install

```bash
npm install zig-crypto
```

Works on Node.js 18+ across all supported platforms. No native compilation step needed — prebuilt binaries are shipped in `dist/bin/`.

---

## Quick Start

```ts
import { nanoid, Snowflake, codec } from "zig-crypto";

// Nanoid — cryptographically secure random string IDs
nanoid(); // "V1StGXR8_Z5jdHi6B-myT"
nanoid(10); // "IRFa-VaY2b"

// Batch — generate 1000 IDs in a single native call
const ids = nanoid.Batch(1000, 21); // string[]

// Snowflake — distributed 64-bit time-ordered IDs
const id = Snowflake.Id(); // 1577836800000000001n (BigInt)
const timestamp = extractSnowflakeTime(id); // Date.now()

// Codec — base64, base58, hex encoding/decoding
codec.base64.encode(Buffer.from("hello")); // "aGVsbG8="
codec.base58.encode(Buffer.from("hello")); // "Cn8eVd3"
codec.hex.encode(Buffer.from("hello")); // "68656c6c6f"
```

---

## API

### `nanoid(length?: number): string`

Generate a cryptographically secure random string ID.

| Parameter | Type     | Default | Description                   |
| --------- | -------- | ------- | ----------------------------- |
| `length`  | `number` | `21`    | ID length (1–128, default 21) |

```ts
nanoid(); // "V1StGXR8_Z5jdHi6B-myT"
nanoid(10); // "IRFa-VaY2b"
```

Uses a 64-character URL-safe alphabet with zero modulo bias. Each byte maps to the alphabet via `byte & 0x3F` — no rejection sampling, no branching.

### `nanoid.Batch(count: number, length?: number): string[]`

Generate multiple IDs in a single JS↔native boundary crossing.

| Parameter | Type     | Default | Description            |
| --------- | -------- | ------- | ---------------------- |
| `count`   | `number` | —       | Number of IDs (1–1000) |
| `length`  | `number` | `21`    | ID length (1–128)      |

```ts
const ids = nanoid.Batch(500, 21); // string[], 500 IDs in one call
```

Creates JS strings directly via `napi_create_string_utf8` — no `Buffer.toString()` overhead.

### `nanoid.BatchBuffer(count: number, length?: number): Buffer`

Zero-copy batch generation returning a single `Buffer` containing all IDs concatenated.

```ts
const buf = nanoid.BatchBuffer(500, 21); // Buffer
```

### `Snowflake.Id(): bigint`

Generate a 64-bit distributed Snowflake ID.

```ts
const id = Snowflake.Id(); // 1577836800000000001n
```

Structure: 41-bit timestamp + 10-bit node ID + 12-bit sequence.

- **Timestamp:** Milliseconds since custom epoch `2026-01-01T00:00:00.000Z`
- **Node ID:** Auto-derived from hostname hash (stable per machine)
- **Sequence:** 12-bit counter, mutex-protected for thread safety

### `Snowflake.Batch(count: number): bigint[]`

Generate multiple Snowflake IDs in a single call.

### `extractSnowflakeTime(id: bigint): number`

Extract the creation timestamp (as epoch milliseconds) from a Snowflake ID.

```ts
const id = Snowflake.Id();
const created = extractSnowflakeTime(id); // Date.now()
```

### `extractSnowflakeNodeId(id: bigint): number`

Extract the 10-bit node ID from a Snowflake ID.

### `extractSnowflakeSequence(id: bigint): number`

Extract the 12-bit sequence counter from a Snowflake ID.

### `codec.base64`

| Method                        | Description                        |
| ----------------------------- | ---------------------------------- |
| `encode(data, options?)`      | Encode buffer to base64 string     |
| `encodeBuf(data, options?)`   | Encode buffer to base64 buffer     |
| `decode(data, options?)`      | Decode base64 string/buffer        |
| `decodeConst(data, options?)` | Constant-time decode (timing-safe) |

Options: `{ urlSafe?: boolean }` — use URL-safe alphabet (`-` and `_` instead of `+` and `/`).

### `codec.base58`

| Method           | Description             |
| ---------------- | ----------------------- |
| `encode(data)`   | Encode buffer to base58 |
| `decode(string)` | Decode base58 to buffer |

### `codec.hex`

| Method                   | Description                 |
| ------------------------ | --------------------------- |
| `encode(data, options?)` | Encode buffer to hex string |
| `decode(string)`         | Decode hex to buffer        |

Options: `{ upper?: boolean }` — use uppercase hex digits.

---

## Performance

| Operation                  | Target     | Notes                                            |
| -------------------------- | ---------- | ------------------------------------------------ |
| `nanoid()` single          | < 1 µs     | Stack buffer + 64KB CSPRNG pool, zero allocation |
| `snowflake()` single       | < 0.5 µs   | Bit ops + mutex lock                             |
| `nanoidBatch(1000)`        | 1 crossing | Native strings, no `Buffer.toString()`           |
| Binary size (per platform) | < 500 KB   | `ReleaseSmall` + strip                           |
| `npm install` time         | < 3 sec    | Prebuilt, no compile                             |

---

## Architecture

```
┌──────────────────────────────────────────┐
│  TypeScript API (index.ts)               │  ← User-facing
├──────────────────────────────────────────┤
│  N-API C ABI Boundary                    │  ← Exports, type marshalling
│  src/napi.zig                            │
├──────────────────────────────────────────┤
│  Zig Core Engine                         │  ← Zero-allocation logic
│  src/id/nanoid.zig                       │
│  src/id/snowflake.zig                    │
│  src/codec/{base64,base58,hex}.zig       │
├──────────────────────────────────────────┤
│  N-API Helpers                           │  ← Reusable error/string/BigInt
│  src/translate.zig                       │
└──────────────────────────────────────────┘
```

- **CSPRNG:** 64KB threadlocal pool refilled via OS entropy (`getrandom` on Linux, `arc4random_buf` on macOS, `BCryptGenRandom` on Windows).
- **Snowflake:** Mutex-protected sequence counter for thread safety across Worker Threads.
- **Codecs:** Base64 (with constant-time decode option), Base58, and Hex — all implemented in Zig with SIMD where applicable.

---

## Supported Platforms

| Platform | Architecture | Status   |
| -------- | ------------ | -------- |
| Linux    | x64          | Prebuilt |
| Linux    | ARM64        | Prebuilt |
| macOS    | x64          | Prebuilt |
| macOS    | ARM64        | Prebuilt |
| Windows  | x64          | Prebuilt |

---

## Building from Source

Requires [Zig](https://ziglang.org/) 0.11+ and Node.js 18+.

```bash
# Install dependencies
npm install

# Build Zig native module (debug)
zig build -Dnapi-include=node_modules/node-api-headers/include

# Build optimized + stripped
zig build -Doptimize=ReleaseSmall -Dnapi-include=node_modules/node-api-headers/include

# Copy binary for local testing
ARCH=$(uname -m | sed 's/x86_64/x86_64/' | sed 's/aarch64/aarch64/')
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
mkdir -p dist/bin/${ARCH}-${PLATFORM}
cp zig-out/lib/libzig_id.so dist/bin/${ARCH}-${PLATFORM}/zig-id.node

# Run tests
npm test
```

### Cross-Compilation

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
