import { Snowflake } from "../../index.js";

const CUSTOM_EPOCH = 1_767_225_600_000;

function extractTimestamp(id: bigint): number {
  const timestampOffset = Number(id >> 22n);
  return CUSTOM_EPOCH + timestampOffset;
}

function extractNodeId(id: bigint): number {
  return Number((id >> 12n) & 0x3ffn);
}

function extractSequence(id: bigint): number {
  return Number(id & 0xfffn);
}

const id = Snowflake.Id();

console.log("ID:", id.toString());
console.log("  Timestamp:", new Date(extractTimestamp(id)).toISOString());
console.log("  NodeId:    ", extractNodeId(id));
console.log("  Sequence:  ", extractSequence(id));
