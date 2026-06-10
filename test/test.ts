import { nanoid, Snowflake, codec } from "../index.js";

let passed = 0;
let failed = 0;

function assert(condition: boolean, msg: string): void {
  if (condition) {
    passed++;
  } else {
    console.error("FAIL:", msg);
    failed++;
  }
}

function assertThrows(fn: () => void, msg: string): void {
  try {
    fn();
    console.error("FAIL:", msg, "- expected throw");
    failed++;
  } catch {
    passed++;
  }
}

// ── Module shape ──────────────────────────────────────
assert(typeof nanoid === "function", "nanoid is a function");
assert(typeof nanoid.Batch === "function", "nanoid.Batch is a function");
assert(typeof Snowflake === "object", "Snowflake is still exported");
assert(typeof Snowflake.Id === "function", "Snowflake.Id still works");

// ── nanoid() returns string ──────────────────────────
const id = nanoid();
assert(typeof id === "string", "nanoid() returns string");
assert(id.length === 21, "nanoid() default length is 21, got " + id.length);

// ── nanoid(32) respects length ───────────────────────
const id32 = nanoid(32);
assert(id32.length === 32, "nanoid(32) length is 32, got " + id32.length);

// ── nanoid(1) minimum length ─────────────────────────
const id1 = nanoid(1);
assert(id1.length === 1, "nanoid(1) length is 1");

// ── nanoid(128) maximum length ───────────────────────
const id128 = nanoid(128);
assert(id128.length === 128, "nanoid(128) length is 128");

// ── URL-safe characters ──────────────────────────────
const urlSafeRegex = /^[A-Za-z0-9_-]+$/;
assert(urlSafeRegex.test(id), "nanoid() is URL-safe");
assert(urlSafeRegex.test(id32), "nanoid(32) is URL-safe");
assert(urlSafeRegex.test(id128), "nanoid(128) is URL-safe");

// ── Uniqueness (100 IDs) ─────────────────────────────
const seen = new Set<string>();
for (let i = 0; i < 100; i++) {
  const uid = nanoid();
  assert(!seen.has(uid), "nanoid() unique at iteration " + i);
  seen.add(uid);
}

// ── nanoid.Batch(10) ─────────────────────────────────
const batch10 = nanoid.Batch(10);
assert(Array.isArray(batch10), "Batch(10) is array");
assert(batch10.length === 10, "Batch(10) length is 10");
for (const b of batch10) {
  assert(typeof b === "string", "Batch elements are strings");
  assert(b.length === 21, "Batch elements default length 21");
  assert(urlSafeRegex.test(b), "Batch elements are URL-safe");
}

// ── nanoid.Batch(10, 16) custom length ───────────────
const batch16 = nanoid.Batch(10, 16);
assert(batch16.length === 10, "Batch(10, 16) length is 10");
for (const b of batch16) {
  assert(b.length === 16, "Batch(10, 16) elements have length 16");
}

// ── Batch uniqueness ─────────────────────────────────
const batchSeen = new Set<string>();
for (const b of batch10) {
  assert(!batchSeen.has(b), "Batch elements are unique");
  batchSeen.add(b);
}

// ── Batch(1000) works ────────────────────────────────
const batch1000 = nanoid.Batch(1000);
assert(batch1000.length === 1000, "Batch(1000) length is 1000");

// ── nanoid.BatchBuffer ───────────────────────────────
const bb10 = nanoid.BatchBuffer(10);
assert(Buffer.isBuffer(bb10), "BatchBuffer(10) returns Buffer");
assert(bb10.length === 210, "BatchBuffer(10) length is 210 (10×21)");

const bb16 = nanoid.BatchBuffer(10, 16);
assert(bb16.length === 160, "BatchBuffer(10,16) length is 160");

// Decode strings from BatchBuffer
for (let i = 0; i < 10; i++) {
  const s = bb10.toString("utf-8", i * 21, (i + 1) * 21);
  assert(s.length === 21, `BatchBuffer decoded string ${i} length 21`);
  assert(urlSafeRegex.test(s), `BatchBuffer decoded string ${i} URL-safe`);
}

