// GC pressure test: verify zig-codec doesn't leak or cause excessive GC
//
// Usage: node --expose-gc bench/gc-profile.js
// Requires: npm run build (tsc) first

import { codec } from "../dist/index.js";

if (typeof global.gc !== "function") {
  console.error("Run with --expose-gc: node --expose-gc bench/gc-profile.js");
  process.exit(1);
}

const MB = 1024 * 1024;

function measureGC(label, fn, iterations) {
  // Warmup
  for (let i = 0; i < 100; i++) fn();

  // Force GC and measure baseline
  global.gc();
  const baseline = process.memoryUsage().heapUsed;

  // Run allocations
  for (let i = 0; i < iterations; i++) fn();

  // Force GC again and measure
  global.gc();
  const after = process.memoryUsage().heapUsed;

  const leaked = after - baseline;
  const perOp = iterations > 0 ? leaked / iterations : 0;
  const status = perOp < 100 ? "OK" : "LEAK";
  console.log(
    `  ${label}: ${(leaked / MB).toFixed(3)} MB delta, ${perOp.toFixed(1)} B/op [${status}]`
  );
}

// ── Test: encode/decode roundtrip ──

console.log("\n═══ GC Pressure: Base64 Roundtrip ═══\n");

const data = Buffer.alloc(1024);
for (let i = 0; i < 1024; i++) data[i] = i & 0xff;

const ITER = 10_000;

measureGC("encode 1 KB", () => codec.base64.encode(data), ITER);

let enc = codec.base64.encode(data);
measureGC("decode 1 KB", () => codec.base64.decode(enc), ITER);

measureGC("decodeConst 1 KB", () => codec.base64.decodeConst(enc), ITER);

// ── Test: encode/decode various sizes ──

console.log("\n═══ GC Pressure: Various Sizes ═══\n");

const sizes = [16, 256, 4096, 65536];

for (const size of sizes) {
  const buf = Buffer.alloc(size);
  for (let i = 0; i < size; i++) buf[i] = i & 0xff;
  const iter = Math.max(1_000, Math.floor(10_000_000 / size));

  measureGC(
    `encode ${(size / 1024).toFixed(1)} KB`,
    () => codec.base64.encode(buf),
    iter
  );

  const b64 = codec.base64.encode(buf);
  measureGC(
    `decode ${(size / 1024).toFixed(1)} KB`,
    () => codec.base64.decode(b64),
    iter
  );
}

// ── Test: burst (rapid fire, no GC in between) ──

console.log("\n═══ GC Pressure: Burst ═══\n");

const BURST = 100_000;
const small = Buffer.from("Hello, World!");

// Don't GC between iterations — simulate real workload
const gcBefore = process.memoryUsage().heapUsed;
const results = [];
for (let i = 0; i < BURST; i++) {
  results.push(codec.base64.encode(small));
}
const gcAfter = process.memoryUsage().heapUsed;
// Let results get collected
results.length = 0;

global.gc();
const gcAfterCollect = process.memoryUsage().heapUsed;
const burstLeak = gcAfterCollect - gcBefore;

console.log(
  `  encode burst ${BURST.toExponential()} × 13B: ${(burstLeak / MB).toFixed(3)} MB delta [${burstLeak < 100_000 ? "OK" : "LEAK"}]`
);

// ── Summary ──

console.log("\n═══ Done ═══");
