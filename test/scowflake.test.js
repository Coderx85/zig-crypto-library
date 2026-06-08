const { Snowflake } = require('../index.js');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) {
    passed++;
  } else {
    console.error('FAIL:', msg);
    failed++;
  }
}

function assertThrows(fn, expectedMsg, msg) {
  try {
    fn();
    console.error('FAIL:', msg, '- expected throw');
    failed++;
  } catch (e) {
    if (e.message.includes(expectedMsg)) {
      passed++;
    } else {
      console.error('FAIL:', msg, '- wrong message:', e.message);
      failed++;
    }
  }
}

// Module shape
assert(typeof Snowflake === 'object', 'Snowflake is object');
assert(typeof Snowflake.Id === 'function', 'Snowflake.Id is function');
assert(typeof Snowflake.Batch === 'function', 'Snowflake.Batch is function');

// Id() returns bigint
const id = Snowflake.Id();
assert(typeof id === 'bigint', 'Id() returns bigint');
assert(id > 0n, 'Id() returns positive bigint');

// Uniqueness (100)
const seen = new Set();
for (let i = 0; i < 100; i++) {
  const tid = Snowflake.Id();
  assert(!seen.has(tid), 'Id() unique at iteration ' + i);
  seen.add(tid);
}

// Monotonicity (100)
let prev = Snowflake.Id();
for (let i = 0; i < 100; i++) {
  const tid = Snowflake.Id();
  assert(tid > prev, 'Id() monotonic at iteration ' + i);
  prev = tid;
}

// Batch(10) returns correct type and length
const batch10 = Snowflake.Batch(10);
assert(Array.isArray(batch10), 'Batch(10) is array');
assert(batch10.length === 10, 'Batch(10) length is 10');
for (const b of batch10) {
  assert(typeof b === 'bigint', 'Batch(10) elements are bigint');
}

// Batch uniqueness
const batchSeen = new Set();
for (const b of batch10) {
  assert(!batchSeen.has(b), 'Batch elements are unique');
  batchSeen.add(b);
}

// Batch joins main sequence (no overlap with previously generated)
for (const b of batch10) {
  assert(!seen.has(b), 'Batch elements not overlapping with previous Ids');
}

// Batch(1000) works
const batch1000 = Snowflake.Batch(1000);
assert(batch1000.length === 1000, 'Batch(1000) length is 1000');

// Batch(0) throws
assertThrows(() => Snowflake.Batch(0), 'count must be >= 1', 'Batch(0) throws');

// Batch(-1) throws
assertThrows(() => Snowflake.Batch(-1), 'count must be >= 1', 'Batch(-1) throws');

// Batch(1001) throws
assertThrows(() => Snowflake.Batch(1001), 'count must be <= 1000', 'Batch(1001) throws');

// Summary
console.log(`\n${passed} passed, ${failed} failed${failed > 0 ? ' *** FAIL ***' : ''}`);
process.exit(failed > 0 ? 1 : 0);
