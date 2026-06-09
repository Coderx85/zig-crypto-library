export interface SnowflakeModule {
  Id(): bigint;
  Batch(count: number): bigint[];
}
