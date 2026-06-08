import { Snowflake } from "../index";

// Snowflake ID bit layout (64 bits total):
//
//   1 bit  |  41 bits          |  10 bits   |  12 bits
//   (unused) | timestamp offset |  nodeId    |  sequence
//
// Timestamp is milliseconds since 2026-01-01T00:00:00.000Z
// NodeId is 0–1023, auto-derived from hostname
// Sequence is 0–4095, resets each millisecond

const CUSTOM_EPOCH = 1_767_225_600_000; // 2026-01-01T00:00:00.000Z

function extractTimestamp(id: bigint): number {
  // Right-shift by 22 to drop nodeId + sequence bits
  const timestampOffset = Number(id >> 22n);
  return CUSTOM_EPOCH + timestampOffset;
}

function extractNodeId(id: bigint): number {
  // Mask away timestamp (upper 42 bits), shift right by 12
  return Number((id >> 12n) & 0x3FFn);
}

function extractSequence(id: bigint): number {
  // Mask lowest 12 bits
  return Number(id & 0xFFFn);
}

const id = Snowflake.Id();

console.log("ID:", id.toString());
console.log("  Timestamp:", new Date(extractTimestamp(id)).toISOString());
console.log("  NodeId:    ", extractNodeId(id));
console.log("  Sequence:  ", extractSequence(id));
