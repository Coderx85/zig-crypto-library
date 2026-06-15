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

export class ZstError extends Error {
  name: "ZstError" = "ZstError";
}

export class ZstExpiredError extends ZstError {
  name: "ZstExpiredError" = "ZstExpiredError";
  expiredAt: Date;
  constructor(message: string, expiredAt?: Date) {
    super(message);
    this.expiredAt = expiredAt ?? new Date();
  }
}

export class ZstNotBeforeError extends ZstError {
  name: "ZstNotBeforeError" = "ZstNotBeforeError";
  date: Date;
  constructor(message: string, date?: Date) {
    super(message);
    this.date = date ?? new Date();
  }
}

export class ZstAudienceError extends ZstError {
  name: "ZstAudienceError" = "ZstAudienceError";
}

export class ZstIssuerError extends ZstError {
  name: "ZstIssuerError" = "ZstIssuerError";
}

export class ZstSubjectError extends ZstError {
  name: "ZstSubjectError" = "ZstSubjectError";
}

export class ZstJwtIdError extends ZstError {
  name: "ZstJwtIdError" = "ZstJwtIdError";
}

export class ZstRevokedError extends ZstError {
  name: "ZstRevokedError" = "ZstRevokedError";
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
