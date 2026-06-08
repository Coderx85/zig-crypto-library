import { nanoid as ZigNanoId } from "../../index.js";
import { nanoid as JsNanoId } from "nanoid";

function nano(name: string, fn: () => void, iterations: number): void {
  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) fn();
  const elapsed = Number(process.hrtime.bigint() - start);
  const avg = (elapsed / iterations).toFixed(2);
  const thru = ((iterations / elapsed) * 1e9).toFixed(0);
  console.log(
    `  ${name.padEnd(50)} ${avg.padStart(10)} ns/op  ${thru.padStart(12)} ops/sec`
  );
}

const ITER = 100_000;
const BATCH_ITER = 10_000;
const BATCH_SIZE = 100;

console.log("=== Single nanoid (default length 21) ===\n");

nano("[zig-crypto] nanoid()", () => ZigNanoId(), ITER);
nano("[npm]       nanoid()", () => JsNanoId(), ITER);

console.log("\n=== Single nanoid (length 8) ===\n");

nano("[zig-crypto] nanoid(8)", () => ZigNanoId(8), ITER);
nano("[npm]       nanoid(8)", () => JsNanoId(8), ITER);

console.log("\n=== Single nanoid (length 128) ===\n");

nano("[zig-crypto] nanoid(128)", () => ZigNanoId(128), ITER);
nano("[npm]       nanoid(128)", () => JsNanoId(128), ITER);

console.log("\n=== Batch (100 IDs per call) ===\n");

nano("[zig-crypto] Batch(100)", () => ZigNanoId.Batch(BATCH_SIZE), BATCH_ITER);
nano(
  "[npm]       Array.from nanoid ×100",
  () => Array.from({ length: BATCH_SIZE }, () => JsNanoId()),
  BATCH_ITER
);

console.log("\n=== BatchBuffer (100 IDs, zero-copy) ===\n");

nano(
  "[zig-crypto] BatchBuffer(100)",
  () => ZigNanoId.BatchBuffer(BATCH_SIZE),
  BATCH_ITER
);

console.log("\n--- Summary ---");
