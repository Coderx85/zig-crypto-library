import { nanoid, Snowflake } from "../index.js";

let passed = 0;
let failed = 0;

function assert(condition: boolean, msg: string): void {
  if (condition) {
    passed++;
  } else {
    console.error("FAIL:", msg);
    failed++;
  }
}

function assertThrows(fn: () => void, msg: string): void {
  try {
    fn();
    console.error("FAIL:", msg, "- expected throw");
    failed++;
  } catch {
    passed++;
  }
}

// ── Module shape ──────────────────────────────────────
assert(typeof nanoid === "function", "nanoid is a function");
assert(typeof nanoid.Batch === "function", "nanoid.Batch is a function");
assert(typeof Snowflake === "object", "Snowflake is still exported");
assert(typeof Snowflake.Id === "function", "Snowflake.Id still works");

// ── nanoid() returns string ──────────────────────────
const id = nanoid();
assert(typeof id === "string", "nanoid() returns string");
assert(id.length === 21, "nanoid() default length is 21, got " + id.length);

// ── nanoid(32) respects length ───────────────────────
const id32 = nanoid(32);
assert(id32.length === 32, "nanoid(32) length is 32, got " + id32.length);

// ── nanoid(1) minimum length ─────────────────────────
const id1 = nanoid(1);
assert(id1.length === 1, "nanoid(1) length is 1");

// ── nanoid(128) maximum length ───────────────────────
const id128 = nanoid(128);
assert(id128.length === 128, "nanoid(128) length is 128");

// ── URL-safe characters ──────────────────────────────
const urlSafeRegex = /^[A-Za-z0-9_-]+$/;
assert(urlSafeRegex.test(id), "nanoid() is URL-safe");
assert(urlSafeRegex.test(id32), "nanoid(32) is URL-safe");
assert(urlSafeRegex.test(id128), "nanoid(128) is URL-safe");

// ── Uniqueness (100 IDs) ─────────────────────────────
const seen = new Set<string>();
for (let i = 0; i < 100; i++) {
  const uid = nanoid();
  assert(!seen.has(uid), "nanoid() unique at iteration " + i);
  seen.add(uid);
}

// ── nanoid.Batch(10) ─────────────────────────────────
const batch10 = nanoid.Batch(10);
assert(Array.isArray(batch10), "Batch(10) is array");
assert(batch10.length === 10, "Batch(10) length is 10");
for (const b of batch10) {
  assert(typeof b === "string", "Batch elements are strings");
  assert(b.length === 21, "Batch elements default length 21");
  assert(urlSafeRegex.test(b), "Batch elements are URL-safe");
}

// ── nanoid.Batch(10, 16) custom length ───────────────
const batch16 = nanoid.Batch(10, 16);
assert(batch16.length === 10, "Batch(10, 16) length is 10");
for (const b of batch16) {
  assert(b.length === 16, "Batch(10, 16) elements have length 16");
}

// ── Batch uniqueness ─────────────────────────────────
const batchSeen = new Set<string>();
for (const b of batch10) {
  assert(!batchSeen.has(b), "Batch elements are unique");
  batchSeen.add(b);
}

// ── Batch(1000) works ────────────────────────────────
const batch1000 = nanoid.Batch(1000);
assert(batch1000.length === 1000, "Batch(1000) length is 1000");

// ── nanoid.BatchBuffer ───────────────────────────────
const bb10 = nanoid.BatchBuffer(10);
assert(Buffer.isBuffer(bb10), "BatchBuffer(10) returns Buffer");
assert(bb10.length === 210, "BatchBuffer(10) length is 210 (10×21)");

const bb16 = nanoid.BatchBuffer(10, 16);
assert(bb16.length === 160, "BatchBuffer(10,16) length is 160");

// Decode strings from BatchBuffer
for (let i = 0; i < 10; i++) {
  const s = bb10.toString("utf-8", i * 21, (i + 1) * 21);
  assert(s.length === 21, `BatchBuffer decoded string ${i} length 21`);
  assert(urlSafeRegex.test(s), `BatchBuffer decoded string ${i} URL-safe`);
}

// BatchBuffer uniqueness
const bbSeen = new Set<string>();
for (let i = 0; i < 10; i++) {
  const s = bb10.toString("utf-8", i * 21, (i + 1) * 21);
  assert(!bbSeen.has(s), "BatchBuffer elements are unique");
  bbSeen.add(s);
}

// ── Error cases ──────────────────────────────────────
assertThrows(() => nanoid(0), "nanoid(0) throws");
assertThrows(() => nanoid(-1), "nanoid(-1) throws");
assertThrows(() => nanoid(129), "nanoid(129) throws");
assertThrows(() => nanoid.Batch(0), "Batch(0) throws");
assertThrows(() => nanoid.Batch(-1), "Batch(-1) throws");
assertThrows(() => nanoid.Batch(1001), "Batch(1001) throws");

// ── Snowflake still works ────────────────────────────
const snowId = Snowflake.Id();
assert(typeof snowId === "bigint", "Snowflake.Id() still returns bigint");
assert(snowId > 0n, "Snowflake.Id() returns positive bigint");

const snowBatch = Snowflake.Batch(5);
assert(Array.isArray(snowBatch), "Snowflake.Batch(5) is array");
assert(snowBatch.length === 5, "Snowflake.Batch(5) length is 5");

// ── Summary ──────────────────────────────────────────
console.log(
  `\n${passed} passed, ${failed} failed${failed > 0 ? " *** FAIL ***" : ""}`,
);
process.exit(failed > 0 ? 1 : 0);
