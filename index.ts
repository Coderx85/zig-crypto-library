import gypBuild from "node-gyp-build";
import { resolve } from "node:path";
import type { NanoidFunction } from "./types/nanoid.types";
import type { SnowflakeModule } from "./types/snowflake.types";
import type { NativeBindings } from "./types/native.types";

// ── Native module loader ──────────────────────────────

const load: NativeBindings = gypBuild(resolve(__dirname, ".."));

// ── Snowflake ─────────────────────────────────────────

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

export const nanoid: NanoidFunction = Object.assign(load.nanoid, {
  Batch: load.nanoidBatchStrings,
  BatchBuffer: load.nanoidBatchBuffer,
});

// ── Type re-exports ───────────────────────────────────

export type { NanoidFunction, SnowflakeModule, NativeBindings };
