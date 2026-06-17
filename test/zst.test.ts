import { zst } from "../index.js";

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

function assertThrows(fn: () => void, expectedMsg: string, msg: string): void {
  try {
    fn();
    console.error("FAIL:", msg, "- expected throw");
    failed++;
  } catch (e) {
    if (e instanceof Error && e.message.includes(expectedMsg)) {
      passed++;
    } else {
      console.error(
        "FAIL:",
        msg,
        "- wrong message:",
        e instanceof Error ? e.message : e
      );
      failed++;
    }
  }
}

assert(typeof zst === "object", "zst is object");
assert(typeof zst.sign === "function", "zst.sign is function");
assert(typeof zst.verify === "function", "zst.verify is function");
assert(typeof zst.decode === "function", "zst.decode is function");
assert(typeof zst.generateKey === "function", "zst.generateKey is function");

assertThrows(
  () => zst.generateKey(0),
  "Key length must be >= 32",
  "generateKey(0) throws"
);
assertThrows(
  () => zst.generateKey(16),
  "Key length must be >= 32",
  "generateKey(16) throws"
);
assertThrows(
  () => zst.generateKey(31),
  "Key length must be >= 32",
  "generateKey(31) throws"
);

const key = zst.generateKey(32);
assert(key.length === 32, "generateKey(32) returns 32 bytes");

const key64 = zst.generateKey(64);
assert(key64.length === 64, "generateKey(64) returns 64 bytes");

const key128 = zst.generateKey(128);
assert(key128.length === 128, "generateKey(128) returns 128 bytes");

const payload =
  '{"sub":"user_123","aud":"api.example.com","exp":9999999999,"rev":1}';
const token = zst.sign(payload, key);
assert(typeof token === "string", "sign returns string");
assert(token.startsWith("zst_v1.local."), "token has correct prefix");

let dotCount = 0;
for (const c of token) {
  if (c === ".") dotCount++;
}
assert(dotCount === 5, "token has 5 dots (header.nonce.ciphertext.tag)");

const result = zst.verify(token, key);
assert(typeof result === "object", "verify returns object");
assert(result.sub === "user_123", "verify returns correct sub");
assert(result.aud === "api.example.com", "verify returns correct aud");
assert(result.rev === 1, "verify returns correct rev");

const decoded = zst.decode(token);
assert(decoded.ver === "1", "decode returns correct ver");
assert(decoded.typ === "ZST", "decode returns correct typ");
assert(decoded.mode === "local", "decode returns correct mode");
assert(decoded.encrypted === true, "decode returns encrypted true");

const payloadWithOptions =
  '{"sub":"user_456","aud":"api.example.com","exp":9999999999,"rev":5}';
const tokenWithOptions = zst.sign(payloadWithOptions, key, {
  audience: "api.example.com",
  issuer: "auth.example.com",
  subject: "user_456",
});

const resultWithOptions = zst.verify(tokenWithOptions, key, {
  audience: "api.example.com",
  issuer: "auth.example.com",
  subject: "user_456",
  currentRev: 3,
  clockTolerance: 30,
  clockTimestamp: 1700000000,
  ignoreExpiration: true,
  ignoreNotBefore: true,
});
assert(
  resultWithOptions.sub === "user_456",
  "verify with options returns correct sub"
);

assertThrows(
  () => zst.verify(token, Buffer.alloc(16, 0x42)),
  "KeyTooShort",
  "verify with short key throws"
);

assertThrows(
  () => zst.verify("not.a.valid.token", key),
  "MalformedToken",
  "verify with malformed token throws"
);

const expiredPayload =
  '{"sub":"user_123","aud":"api.example.com","exp":1000000000,"rev":1}';
const signedExpiredToken = zst.sign(expiredPayload, key);
assertThrows(
  () => zst.verify(signedExpiredToken, key, { clockTimestamp: 2000000000 }),
  "Expired",
  "verify rejects expired token"
);

const revokedPayload =
  '{"sub":"user_123","aud":"api.example.com","exp":9999999999,"rev":1}';
const signedRevokedToken = zst.sign(revokedPayload, key);
assertThrows(
  () =>
    zst.verify(signedRevokedToken, key, {
      currentRev: 5,
      clockTimestamp: 1700000000,
    }),
  "Revoked",
  "verify rejects revoked token"
);

console.log(
  `\n${passed} passed, ${failed} failed${failed > 0 ? " *** FAIL ***" : ""}`
);
process.exit(failed > 0 ? 1 : 0);
