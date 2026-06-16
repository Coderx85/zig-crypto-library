import { codec } from "../../../index.js";

const data = Buffer.from("Hello, World!");

const encoded = codec.base64.encode(data);
console.log("Encoded:", encoded.toString());

const decoded = codec.base64.decode(encoded);
console.log("Decoded:", decoded.toString());

console.log("Roundtrip OK:", data.equals(decoded));
