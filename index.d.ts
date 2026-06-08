export interface Snowflake {
  /** Generate a single Snowflake ID.
   *  Returns a BigInt with embedded timestamp, nodeId, and sequence.
   *  Timestamp is ms since 2026-01-01T00:00:00.000Z. */
  Id(): bigint;

  /** Generate `count` Snowflake IDs.
   *  @param count - Number of IDs to generate (1 ≤ count ≤ 1000)
   *  @throws RangeError if count is out of range */
  Batch(count: number): bigint[];
}

export const Snowflake: Snowflake;
