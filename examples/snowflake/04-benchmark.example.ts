import { Snowflake } from "../index";

// Measure raw throughput of single ID generation
function benchSingle(count: number): void {
  const start = process.hrtime.bigint();
  for (let i = 0; i < count; i++) {
    Snowflake.Id();
  }
  const elapsed = Number(process.hrtime.bigint() - start) / 1e3;
  console.log(
    `${count} single Id() calls:  ${elapsed.toFixed(0)}µs ` +
    `(${(count / elapsed * 1e6).toFixed(0)} IDs/sec)`
  );
}

// Measure batch throughput
function benchBatch(count: number, batchSize: number): void {
  const iterations = Math.floor(count / batchSize);
  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) {
    Snowflake.Batch(batchSize);
  }
  const elapsed = Number(process.hrtime.bigint() - start) / 1e3;
  const totalIds = iterations * batchSize;
  console.log(
    `${iterations} Batch(${batchSize}) calls: ${elapsed.toFixed(0)}µs ` +
    `(${(totalIds / elapsed * 1e6).toFixed(0)} IDs/sec)`
  );
}

console.log("Warmup...");
Snowflake.Batch(1000);

console.log("\n--- Single ID throughput ---");
benchSingle(1000);
benchSingle(10000);

console.log("\n--- Batch throughput ---");
benchBatch(1000, 10);
benchBatch(1000, 100);
benchBatch(10000, 1000);
