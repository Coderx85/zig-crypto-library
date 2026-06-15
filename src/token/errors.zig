const std = @import("std");

pub const ErrorCode = enum {
    expired,
    not_before,
    audience,
    issuer,
    subject,
    jwt_id,
    revoked,
    invalid_signature,
    malformed_token,
    key_too_short,
    missing_claim,
};

pub const ZstError = error{
    Expired,
    NotBefore,
    AudienceMismatch,
    IssuerMismatch,
    SubjectMismatch,
    JwtIdMismatch,
    Revoked,
    InvalidSignature,
    MalformedToken,
    KeyTooShort,
    MissingRequiredClaim,
    InvalidPayload,
    EncryptionFailed,
    DecryptionFailed,
    AllocFailed,
    OutOfMemory,
};

pub const ErrorInfo = struct {
    code: ErrorCode,
    message: []const u8,
};

pub fn errorCodeFromError(err: ZstError) ErrorCode {
    return switch (err) {
        error.Expired => .expired,
        error.NotBefore => .not_before,
        error.AudienceMismatch => .audience,
        error.IssuerMismatch => .issuer,
        error.SubjectMismatch => .subject,
        error.JwtIdMismatch => .jwt_id,
        error.Revoked => .revoked,
        error.InvalidSignature => .invalid_signature,
        error.MalformedToken => .malformed_token,
        error.KeyTooShort => .key_too_short,
        error.MissingRequiredClaim => .missing_claim,
        error.InvalidPayload => .missing_claim,
        error.EncryptionFailed => .missing_claim,
        error.DecryptionFailed => .invalid_signature,
        error.AllocFailed => .missing_claim,
        error.OutOfMemory => .missing_claim,
    };
}

pub fn errorMessage(err: ZstError) []const u8 {
    return switch (err) {
        error.Expired => "Token has expired",
        error.NotBefore => "Token is not yet valid",
        error.AudienceMismatch => "Audience mismatch",
        error.IssuerMismatch => "Issuer mismatch",
        error.SubjectMismatch => "Subject mismatch",
        error.JwtIdMismatch => "JWT ID mismatch",
        error.Revoked => "Token has been revoked",
        error.InvalidSignature => "Invalid signature",
        error.MalformedToken => "Malformed token",
        error.KeyTooShort => "Key must be at least 32 bytes",
        error.MissingRequiredClaim => "Missing required claim",
        error.InvalidPayload => "Invalid payload",
        error.EncryptionFailed => "Encryption failed",
        error.DecryptionFailed => "Decryption failed",
        error.AllocFailed => "Allocation failed",
        error.OutOfMemory => "Out of memory",
    };
}

pub fn formatErrorJson(buf: []u8, err: ZstError) ![]const u8 {
    const code = errorCodeFromError(err);
    const msg = errorMessage(err);
    return std.fmt.bufPrint(buf, "{{\"code\":\"{s}\",\"message\":\"{s}\"}}", .{
        @tagName(code),
        msg,
    });
}

test "error codes map correctly" {
    try std.testing.expectEqual(ErrorCode.expired, errorCodeFromError(error.Expired));
    try std.testing.expectEqual(ErrorCode.revoked, errorCodeFromError(error.Revoked));
    try std.testing.expectEqual(ErrorCode.key_too_short, errorCodeFromError(error.KeyTooShort));
}

test "error messages are non-empty" {
    const err = error.Expired;
    const msg = errorMessage(err);
    try std.testing.expect(msg.len > 0);
}

test "format error json" {
    var buf: [256]u8 = undefined;
    const json = try formatErrorJson(&buf, error.Expired);
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "expired"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "Token has expired"));
}
