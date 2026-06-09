import { codec } from "../../../index.js";

const data = Buffer.from("Hello, World!");

// Encode to base64
const encoded = codec.base64.encode(data);
console.log("Encoded:", encoded.toString());
// → "SGVsbG8sIFdvcmxkIQ=="

// Decode back
const decoded = codec.base64.decode(encoded);
console.log("Decoded:", decoded.toString());
// → "Hello, World!"

// Roundtrip preserves exact bytes
console.log("Roundtrip OK:", data.equals(decoded));
// → true
