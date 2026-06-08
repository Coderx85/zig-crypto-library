import { Snowflake, snowflakeBatch, snowflakeId } from "@";

// Generate a single Snowflake ID
const id = snowflakeId();
console.log("Single ID:", id.toString());
// → e.g. "57406623190478848n"

// IDs are 64-bit BigInts, strictly increasing
const a = snowflakeId();
const b = snowflakeId();
console.log("Monotonic:", a < b);
// → true

// Generate a batch in one native call (avoids JS↔native overhead per ID)
const batch = snowflakeBatch(10);
console.log("Batch of 10:", batch.map(String).join(", "));
// → e.g. "57406623194673152, 57406623194673153, ..."

// Batch is capped at 1000
const big = snowflakeBatch(1000);
console.log("Batch of 1000: length =", big.length);
// → 1000
