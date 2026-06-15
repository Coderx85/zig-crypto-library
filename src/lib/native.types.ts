export interface NativeBindings {
  // ── ID ──
  Id(): bigint;
  Batch(count: number): bigint[];
  // ── Nanoid ──
  nanoid(length?: number): string;
  nanoidBatchBuffer(count: number, length?: number): Buffer;
  nanoidBatchStrings(count: number, length?: number): string[];
  // ── Base64 ──
  base64Encode(data: Buffer, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64EncodeStr(data: Buffer, options?: { urlSafe?: boolean }): string;
  base64Decode(data: Buffer, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64DecodeStr(data: string, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64DecodeConst(data: Buffer, options?: { urlSafe?: boolean }): ArrayBuffer;
  base64DecodeConstStr(
    data: string,
    options?: { urlSafe?: boolean }
  ): ArrayBuffer;
  // ── Base58 ──
  base58Encode(data: Buffer): string;
  base58Decode(data: string): ArrayBuffer;
  // ── Hex ──
  hexEncode(data: Buffer, options?: { upper?: boolean }): string;
  hexDecode(data: string): ArrayBuffer;
  // ── ZST ──
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
