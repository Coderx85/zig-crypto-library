import { nanoid, Snowflake } from "../../index.js";

// Default 21-character ID
console.log('Default ID:', nanoid());

// Custom length
console.log('8-char ID:', nanoid(8));
console.log('32-char ID:', nanoid(32));

// Batch generation
const batch = nanoid.Batch(5);
console.log('\nBatch of 5 IDs:');
batch.forEach((id, i) => console.log(`  ${i + 1}. ${id}`));

// Custom length batch
const shortBatch = nanoid.Batch(3, 8);
console.log('\nBatch of 3 short IDs:');
shortBatch.forEach((id, i) => console.log(`  ${i + 1}. ${id}`));

console.log('\n=== Snowflake examples ===\n');

// Snowflake ID
console.log('Snowflake ID:', Snowflake.Id().toString());

// Snowflake batch
const snowBatch = Snowflake.Batch(3);
console.log('\nSnowflake batch:');
snowBatch.forEach((id, i) => console.log(`  ${i + 1}. ${id.toString()}`));