// BatchBuffer uniqueness
const bbSeen = new Set<string>();
for (let i = 0; i < 10; i++) {
  const s = bb10.toString("utf-8", i * 21, (i + 1) * 21);
  assert(!bbSeen.has(s), "BatchBuffer elements are unique");
  bbSeen.add(s);
}

// ── Error cases ──────────────────────────────────────
assertThrows(() => nanoid(0), "nanoid(0) throws");
assertThrows(() => nanoid(-1), "nanoid(-1) throws");
assertThrows(() => nanoid(129), "nanoid(129) throws");
assertThrows(() => nanoid.Batch(0), "Batch(0) throws");
assertThrows(() => nanoid.Batch(-1), "Batch(-1) throws");
assertThrows(() => nanoid.Batch(1001), "Batch(1001) throws");

// ── Snowflake still works ────────────────────────────
const snowId = Snowflake.Id();
assert(typeof snowId === "bigint", "Snowflake.Id() still returns bigint");
assert(snowId > 0n, "Snowflake.Id() returns positive bigint");

const snowBatch = Snowflake.Batch(5);
assert(Array.isArray(snowBatch), "Snowflake.Batch(5) is array");
assert(snowBatch.length === 5, "Snowflake.Batch(5) length is 5");

// ── Codec: base64 encode/decode ──────────────────────
assert(typeof codec === "object", "codec is exported");
assert(typeof codec.base64 === "object", "codec.base64 is exported");
assert(
  typeof codec.base64.encode === "function",
  "codec.base64.encode is a function"
);
assert(
  typeof codec.base64.decode === "function",
  "codec.base64.decode is a function"
);

const helloBuf = Buffer.from("Hello, World!");
const encoded = codec.base64.encode(helloBuf);
assert(typeof encoded === "string", "base64.encode returns string");
assert(
  encoded === "SGVsbG8sIFdvcmxkIQ==",
  "base64.encode standard matches expected"
);

const decoded = codec.base64.decode(encoded);
assert(Buffer.isBuffer(decoded), "base64.decode returns Buffer");
assert(
  decoded.toString() === "Hello, World!",
  "base64.decode roundtrip matches original"
);

// URL-safe variant
const urlEncoded = codec.base64.encode(helloBuf, { urlSafe: true });
assert(typeof urlEncoded === "string", "base64.encode urlSafe returns string");
assert(
  urlEncoded === "SGVsbG8sIFdvcmxkIQ==",
  "base64.encode urlSafe matches expected (same for ascii)"
);

const urlDecoded = codec.base64.decode(urlEncoded, { urlSafe: true });
assert(
  urlDecoded.toString() === "Hello, World!",
  "base64.decode urlSafe roundtrip"
);

// Binary data roundtrip
const binData = Buffer.from([0x00, 0x01, 0x02, 0xff, 0xfe, 0xfd]);
const binEncoded = codec.base64.encode(binData);
const binDecoded = codec.base64.decode(binEncoded);
assert(binDecoded.equals(binData), "binary data roundtrips through base64");

// Empty input roundtrip
const emptyEncoded = codec.base64.encode(Buffer.alloc(0));
assert(emptyEncoded.length === 0, "empty encode produces empty output");
const emptyDecoded = codec.base64.decode(Buffer.alloc(0));
assert(emptyDecoded.length === 0, "empty decode produces empty output");

// Single byte
const singleEnc = codec.base64.encode(Buffer.from("M"));
assert(singleEnc === "TQ==", "single byte encode is 'TQ=='");

// Two bytes
const twoEnc = codec.base64.encode(Buffer.from("Ma"));
assert(twoEnc === "TWE=", "two byte encode is 'TWE='");

// URL-safe binary (bytes that differ between alphabets)
const specialBin = Buffer.from([0xff, 0xfb, 0xfc]);
const stdEnc = codec.base64.encode(specialBin);
const safeEnc = codec.base64.encode(specialBin, { urlSafe: true });
assert(stdEnc === "//v8", "standard encode uses +/ chars");
assert(safeEnc === "__v8", "urlSafe encode uses -_ chars");

// ── Codec: decodeConst (constant-time) ────────────────
assert(
  typeof codec.base64.decodeConst === "function",
  "codec.base64.decodeConst is a function"
);

