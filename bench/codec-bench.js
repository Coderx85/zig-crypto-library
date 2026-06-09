// Benchmark: zig-codec base64 vs Node Buffer vs base64-js (pure JS)
//
// Usage: node bench/codec-bench.js
// Requires: npm run build (tsc) first

import { codec } from "../dist/index.js";
import { toByteArray, fromByteArray } from "base64-js";

function fmt(ns) {
  if (ns >= 1_000_000_000) return (ns / 1_000_000_000).toFixed(2) + " s";
  if (ns >= 1_000_000) return (ns / 1_000_000).toFixed(2) + " ms";
  if (ns >= 1_000) return (ns / 1_000).toFixed(2) + " µs";
  return ns.toFixed(0) + " ns";
}

function bench(label, fn, iterations) {
  for (let i = 0; i < 100; i++) fn();
  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) fn();
  const end = process.hrtime.bigint();
  const perOp = Number(end - start) / iterations;
  console.log(
    `  ${label.padEnd(40)} ${fmt(perOp).padStart(12)}  (${iterations.toExponential()} iters)`
  );
  return perOp;
}

const SEP = "  " + "-".repeat(72);

// ── Round 1: Encode ──

console.log("\n═══ Encode ═══");
const encodeSizes = [8, 64, 512, 4096, 65536];
const encodeIter = 5_000;

for (const size of encodeSizes) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;

  console.log(`\n--- ${size.toLocaleString()} bytes ---`);
  const zig = bench(
    "zig-codec encode",
    () => codec.base64.encode(data),
    encodeIter
  );
  const node = bench(
    "Buffer.toString('base64')",
    () => data.toString("base64"),
    encodeIter
  );
  const b64js = bench(
    "base64-js fromByteArray",
    () => fromByteArray(data),
    encodeIter
  );
  bench(
    "zig-codec encode (urlSafe)",
    () => codec.base64.encode(data, { urlSafe: true }),
    encodeIter
  );

  if (size > 0) {
    const zigMb = size / 1024 / 1024 / (zig / 1e9);
    const nodeMb = size / 1024 / 1024 / (node / 1e9);
    const b64jsMb = size / 1024 / 1024 / (b64js / 1e9);
    console.log(
      `  ${"zig-codec MB/s".padEnd(40)} ${zigMb.toFixed(1).padStart(12)} MB/s`
    );
    console.log(
      `  ${"Buffer MB/s".padEnd(40)} ${nodeMb.toFixed(1).padStart(12)} MB/s`
    );
    console.log(
      `  ${"base64-js MB/s".padEnd(40)} ${b64jsMb.toFixed(1).padStart(12)} MB/s`
    );
  }
}

// ── Round 2: Decode ──

console.log(`\n\n═══ Decode ═══`);

for (const size of encodeSizes) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;
  const encoded = codec.base64.encode(data);
  const encodedStr = data.toString("base64");
  const b64jsEncoded = fromByteArray(data);

  console.log(`\n--- ${size.toLocaleString()} bytes ---`);
  const zig = bench(
    "zig-codec decode",
    () => codec.base64.decode(encoded),
    encodeIter
  );
  const node = bench(
    "Buffer.from(str, 'base64')",
    () => Buffer.from(encodedStr, "base64"),
    encodeIter
  );
  const b64js = bench(
    "base64-js toByteArray",
    () => toByteArray(b64jsEncoded),
    encodeIter
  );
  bench(
    "zig-codec decodeConst",
    () => codec.base64.decodeConst(encoded),
    encodeIter
  );

  if (size > 0) {
    const outSize = Math.ceil(size / 3) * 4;
    const decodedSize = Math.floor(outSize / 4) * 3;
    const zigMb = decodedSize / 1024 / 1024 / (zig / 1e9);
    const nodeMb = decodedSize / 1024 / 1024 / (node / 1e9);
    const b64jsMb = decodedSize / 1024 / 1024 / (b64js / 1e9);
    console.log(
      `  ${"zig-codec MB/s".padEnd(40)} ${zigMb.toFixed(1).padStart(12)} MB/s`
    );
    console.log(
      `  ${"Buffer MB/s".padEnd(40)} ${nodeMb.toFixed(1).padStart(12)} MB/s`
    );
    console.log(
      `  ${"base64-js MB/s".padEnd(40)} ${b64jsMb.toFixed(1).padStart(12)} MB/s`
    );
  }
}

