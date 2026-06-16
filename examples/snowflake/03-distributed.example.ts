import { Snowflake } from "../../index.js";

function extractTimestamp(id: bigint): number {
  const CUSTOM_EPOCH = 1_767_225_600_000;
  return CUSTOM_EPOCH + Number(id >> 22n);
}

function extractNodeId(id: bigint): number {
  return Number((id >> 12n) & 0x3ffn);
}

const ids = Snowflake.Batch(300);
const fromMachine = new Map<number, bigint[]>();

for (const id of ids) {
  const nodeId = extractNodeId(id);
  if (!fromMachine.has(nodeId)) fromMachine.set(nodeId, []);
  fromMachine.get(nodeId)!.push(id);
}

console.log("Machines that generated IDs:");
for (const [nodeId, nodeIds] of fromMachine) {
  const first = nodeIds[0];
  console.log(
    `  nodeId ${nodeId.toString().padStart(4)}: ${nodeIds.length} IDs, ` +
      `range [${first.toString()}, ${nodeIds[nodeIds.length - 1].toString()}] ` +
      `at ${new Date(extractTimestamp(first)).toISOString()}`
  );
}
