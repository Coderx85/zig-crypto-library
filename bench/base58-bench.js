// Benchmark: zig-codec base58 vs bs58 (pure JS)
//
// Usage: node bench/base58-bench.js
// Requires: npm run build (tsc) first

import { codec } from "../dist/index.js";
import bs58 from "bs58";

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
    `  ${label.padEnd(42)} ${fmt(perOp).padStart(12)}  (${iterations.toExponential()} iters)`
  );
  return perOp;
}

const SEP = "  " + "-".repeat(76);

// Payload sizes: Bitcoin P2PKH (25), P2SH/compressed pubkey (33), Solana (64), general (128, 512)
const sizes = [25, 33, 64, 128, 512];
const iter = 2_000;

// ── Round 1: Encode ──

console.log("\n═══ Base58 Encode ═══");

for (const size of sizes) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;

  console.log(`\n--- ${size} bytes ---`);
  const zig = bench(
    "zig-codec base58.encode",
    () => codec.base58.encode(data),
    iter
  );
  const js = bench("bs58.encode", () => bs58.encode(data), iter);

  if (size > 0) {
    const zigMb = size / 1024 / 1024 / (zig / 1e9);
    const jsMb = size / 1024 / 1024 / (js / 1e9);
    console.log(
      `  ${"zig-codec MB/s".padEnd(42)} ${zigMb.toFixed(1).padStart(12)} MB/s`
    );
    console.log(
      `  ${"bs58 MB/s".padEnd(42)} ${jsMb.toFixed(1).padStart(12)} MB/s`
    );
    const ratio = js / zig;
    console.log(
      `  ${"ratio (bs58 / zig)".padEnd(42)} ${ratio.toFixed(2).padStart(12)}×`
    );
  }
}

// ── Round 2: Decode ──

console.log(`\n\n═══ Base58 Decode ═══`);

for (const size of sizes) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;
  const encoded = codec.base58.encode(data);
  const bs58Encoded = bs58.encode(data);

  console.log(`\n--- ${size} bytes ---`);
  const zig = bench(
    "zig-codec base58.decode",
    () => codec.base58.decode(encoded),
    iter
  );
  const js = bench("bs58.decode", () => bs58.decode(bs58Encoded), iter);

  const ratio = js / zig;
  console.log(
    `  ${"ratio (bs58 / zig)".padEnd(42)} ${ratio.toFixed(2).padStart(12)}×`
  );
}

// ── Round 3: Bitcoin P2PKH head-to-head ──

console.log(`\n\n═══ Bitcoin P2PKH (25 bytes) — Head-to-Head ═══`);
const p2pkhData = Buffer.from([
  0x00, 0x6a, 0xe3, 0x5b, 0x5d, 0x13, 0x45, 0x53, 0x2d, 0x27, 0x8e, 0x11, 0x0e,
  0x9a, 0x6c, 0x9c, 0x6a, 0x22, 0xc2, 0x63, 0x10, 0x65, 0xfb, 0x36, 0x16,
]);
const p2pkhIter = 5_000;

console.log(SEP);
console.log("  Encode:");
const zEnc = bench(
  "zig-codec",
  () => codec.base58.encode(p2pkhData),
  p2pkhIter
);
const jEnc = bench("bs58", () => bs58.encode(p2pkhData), p2pkhIter);
console.log(
  `  ${"ratio (bs58 / zig)".padEnd(42)} ${(jEnc / zEnc).toFixed(2).padStart(12)}×`
);

const p2pkhStr = codec.base58.encode(p2pkhData);
const p2pkhBs58Str = bs58.encode(p2pkhData);

console.log(SEP);
console.log("  Decode:");
const zDec = bench("zig-codec", () => codec.base58.decode(p2pkhStr), p2pkhIter);
const jDec = bench("bs58", () => bs58.decode(p2pkhBs58Str), p2pkhIter);
console.log(
  `  ${"ratio (bs58 / zig)".padEnd(42)} ${(jDec / zDec).toFixed(2).padStart(12)}×`
);

// ── Summary ──

console.log(`\n\n═══ Summary ═══`);
const summarySizes = [25, 64, 512];
const summaryResults = [];
for (const size of summarySizes) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;
  const encoded = codec.base58.encode(data);
  const bs58Encoded = bs58.encode(data);

  const zE = bench(
    `(int) zig enc ${size}`,
    () => codec.base58.encode(data),
    iter
  );
  const jE = bench(`(int) bs58 enc ${size}`, () => bs58.encode(data), iter);
  const zD = bench(
    `(int) zig dec ${size}`,
    () => codec.base58.decode(encoded),
    iter
  );
  const jD = bench(
    `(int) bs58 dec ${size}`,
    () => bs58.decode(bs58Encoded),
    iter
  );

  summaryResults.push({ size, zE, jE, zD, jD });
}

console.log(`\n═══ Summary Table ═══`);
console.log(
  `  ${"Payload".padStart(8)} | ${"enc (zig)".padStart(12)} ${"enc (bs58)".padStart(12)} | ${"dec (zig)".padStart(12)} ${"dec (bs58)".padStart(12)} | ${"rat enc".padStart(8)} ${"rat dec".padStart(8)}`
);
console.log(
  `  ${"-".repeat(8)}-+-${"-".repeat(12)} ${"-".repeat(12)}-+-${"-".repeat(12)} ${"-".repeat(12)}-+-${"-".repeat(8)} ${"-".repeat(8)}`
);
for (const r of summaryResults) {
  const ratEnc = (r.zE / r.jE).toFixed(2);
  const ratDec = (r.zD / r.jD).toFixed(2);
  console.log(
    `  ${String(r.size).padStart(8)} | ${fmt(r.zE).padStart(12)} ${fmt(r.jE).padStart(12)} | ${fmt(r.zD).padStart(12)} ${fmt(r.jD).padStart(12)} | ${ratEnc.padStart(8)}× ${ratDec.padStart(8)}×`
  );
}

console.log("\n═══ Done ═══");
