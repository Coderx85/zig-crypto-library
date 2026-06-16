import { codec } from "../../../index.js";

const binary = Buffer.from([
  0x00, 0x01, 0x02, 0x03, 0xff, 0xfe, 0xfd, 0xfc, 0xde, 0xad, 0xbe, 0xef, 0xca,
  0xfe, 0xba, 0xbe,
]);

const encoded = codec.base64.encode(binary);
console.log("Binary encoded:", encoded.toString());

const decoded = codec.base64.decode(encoded);
console.log("Bytes match:", binary.equals(decoded));

const singleEnc = codec.base64.encode(Buffer.from("M"));
console.log("Single byte:", singleEnc.toString());

const emptyEnc = codec.base64.encode(Buffer.alloc(0));
console.log("Empty length:", emptyEnc.length);

const emptyDec = codec.base64.decode(Buffer.alloc(0));
console.log("Decoded empty length:", emptyDec.length);
