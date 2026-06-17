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

export interface ZstDecodedHeader {
  ver: string;
  typ: string;
  mode: string;
  encrypted: boolean;
}

export interface ZstSignOptions {
  expiresIn?: number | string;
  notBefore?: number | string;
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

export interface NativeBindings {
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
  zstSign(payload: string, key: Buffer, options?: ZstSignOptions): string;
  zstVerify(token: string, key: Buffer, options?: ZstVerifyOptions): ZstPayload;
  zstDecode(token: string): ZstDecodedHeader;
  zstGenerateKey(length?: number): Buffer;
}
