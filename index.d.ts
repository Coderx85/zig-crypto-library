export interface Snowflake {
  /** Generate a single Snowflake ID.
   *  Returns a BigInt with embedded timestamp, nodeId, and sequence.
   *  Timestamp is ms since 2026-01-01T00:00:00.000Z. */
  Id(): bigint;

  /** Generate `count` Snowflake IDs.
   *  @param count - Number of IDs to generate (1 ≤ count ≤ 1000)
   *  @throws RangeError if count is out of range */
  Batch(count: number): bigint[];
};
export function snowflakeId(): bigint;
export function snowflakeBatch(count: number): bigint[];

export declare const Snowflake: Snowflake;

declare const nanoid: {
  /** Generate a URL-safe random ID.
   *  @param length Number of characters (1–128, default 21). */
  (length?: number): string;

  /** Generate `count` random IDs.
   *  @param count 1 ≤ count ≤ 1000
   *  @param length Characters per ID (1–128, default 21)
   *  @throws RangeError if count or length out of range */
  Batch(count: number, length?: number): string[];
};

export { nanoid };
