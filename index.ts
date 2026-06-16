interface NativeBindings {
  Id(): bigint;
  Batch(count: number): bigint[];
  nanoid(length?: number): string;
  nanoidBatchBuffer(count: number, length?: number): Buffer;
  nanoidBatchStrings(count: number, length?: number): string[];
  base64Encode(data: Buffer, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64EncodeStr(data: Buffer, options?: { urlSafe?: boolean }): string;
  base64Decode(data: Buffer, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64DecodeStr(data: string, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64DecodeConst(data: Buffer, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64DecodeConstStr(
    data: string,
    options?: { urlSafe?: boolean }
  ): ArrayBuffer;
  base58Encode(data: Buffer): string;
  base58Decode(data: string): ArrayBuffer;
  hexEncode(data: Buffer, options?: { upper?: boolean }): string;
  hexDecode(data: string): ArrayBuffer;
  zstSign(
    payload: string,
    key: Buffer,
    options?: {
      expiresIn?: number | string;
      notBefore?: number | string;
      audience?: string;
      issuer?: string;
      subject?: string;
      jwtid?: string;
      rev?: number;
    }
  ): string;
  zstVerify(
    token: string,
    key: Buffer,
    options?: {
      audience?: string;
      issuer?: string;
      subject?: string;
      jwtid?: string;
      currentRev?: number;
      clockTolerance?: number;
      clockTimestamp?: number;
      maxAge?: number | string;
      complete?: boolean;
      ignoreExpiration?: boolean;
      ignoreNotBefore?: boolean;
    }
  ): string;
  zstDecode(token: string): string;
  zstGenerateKey(length?: number): Buffer;
}

const load: NativeBindings = (() => {
  const { arch, platform } = process;

  const archMap: Record<string, string> = {
    arm64: "aarch64",
    x64: "x86_64",
  };

  const platformMap: Record<string, string> = {
    linux: "linux",
    darwin: "macos",
    win32: "windows",
  };

  if (!(arch in archMap)) {
    throw new Error(`Unsupported architecture: ${arch}`);
  }
  if (!(platform in platformMap)) {
    throw new Error(`Unsupported platform: ${platform}`);
  }

  let linuxABI = "";
  if (platform === "linux") {
    const report = process.report.getReport() as any;
    const glibcVersionRuntime = report.header?.glibcVersionRuntime;
    linuxABI = glibcVersionRuntime ? "-gnu" : "-musl";
  }

  const zigArch = archMap[arch];
  const zigPlatform = platformMap[platform];
  const name = `${zigArch}-${zigPlatform}${linuxABI}/zig-id.node`;

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
    `No prebuilt binary found for ${name}. Searched:\n` +
      candidates.map((c) => `  - ${c}`).join("\n") +
      `\nErrors:\n${errors.join("\n")}`
  );
})();

export interface SnowflakeModule {
  Id(): bigint;
  Batch(count: number): bigint[];
}

export const Snowflake: SnowflakeModule = {
  Id: load.Id,
  Batch: load.Batch,
};

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

export interface NanoidFunction {
  (length?: number): string;
  Batch(count: number, length?: number): string[];
  BatchBuffer(count: number, length?: number): Buffer;
}

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

export class ZstError extends Error {
  name = "ZstError" as const;
}

export class ZstExpiredError extends ZstError {
  expiredAt: Date;
  constructor(message: string, expiredAt?: Date) {
    super(message);
    this.expiredAt = expiredAt ?? new Date();
  }
}

export class ZstNotBeforeError extends ZstError {
  date: Date;
  constructor(message: string, date?: Date) {
    super(message);
    this.date = date ?? new Date();
  }
}

export class ZstAudienceError extends ZstError {
  constructor() {
    super("Zistoken audience mismatch");
  }
}

export class ZstIssuerError extends ZstError {
  constructor() {
    super("Zistoken issuer mismatch");
  }
}

export class ZstSubjectError extends ZstError {
  constructor() {
    super("Zistoken subject mismatch");
  }
}

export class ZstJwtIdError extends ZstError {
  constructor() {
    super("Zistoken JWT ID mismatch");
  }
}

export class ZstRevokedError extends ZstError {
  constructor() {
    super("Zistoken revoked");
  }
}

function throwZstError(errorJson: string): never {
  const parsed = JSON.parse(errorJson) as { code: string; message: string };
  switch (parsed.code) {
    case "expired":
      throw new ZstExpiredError(parsed.message);
    case "not_before":
      throw new ZstNotBeforeError(parsed.message);
    case "audience":
      throw new ZstAudienceError();
    case "issuer":
      throw new ZstIssuerError();
    case "subject":
      throw new ZstSubjectError();
    case "jwt_id":
      throw new ZstJwtIdError();
    case "revoked":
      throw new ZstRevokedError();
    default:
      throw new ZstError(parsed.message);
  }
}

export interface ZstSignOptions {
  expiresIn?: number | string;
  notBefore?: string;
  audience?: string;
  issuer?: string;
  subject?: string;
  jwtid?: string;
  rev?: number;
  header?: Record<string, any>;
  mutatePayload?: boolean;
}

export interface ZstVerifyOptions {
  audience?: string;
  issuer?: string;
  subject?: string;
  jwtid?: string;
  currentRev?: number;
  clockTolerance?: number;
  clockTimestamp?: number;
  maxAge?: number | string;
  complete?: boolean;
  ignoreExpiration?: boolean;
  ignoreNotBefore?: boolean;
}

export interface ZstDecodeOptions {
  complete?: boolean;
}

export interface ZstPayload {
  sub: string;
  aud: string;
  exp: number;
  iat: number;
  jti: string;
  rev: number;
  iss?: string;
  nbf?: number;
  [key: string]: any;
}

export interface ZstHeader {
  ver: string;
  typ: string;
  mode: "local" | "public";
}

export interface ZstCompleteResult {
  payload: ZstPayload;
  header: ZstHeader;
}

export interface ZstDecodedHeader {
  ver: string;
  typ: string;
  mode: string;
  encrypted: boolean;
}

export interface ZstModule {
  sign(
    payload: object | string | Buffer,
    secret: string | Buffer | Uint8Array,
    options?: ZstSignOptions
  ): string;
  verify(
    token: string,
    secret: string | Buffer | Uint8Array,
    options?: ZstVerifyOptions
  ): ZstPayload;
  decode(token: string, options?: ZstDecodeOptions): ZstDecodedHeader;
  generateKey(length?: number): Buffer;
}

export const zst: ZstModule = {
  sign(payload, secret, options?) {
    const keyBuf = Buffer.isBuffer(secret)
      ? secret
      : typeof secret === "string"
        ? Buffer.from(secret)
        : Buffer.from(secret);
    const payloadStr =
      typeof payload === "string" ? payload : JSON.stringify(payload);
    return load.zstSign(payloadStr, keyBuf, options);
  },
  verify(token, secret, options?) {
    const keyBuf = Buffer.isBuffer(secret)
      ? secret
      : typeof secret === "string"
        ? Buffer.from(secret)
        : Buffer.from(secret);
    const result = load.zstVerify(token, keyBuf, options);
    try {
      return JSON.parse(result) as ZstPayload;
    } catch {
      throwZstError(result);
    }
  },
  decode(token, options?) {
    const result = load.zstDecode(token);
    return JSON.parse(result) as ZstDecodedHeader;
  },
  generateKey(length?: number): Buffer {
    return load.zstGenerateKey(length);
  },
};

export const codec: {
  base64: Base64Module;
  base58: Base58Module;
  hex: HexModule;
} = {
  base64: {
    encode(data: Buffer, options?: Base64Options): string {
      return load.base64EncodeStr(data, options);
    },
    encodeBuf(data: Buffer, options?: Base64Options): Buffer {
      return Buffer.from(load.base64Encode(data, options));
    },
    decode(data: Buffer | string, options?: Base64Options): Buffer {
      const buf: Buffer = typeof data === "string" ? Buffer.from(data) : data;
      return Buffer.from(load.base64Decode(buf, options));
    },
    decodeConst(data: Buffer | string, options?: Base64Options): Buffer {
      const buf: Buffer = typeof data === "string" ? Buffer.from(data) : data;
      return Buffer.from(load.base64DecodeConst(buf, options));
    },
  },
  base58: {
    encode(data: Buffer): string {
      return load.base58Encode(data);
    },
    decode(data: string): Buffer {
      return Buffer.from(load.base58Decode(data));
    },
  },
  hex: {
    encode(data: Buffer, options?: HexOptions): string {
      return load.hexEncode(data, options);
    },
    decode(data: string): Buffer {
      return Buffer.from(load.hexDecode(data));
    },
  },
};
