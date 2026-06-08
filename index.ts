import gypBuild from "node-gyp-build";
import { resolve } from "node:path";

interface NativeBindings {
  Id(): bigint;
  Batch(count: number): bigint[];
  nanoid(length?: number): string;
  nanoidBatchBuffer(count: number, length?: number): Buffer;
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
      const buf = load.nanoidBatchBuffer(count, length);
      const len = length ?? 21;
      const ids = new Array<string>(count);
      for (let i = 0; i < count; i++) {
        ids[i] = buf.toString("utf-8", i * len, (i + 1) * len);
      }
      return ids;
    },
    BatchBuffer(count: number, length?: number): Buffer {
      return load.nanoidBatchBuffer(count, length);
    },
  },
);
