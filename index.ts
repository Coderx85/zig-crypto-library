import type {
  NativeBindings,
  NanoidFunction,
  SnowflakeModule,
  ZstPayload,
  ZstDecodedHeader,
  ZstSignOptions,
  ZstVerifyOptions,
  ZstDecodeOptions,
  ZstModule,
} from "./src/lib/native.types";
import {
  ZstError,
  ZstExpiredError,
  ZstNotBeforeError,
  ZstAudienceError,
  ZstIssuerError,
  ZstSubjectError,
  ZstJwtIdError,
  ZstRevokedError,
} from "./src/lib/native.types";

export {
  ZstError,
  ZstExpiredError,
  ZstNotBeforeError,
  ZstAudienceError,
  ZstIssuerError,
  ZstSubjectError,
  ZstJwtIdError,
  ZstRevokedError,
};

export type {
  ZstPayload,
  ZstSignOptions,
  ZstVerifyOptions,
  ZstDecodeOptions,
  ZstDecodedHeader,
  ZstModule,
};

function toBuffer(v: string | Buffer | Uint8Array): Buffer {
  return Buffer.isBuffer(v) ? v : Buffer.from(v);
}

const load: NativeBindings = (() => {
  const { arch, platform } = process;
  const archMap: Record<string, string> = { arm64: "aarch64", x64: "x86_64" };
  const platformMap: Record<string, string> = {
    linux: "linux",
    darwin: "macos",
    win32: "windows",
  };
  if (!(arch in archMap)) throw new Error(`Unsupported architecture: ${arch}`);
  if (!(platform in platformMap))
    throw new Error(`Unsupported platform: ${platform}`);

  let linuxABI = "";
  if (platform === "linux") {
    const report = process.report.getReport() as any;
    linuxABI = report.header?.glibcVersionRuntime ? "-gnu" : "-musl";
  }

  const name = `${archMap[arch]}-${platformMap[platform]}${linuxABI}/zig-id.node`;
  const candidates = [
    require("path").resolve(__dirname, "bin", name),
    require("path").resolve(__dirname, "..", "prebuilds", name),
  ];

  const errors: string[] = [];
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (err: any) {
      errors.push(`  ${candidate}: ${err.message || err}`);
    }
  }
  throw new Error(
    `No prebuilt binary found for ${name}. Searched:\n${candidates.map((c) => `  - ${c}`).join("\n")}\nErrors:\n${errors.join("\n")}`
  );
})();

export const Snowflake: SnowflakeModule = { Id: load.Id, Batch: load.Batch };

const TIMESTAMP_SHIFT = 22n;
const NODE_ID_SHIFT = 12n;
const SEQUENCE_MASK = 0xfffn;
const NODE_ID_MASK = 0x3ffn;

export const EPOCH = 1767225600000;

export function extractSnowflakeTime(id: bigint): number {
  return Number((id >> TIMESTAMP_SHIFT) + BigInt(EPOCH));
}

export function extractSnowflakeNodeId(id: bigint): number {
  return Number((id >> NODE_ID_SHIFT) & NODE_ID_MASK);
}

export function extractSnowflakeSequence(id: bigint): number {
  return Number(id & SEQUENCE_MASK);
}

export const DEFAULT_LENGTH = 21;
export const MAX_LENGTH = 128;
export const MAX_BATCH = 1000;

export const nanoid: NanoidFunction = Object.assign(load.nanoid, {
  Batch: load.nanoidBatchStrings,
  BatchBuffer: load.nanoidBatchBuffer,
});

export interface Base64Options {
  urlSafe?: boolean;
}
export interface Base64Module {
  encode(data: Buffer, options?: Base64Options): string;
  encodeBuf(data: Buffer, options?: Base64Options): Buffer;
  decode(data: Buffer | string, options?: Base64Options): Buffer;
  decodeConst(data: Buffer | string, options?: Base64Options): Buffer;
}
export interface Base58Module {
  encode(data: Buffer): string;
  decode(data: string): Buffer;
}
export interface HexOptions {
  upper?: boolean;
}
export interface HexModule {
  encode(data: Buffer, options?: HexOptions): string;
  decode(data: string): Buffer;
}

export const zst: ZstModule = {
  sign(payload, secret, options?) {
    const payloadStr =
      typeof payload === "string" ? payload : JSON.stringify(payload);
    return load.zstSign(payloadStr, toBuffer(secret), options);
  },
  verify(token, secret, options?) {
    return load.zstVerify(
      token,
      toBuffer(secret),
      options
    ) as unknown as ZstPayload;
  },
  decode(token, _options?) {
    return load.zstDecode(token) as unknown as ZstDecodedHeader;
  },
  generateKey(length?: number): Buffer {
    return Buffer.from(load.zstGenerateKey(length));
  },
};

export const codec: {
  base64: Base64Module;
  base58: Base58Module;
  hex: HexModule;
} = {
  base64: {
    encode: (data, options?) => load.base64EncodeStr(data, options),
    encodeBuf: (data, options?) =>
      Buffer.from(load.base64Encode(data, options)),
    decode: (data, options?) => {
      const buf = typeof data === "string" ? Buffer.from(data) : data;
      return Buffer.from(load.base64Decode(buf, options));
    },
    decodeConst: (data, options?) => {
      const buf = typeof data === "string" ? Buffer.from(data) : data;
      return Buffer.from(load.base64DecodeConst(buf, options));
    },
  },
  base58: {
    encode: (data) => load.base58Encode(data),
    decode: (data) => Buffer.from(load.base58Decode(data)),
  },
  hex: {
    encode: (data, options?) => load.hexEncode(data, options),
    decode: (data) => Buffer.from(load.hexDecode(data)),
  },
};
