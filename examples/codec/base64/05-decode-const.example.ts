import { codec } from "../../../index.js";

const data = Buffer.from("Hello, World!");
const encoded = codec.base64.encode(data);

const decoded = codec.base64.decodeConst(encoded);
console.log("Decoded:", decoded.toString());

const urlEncoded = codec.base64.encode(data, { urlSafe: true });
const urlDecoded = codec.base64.decodeConst(urlEncoded, { urlSafe: true });
console.log("URL-safe roundtrip OK:", data.equals(urlDecoded));

const bin = Buffer.from([0x00, 0xff, 0xfe, 0xfd, 0xde, 0xad]);
const binEncoded = codec.base64.encode(bin);
const binDecoded = codec.base64.decodeConst(binEncoded);
console.log("Binary roundtrip OK:", bin.equals(binDecoded));

try {
  codec.base64.decodeConst(Buffer.from("!!!!"));
  console.log("Should not reach here");
} catch {
  console.log("Invalid chars correctly rejected");
}