const ctDecoded = codec.base64.decodeConst(encoded);
assert(Buffer.isBuffer(ctDecoded), "decodeConst returns Buffer");
assert(
  ctDecoded.toString() === "Hello, World!",
  "decodeConst roundtrip matches original"
);
assert(decoded.equals(ctDecoded), "decodeConst matches decode output");

const ctUrlDecoded = codec.base64.decodeConst(urlEncoded, { urlSafe: true });
assert(
  ctUrlDecoded.toString() === "Hello, World!",
  "decodeConst urlSafe roundtrip"
);

const ctBinDecoded = codec.base64.decodeConst(binEncoded);
assert(ctBinDecoded.equals(binData), "decodeConst binary roundtrip");

// decodeConst rejects invalid chars
assertThrows(
  () => codec.base64.decodeConst(Buffer.from("!!!!")),
  "decodeConst rejects invalid chars"
);
assertThrows(
  () => codec.base64.decodeConst(Buffer.from("//v8"), { urlSafe: true }),
  "decodeConst urlSafe rejects +/ chars"
);

// ── Codec: base58 encode/decode ─────────────────────
assert(typeof codec.base58 === "object", "codec.base58 is exported");
assert(
  typeof codec.base58.encode === "function",
  "codec.base58.encode is a function"
);
assert(
  typeof codec.base58.decode === "function",
  "codec.base58.decode is a function"
);

const b58alpha = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

// Roundtrip "Hello, World!"
const hello58 = Buffer.from("Hello, World!");
const enc58 = codec.base58.encode(hello58);
assert(typeof enc58 === "string", "base58.encode returns string");
const dec58 = codec.base58.decode(enc58);
assert(Buffer.isBuffer(dec58), "base58.decode returns Buffer");
assert(dec58.equals(hello58), "base58 roundtrip matches original: " + enc58);

// All output characters belong to base58 alphabet
for (const ch of enc58) {
  assert(b58alpha.includes(ch), `base58 char '${ch}' is in alphabet`);
}

// Empty input
const emptyEnc58 = codec.base58.encode(Buffer.alloc(0));
assert(emptyEnc58 === "", "base58.empty encode produces empty string");
const emptyDec58 = codec.base58.decode("");
assert(emptyDec58.length === 0, "base58.empty decode produces empty buffer");

// Single byte: 0x00 → "1"
const zeroEnc = codec.base58.encode(Buffer.from([0x00]));
assert(zeroEnc === "1", "base58.encode 0x00 is '1'");
const zeroDec = codec.base58.decode("1");
assert(zeroDec.length === 1 && zeroDec[0] === 0, "base58.decode '1' is 0x00");

// Single byte: 0xFF → "5Q"
const ffEnc = codec.base58.encode(Buffer.from([0xff]));
assert(ffEnc === "5Q", "base58.encode 0xFF is '5Q'");

// Leading zero preserved
const leadEnc = codec.base58.encode(Buffer.from([0x00, 0x00, 0x01]));
assert(leadEnc.startsWith("11"), "base58 leading zeros encoded as '11'");

// Binary roundtrip (DEADBEEF)
const beef = Buffer.from([0xde, 0xad, 0xbe, 0xef]);
const beefEnc = codec.base58.encode(beef);
assert(typeof beefEnc === "string", "base58.encode binary returns string");
const beefDec = codec.base58.decode(beefEnc);
assert(beefDec.equals(beef), "base58 DEADBEEF roundtrip");

// Multi-byte roundtrip (CAFEBABE)
const cafe = Buffer.from([0xca, 0xfe, 0xba, 0xbe]);
assert(
  codec.base58.decode(codec.base58.encode(cafe)).equals(cafe),
  "base58 CAFEBABE roundtrip"
);

// Invalid char rejection
assertThrows(
  () => codec.base58.decode("0OIl!@#$%"),
  "base58.decode rejects invalid chars (0/O/I/l/special)"
);
assertThrows(() => codec.base58.decode("hello0"), "base58.decode rejects '0'");
assertThrows(
  () => codec.base58.decode("helLo"),
  "base58.decode rejects 'O' and 'l'"
);

// ── Summary ──────────────────────────────────────────
console.log(
  `\n${passed} passed, ${failed} failed${failed > 0 ? " *** FAIL ***" : ""}`
);
process.exit(failed > 0 ? 1 : 0);
