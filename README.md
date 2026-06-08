# zig-id

A zero-allocation, N-ABI-stable Node.js native extension for high-performance
Snowflake ID generation, written in Zig.

```js
const { Snowflake } = require('zig-id');

const id = Snowflake.Id();      // 57406623190478848n
const ids = Snowflake.Batch(5); // [ 57406623194673152n, 57406623194673153n, ... ]
```

## API

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
| Linux | x64, arm64 |
| macOS | x64, arm64 |
| Windows | x64 |

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
