import { codec } from "../../../index.js";

// URL-safe variant uses '-' and '_' instead of '+' and '/'
const data = Buffer.from([0xff, 0xfb, 0xfc]);

// Standard base64 (uses '+/')
const standard = codec.base64.encode(data);
console.log("Standard:", standard.toString());
// → "//v8"

// URL-safe (uses '-_')
const urlSafe = codec.base64.encode(data, { urlSafe: true });
console.log("URL-safe:", urlSafe.toString());
// → "__v8"

// Decode also respects the flag
const decoded = codec.base64.decode(urlSafe, { urlSafe: true });
console.log("Roundtrip OK:", data.equals(decoded));
// → true

// Without urlSafe flag, decoding url-safe data fails
try {
  codec.base64.decode(urlSafe);
  console.log("Should not reach here");
} catch {
  console.log("Correctly rejected url-safe data without flag");
}
