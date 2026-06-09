import gypBuild from "node-gyp-build";
import { resolve } from "node:path";

// ── Native module loader ──────────────────────────────

interface NativeBindings {
  Id(): bigint;
  Batch(count: number): bigint[];
  nanoid(length?: number): string;
  nanoidBatchBuffer(count: number, length?: number): Buffer;
  nanoidBatchStrings(count: number, length?: number): string[];
}

const load: NativeBindings = gypBuild(resolve(__dirname, ".."));

// ── Snowflake ─────────────────────────────────────────

export interface SnowflakeModule {
  Id(): bigint;
  Batch(count: number): bigint[];
}

export const Snowflake: SnowflakeModule = {
  Id: load.Id,
  Batch: load.Batch,
};

// ── Extract helpers (pure JS, no native code) ─────────

const TIMESTAMP_SHIFT = 22n;
const NODE_ID_SHIFT = 12n;
const SEQUENCE_MASK = 0xfffn;
const NODE_ID_MASK = 0x3ffn;

export const EPOCH = 1767225600000;

export function extractSnowflakeTime(id: bigint): number {
  return Number((id >> TIMESTAMP_SHIFT) + BigInt(EPOCH));
}

export function extractSnowflakeNodeId(id: bigint): number {
  return Number((id >> NODE_ID_SHIFT) & NODE_ID_MASK);
}

export function extractSnowflakeSequence(id: bigint): number {
  return Number(id & SEQUENCE_MASK);
}

// ── Nanoid ────────────────────────────────────────────

export const DEFAULT_LENGTH = 21;
export const MAX_LENGTH = 128;
export const MAX_BATCH = 1000;

export interface NanoidFunction {
  (length?: number): string;
  Batch(count: number, length?: number): string[];
  BatchBuffer(count: number, length?: number): Buffer;
}

export const nanoid: NanoidFunction = Object.assign(load.nanoid, {
  Batch: load.nanoidBatchStrings,
  BatchBuffer: load.nanoidBatchBuffer,
});
