import { Snowflake } from "../../index.js";

const id = Snowflake.Id();
console.log("Single ID:", id.toString());

const a = Snowflake.Id();
const b = Snowflake.Id();
console.log("Monotonic:", a < b);

const batch = Snowflake.Batch(10);
console.log("Batch of 10:", batch.map(String).join(", "));

const big = Snowflake.Batch(1000);
console.log("Batch of 1000: length =", big.length);
