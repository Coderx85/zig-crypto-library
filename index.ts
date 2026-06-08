import gypBuild from "node-gyp-build";
import { resolve } from "node:path";

interface NativeBindings {
  Id(): bigint;
  Batch(count: number): bigint[];
  nanoid(length?: number): string;
  nanoidBatchBuffer(count: number, length?: number): Buffer;
  nanoidBatchStrings(count: number, length?: number): string[];
}

const load: NativeBindings = gypBuild(resolve(__dirname, ".."));

export interface SnowflakeModule {
  Id(): bigint;
  Batch(count: number): bigint[];
}

export const Snowflake: SnowflakeModule = {
  Id: load.Id,
  Batch: load.Batch,
};

export interface NanoidFunction {
  (length?: number): string;
  Batch(count: number, length?: number): string[];
  BatchBuffer(count: number, length?: number): Buffer;
}

export const nanoid: NanoidFunction = Object.assign(
  function nanoid(length?: number): string {
    return load.nanoid(length);
  },
  {
    Batch(count: number, length?: number): string[] {
      return load.nanoidBatchStrings(count, length);
    },
    BatchBuffer(count: number, length?: number): Buffer {
      return load.nanoidBatchBuffer(count, length);
    },
  }
);
