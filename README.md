# zig-id

A zero-allocation, N-ABI-stable Node.js native extension for high-performance
ID generation, written in Zig. Provides both nanoid (URL-safe random strings)
and Snowflake (time-ordered 64-bit integers).

```js
const { nanoid, Snowflake } = require('zig-id');

// Random URL-safe IDs
const id = nanoid();          // "V1StGXR8_Z5jdHi6B-myT"
const id32 = nanoid(32);      // 32-character ID
const batch = nanoid.Batch(100);  // 100 IDs at once

// Snowflake IDs
const snowflakeId = Snowflake.Id();      // 57406623190478848n
const ids = Snowflake.Batch(5);          // [57406623194673152n, ...]
```

## nanoid API

### `nanoid(length?)`

Returns a URL-safe random ID string.

- **Default length:** 21 characters (126 bits of entropy)
- **Alphabet:** `A-Za-z0-9_-` (64 chars, zero modulo bias)
- **Entropy:** CSPRNG-backed (`getrandom` / `arc4random` / `BCryptGenRandom`)
- **Length range:** 1–128

### `nanoid.Batch(count, length?)`

Generates `count` random IDs in a single native call. Accepts 1–1000.
Throws `RangeError` if count or length is out of range.

## Snowflake API

### `Snowflake.Id()`

Returns a unique 64-bit Snowflake ID as a `BigInt`. The ID embeds a timestamp
(ms since 2026-01-01), a machine-specific node ID, and a per-millisecond
sequence counter.

- **Thread-safe** — uses a spinlock internally
- **Monotonic** — each ID is strictly greater than the previous
- **Zero-config** — node ID is auto-derived from hostname

### `Snowflake.Batch(count)`

Generates `count` Snowflake IDs in a single call. Accepts 1–1000.
Throws `RangeError` if count is out of range.

## Install

```
npm install zig-id
```

Prebuilt binaries are provided for:

| Platform | Architecture |
|----------|-------------|
| Linux    | x64, arm64  |
| macOS    | x64, arm64  |
| Windows  | x64         |

No build tools required — binaries ship with the package.

## Build from source

Requires [Zig](https://ziglang.org/download/) 0.16.0+.

```bash
npm install
zig build -Doptimize=ReleaseSmall -Dnapi-include=node_modules/node-api-headers/include
mkdir -p prebuilds/$(node -e "console.log(process.platform+'-'+process.arch)")
cp zig-out/lib/libzig_id.* prebuilds/*/zig-id.node
node test/test.js
```

## Test

```bash
# Zig tests
zig build test

# JS integration tests
npm test
```

## License

MIT
