import { codec } from "../../../index.js";

function fmt(ns: number): string {
  if (ns >= 1_000_000) return (ns / 1_000_000).toFixed(2) + " ms";
  if (ns >= 1_000) return (ns / 1_000).toFixed(2) + " µs";
  return ns.toFixed(0) + " ns";
}

function bench(label: string, fn: () => void, iterations: number): number {
  // warmup
  for (let i = 0; i < 100; i++) fn();

  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) fn();
  const end = process.hrtime.bigint();

  const total_ns = Number(end - start);
  const per_op = total_ns / iterations;
  console.log(`  ${label}: ${fmt(per_op)} / op (${iterations} iters)`);
  return per_op;
}

// Data sizes to test
const sizes = [16, 64, 256, 1024, 4096];
const iterations = 10_000;

for (const size of sizes) {
  const data = Buffer.alloc(size);
  for (let i = 0; i < size; i++) data[i] = i & 0xff;

  console.log(`\n--- ${size} bytes ---`);
  let enc: Buffer;

  bench(
    "encode",
    () => {
      enc = codec.base64.encode(data);
    },
    iterations
  );

  enc = codec.base64.encode(data);

  bench(
    "decode",
    () => {
      codec.base64.decode(enc);
    },
    iterations
  );
}

// Compare with Node.js built-in Buffer base64
console.log("\n--- Native vs Buffer (1 KB) ---");
const kb = Buffer.alloc(1024);
for (let i = 0; i < 1024; i++) kb[i] = i & 0xff;

bench("zig-codec encode", () => codec.base64.encode(kb), iterations);
bench("Buffer.toString('base64')", () => kb.toString("base64"), iterations);

const b64 = codec.base64.encode(kb);
const b64str = kb.toString("base64");
bench("zig-codec decode", () => codec.base64.decode(b64), iterations);
bench("Buffer.from(base64)", () => Buffer.from(b64str, "base64"), iterations);
