import { codec } from "../../../index.js";

const data = Buffer.from([0xff, 0xfb, 0xfc]);

const standard = codec.base64.encode(data);
console.log("Standard:", standard.toString());

const urlSafe = codec.base64.encode(data, { urlSafe: true });
console.log("URL-safe:", urlSafe.toString());

const decoded = codec.base64.decode(urlSafe, { urlSafe: true });
console.log("Roundtrip OK:", data.equals(decoded));

try {
  codec.base64.decode(urlSafe);
  console.log("Should not reach here");
} catch {
  console.log("Correctly rejected url-safe data without flag");
}