// ── Round 3: Head-to-head at 1 KB ──

console.log(`\n\n═══ Head-to-Head: 1 KB payload ═══`);
const kb = Buffer.alloc(1024);
for (let i = 0; i < 1024; i++) kb[i] = i & 0xff;
const kbEncoded = codec.base64.encode(kb);
const kbStr = kb.toString("base64");
const kbB64js = fromByteArray(kb);
const kbIter = 10_000;

console.log(SEP);
console.log("  Encode:");
bench("zig-codec", () => codec.base64.encode(kb), kbIter);
bench("Buffer.toString", () => kb.toString("base64"), kbIter);
bench("base64-js", () => fromByteArray(kb), kbIter);

console.log(SEP);
console.log("  Decode:");
bench("zig-codec", () => codec.base64.decode(kbEncoded), kbIter);
bench("Buffer.from", () => Buffer.from(kbStr, "base64"), kbIter);
bench("base64-js", () => toByteArray(kbB64js), kbIter);

console.log(SEP);
console.log("  Decode (constant-time):");
bench(
  "zig-codec decodeConst",
  () => codec.base64.decodeConst(kbEncoded),
  kbIter
);

// ── Round 4: Throughput ramp ──

console.log(`\n\n═══ Throughput Ramp (zig-codec vs Buffer) ═══`);

for (const size of [64, 1024, 16384, 131072, 1048576]) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;
  const encoded = codec.base64.encode(data);
  const encodedStr = data.toString("base64");
  const iter = Math.max(100, Math.floor(5_000_000 / size));

  const zigEnc = bench(
    `zig encode ${(size / 1024).toFixed(0)} KB`,
    () => codec.base64.encode(data),
    iter
  );
  const nodeEnc = bench(
    `Buffer.encode ${(size / 1024).toFixed(0)} KB`,
    () => data.toString("base64"),
    iter
  );

  const zigDec = bench(
    `zig decode ${(size / 1024).toFixed(0)} KB`,
    () => codec.base64.decode(encoded),
    iter
  );
  const nodeDec = bench(
    `Buffer.decode ${(size / 1024).toFixed(0)} KB`,
    () => Buffer.from(encodedStr, "base64"),
    iter
  );
}

// ── Summary table ──

const results = [];
for (const size of [64, 1024, 65536]) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;
  const encoded = codec.base64.encode(data);
  const encodedStr = data.toString("base64");
  const iter = Math.max(500, Math.floor(500_000 / size));

  const zE = bench(
    `(internal) zig enc ${size}`,
    () => codec.base64.encode(data),
    iter
  );
  const nE = bench(
    `(internal) node enc ${size}`,
    () => data.toString("base64"),
    iter
  );
  const zD = bench(
    `(internal) zig dec ${size}`,
    () => codec.base64.decode(encoded),
    iter
  );
  const nD = bench(
    `(internal) node dec ${size}`,
    () => Buffer.from(encodedStr, "base64"),
    iter
  );

  results.push({ size, zE, nE, zD, nD });
}

console.log(`\n═══ Summary ═══`);
console.log(
  `  ${"Payload".padStart(10)} | ${"encode (zig)".padStart(12)} ${"encode (buf)".padStart(12)} | ${"decode (zig)".padStart(12)} ${"decode (buf)".padStart(12)} | ${"ratio enc".padStart(9)} ${"ratio dec".padStart(9)}`
);
console.log(
  `  ${"-".repeat(10)}-+-${"-".repeat(12)} ${"-".repeat(12)}-+-${"-".repeat(12)} ${"-".repeat(12)}-+-${"-".repeat(9)} ${"-".repeat(9)}`
);
for (const r of results) {
  const ratioEnc = (r.zE / r.nE).toFixed(2);
  const ratioDec = (r.zD / r.nD).toFixed(2);
  console.log(
    `  ${String(r.size).padStart(10)} | ${fmt(r.zE).padStart(12)} ${fmt(r.nE).padStart(12)} | ${fmt(r.zD).padStart(12)} ${fmt(r.nD).padStart(12)} | ${ratioEnc.padStart(9)}× ${ratioDec.padStart(9)}×`
  );
}

console.log("\n═══ Done ═══");
