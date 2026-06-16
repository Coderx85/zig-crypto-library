const std = @import("std");
const builtin = @import("builtin");
const claims_mod = @import("claims.zig");
const errors_mod = @import("errors.zig");
const blake2b = @import("blake2b");
const xchacha20 = @import("xchacha20");
const rand = @import("rand");

pub const Claims = claims_mod.Claims;
pub const Header = claims_mod.Header;
pub const DecodedHeader = claims_mod.DecodedHeader;
pub const ZstError = errors_mod.ZstError;
pub const ErrorCode = errors_mod.ErrorCode;

pub const VERSION = "1";
pub const TYPE = "ZST";
pub const MODE = "local";
pub const MIN_KEY_LEN: usize = 32;
pub const NONCE_LEN: usize = 24;
pub const TAG_LEN: usize = 16;
pub const TOKEN_PREFIX = "zst_v1.local.";

pub const SignOptions = struct {
    expires_in: ?[]const u8 = null,
    not_before: ?[]const u8 = null,
    audience: ?[]const u8 = null,
    issuer: ?[]const u8 = null,
    subject: ?[]const u8 = null,
    jwtid: ?[]const u8 = null,
    rev: ?u64 = null,
};

pub const VerifyOptions = struct {
    audience: ?[]const u8 = null,
    issuer: ?[]const u8 = null,
    subject: ?[]const u8 = null,
    jwtid: ?[]const u8 = null,
    current_rev: u64 = 0,
    clock_tolerance: u64 = 0,
    clock_timestamp: ?u64 = null,
    max_age: ?u64 = null,
    complete: bool = false,
    ignore_expiration: bool = false,
    ignore_not_before: bool = false,
};

pub const VerifyResult = struct {
    payload: Claims,
    header: DecodedHeader,
};

fn hasAnyOptions(options: SignOptions) bool {
    return options.expires_in != null or
        options.not_before != null or
        options.audience != null or
        options.issuer != null or
        options.subject != null or
        options.jwtid != null or
        options.rev != null;
}

pub fn generateKey(allocator: std.mem.Allocator, length: usize) ![]u8 {
    if (length < MIN_KEY_LEN) return error.KeyTooShort;
    const buf = try allocator.alloc(u8, length);
    rand.fillRandom(buf);
    return buf;
}

pub fn sign(allocator: std.mem.Allocator, payload: []const u8, key: []const u8, options: SignOptions) ZstError![]u8 {
    if (key.len < MIN_KEY_LEN) return error.KeyTooShort;

    // Fast path: when no options set, use raw payload directly (no parse/reserialize)
    var claims_buf: [Claims.MAX_CLAIMS_JSON_LEN]u8 = undefined;
    const claims_json = if (!hasAnyOptions(options))
        payload
    else blk: {
        const claims = claims_mod.parseClaimsJson(allocator, payload) catch return error.InvalidPayload;
        defer freeClaims(allocator, claims);

        var final_claims = claims;
        if (options.audience) |aud| final_claims.aud = aud;
        if (options.issuer) |iss| final_claims.iss = iss;
        if (options.subject) |sub| final_claims.sub = sub;
        if (options.jwtid) |jti| final_claims.jti = jti;
        if (options.rev) |rev| final_claims.rev = rev;

        break :blk claims_mod.serializeClaimsJson(&claims_buf, final_claims) catch return error.InvalidPayload;
    };

    var enc_key: [32]u8 = undefined;
    blake2b.deriveKey(key, "zst-v1-local-encryption", &enc_key);

    var nonce: [NONCE_LEN]u8 = undefined;
    rand.fillRandom(&nonce);

    const encrypted = xchacha20.encrypt(allocator, claims_json, &enc_key, &nonce) catch return error.EncryptionFailed;
    defer allocator.free(encrypted.ciphertext);

    var header_buf: [64]u8 = undefined;
    const header_b64 = base64urlEncodeInto(&header_buf, claims_mod.Header.HEADER_JSON);

    var nonce_buf: [64]u8 = undefined;
    const nonce_b64 = base64urlEncodeInto(&nonce_buf, &nonce);

    var ct_buf: [Claims.MAX_CLAIMS_JSON_LEN * 2 + 8]u8 = undefined;
    const ciphertext_b64 = base64urlEncodeInto(&ct_buf, encrypted.ciphertext);

    var tag_buf: [64]u8 = undefined;
    const tag_b64 = base64urlEncodeInto(&tag_buf, &encrypted.tag);

    const token_len = TOKEN_PREFIX.len + header_b64.len + 1 + nonce_b64.len + 1 + ciphertext_b64.len + 1 + tag_b64.len;
    const token = allocator.alloc(u8, token_len) catch return error.AllocFailed;
    errdefer allocator.free(token);
    var pos: usize = 0;

    @memcpy(token[pos..][0..TOKEN_PREFIX.len], TOKEN_PREFIX);
    pos += TOKEN_PREFIX.len;

    @memcpy(token[pos..][0..header_b64.len], header_b64);
    pos += header_b64.len;

    token[pos] = '.';
    pos += 1;

    @memcpy(token[pos..][0..nonce_b64.len], nonce_b64);
    pos += nonce_b64.len;

    token[pos] = '.';
    pos += 1;

    @memcpy(token[pos..][0..ciphertext_b64.len], ciphertext_b64);
    pos += ciphertext_b64.len;

    token[pos] = '.';
    pos += 1;

    @memcpy(token[pos..][0..tag_b64.len], tag_b64);
    pos += tag_b64.len;

    return token;
}

pub fn verify(allocator: std.mem.Allocator, token: []const u8, key: []const u8, options: VerifyOptions) !VerifyResult {
    if (key.len < MIN_KEY_LEN) return error.KeyTooShort;

    const parts = splitToken(token) catch return error.MalformedToken;

    const nonce = base64urlDecodeAlloc(allocator, parts.nonce) catch return error.MalformedToken;
    defer allocator.free(nonce);
    const ciphertext = base64urlDecodeAlloc(allocator, parts.ciphertext) catch return error.MalformedToken;
    defer allocator.free(ciphertext);
    const tag_bytes = base64urlDecodeAlloc(allocator, parts.tag) catch return error.MalformedToken;
    defer allocator.free(tag_bytes);

    if (nonce.len != NONCE_LEN) return error.MalformedToken;
    if (tag_bytes.len != TAG_LEN) return error.MalformedToken;

    var enc_key: [32]u8 = undefined;
    blake2b.deriveKey(key, "zst-v1-local-encryption", &enc_key);

    var tag: [TAG_LEN]u8 = undefined;
    @memcpy(&tag, tag_bytes);
    const expected_tag = xchacha20.poly1305ComputeTag(ciphertext, &enc_key);
    if (!std.crypto.timing_safe.eql([TAG_LEN]u8, tag, expected_tag)) {
        return error.InvalidSignature;
    }

    var nonce_arr: [NONCE_LEN]u8 = undefined;
    @memcpy(&nonce_arr, nonce);
    const plaintext = xchacha20Decrypt(allocator, ciphertext, &enc_key, &nonce_arr) catch return error.DecryptionFailed;
    defer allocator.free(plaintext);

    const claims = claims_mod.parseClaimsJson(allocator, plaintext) catch return error.InvalidPayload;
    errdefer freeClaims(allocator, claims);

    const now: u64 = options.clock_timestamp orelse getCurrentTimestamp();

    if (!options.ignore_expiration) {
        if (claims.exp) |exp| {
            if (now > exp + options.clock_tolerance) return error.Expired;
        }
    }

    if (!options.ignore_not_before) {
        if (claims.nbf) |nbf| {
            if (now < nbf -| options.clock_tolerance) return error.NotBefore;
        }
    }

    if (options.audience) |aud| {
        if (claims.aud) |token_aud| {
            if (!std.mem.eql(u8, aud, token_aud)) return error.AudienceMismatch;
        }
    }

    if (options.issuer) |iss| {
        if (claims.iss) |token_iss| {
            if (!std.mem.eql(u8, iss, token_iss)) return error.IssuerMismatch;
        }
    }

    if (options.subject) |sub| {
        if (claims.sub) |token_sub| {
            if (!std.mem.eql(u8, sub, token_sub)) return error.SubjectMismatch;
        }
    }

    if (claims.rev) |token_rev| {
        if (token_rev < options.current_rev) return error.Revoked;
    }

    return .{
        .payload = claims,
        .header = .{
            .ver = VERSION,
            .typ = TYPE,
            .mode = MODE,
            .encrypted = true,
        },
    };
}

pub fn decode(token: []const u8) !DecodedHeader {
    _ = splitToken(token) catch return error.MalformedToken;

    return DecodedHeader{
        .ver = VERSION,
        .typ = TYPE,
        .mode = MODE,
        .encrypted = true,
    };
}

const TokenParts = struct {
    header: []const u8,
    nonce: []const u8,
    ciphertext: []const u8,
    tag: []const u8,
};

fn splitToken(token: []const u8) !TokenParts {
    if (!std.mem.startsWith(u8, token, TOKEN_PREFIX)) return error.MalformedToken;
    var rest = token[TOKEN_PREFIX.len..];

    const header_end = std.mem.indexOfScalar(u8, rest, '.') orelse return error.MalformedToken;
    const header = rest[0..header_end];
    rest = rest[header_end + 1 ..];

    const nonce_end = std.mem.indexOfScalar(u8, rest, '.') orelse return error.MalformedToken;
    const nonce = rest[0..nonce_end];
    rest = rest[nonce_end + 1 ..];

    const ct_end = std.mem.indexOfScalar(u8, rest, '.') orelse return error.MalformedToken;
    const ciphertext = rest[0..ct_end];
    const tag = rest[ct_end + 1 ..];

    return .{
        .header = header,
        .nonce = nonce,
        .ciphertext = ciphertext,
        .tag = tag,
    };
}

fn base64urlEncodeInto(buf: []u8, data: []const u8) []const u8 {
    const encoder = std.base64.url_safe_no_pad.Encoder;
    return encoder.encode(buf, data);
}

fn base64urlDecodeAlloc(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded);
    const buf = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(buf);
    try decoder.decode(buf, encoded);
    return buf;
}

fn getCurrentTimestamp() u64 {
    switch (builtin.os.tag) {
        .linux => {
            var ts: std.os.linux.timespec = undefined;
            _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);
            return @intCast(ts.sec);
        },
        else => {
            return 0;
        },
    }
}

fn xchacha20Decrypt(allocator: std.mem.Allocator, ciphertext: []const u8, key: *const [32]u8, nonce: *const [24]u8) ![]u8 {
    var key_words: [8]u32 = undefined;
    for (0..8) |i| {
        key_words[i] = std.mem.readInt(u32, key[i * 4 ..][0..4], .little);
    }

    var h_nonce: [4]u32 = undefined;
    for (0..4) |i| {
        h_nonce[i] = std.mem.readInt(u32, nonce[i * 4 ..][0..4], .little);
    }
    var x_nonce: [6]u32 = undefined;
    for (0..6) |i| {
        x_nonce[i] = std.mem.readInt(u32, nonce[i * 4 ..][0..4], .little);
    }

    const subkey = xchacha20.hChaCha20(&key_words, &h_nonce);

    const plaintext = try allocator.alloc(u8, ciphertext.len);
    errdefer allocator.free(plaintext);

    const num_blocks = (ciphertext.len + 63) / 64;
    for (0..num_blocks) |block_idx| {
        const start = block_idx * 64;
        const end = @min(start + 64, ciphertext.len);
        const block_len = end - start;

        const keystream = xchacha20.xChaCha20(&subkey, &x_nonce, @intCast(block_idx));
        const ks_bytes = std.mem.sliceAsBytes(&keystream);
        for (0..block_len) |j| {
            plaintext[start + j] = ciphertext[start + j] ^ ks_bytes[j];
        }
    }

    return plaintext;
}

pub fn freeClaims(allocator: std.mem.Allocator, claims: Claims) void {
    if (claims.sub) |sub| allocator.free(sub);
    if (claims.aud) |aud| allocator.free(aud);
    if (claims.jti) |jti| allocator.free(jti);
    if (claims.iss) |iss| allocator.free(iss);
    if (claims.custom) |custom| allocator.free(custom);
}

test "constants have correct values" {
    try std.testing.expectEqualStrings("1", VERSION);
    try std.testing.expectEqualStrings("ZST", TYPE);
    try std.testing.expectEqualStrings("local", MODE);
    try std.testing.expectEqualStrings("zst_v1.local.", TOKEN_PREFIX);
    try std.testing.expectEqual(@as(usize, 32), MIN_KEY_LEN);
    try std.testing.expectEqual(@as(usize, 24), NONCE_LEN);
    try std.testing.expectEqual(@as(usize, 16), TAG_LEN);
}

test "constants token prefix matches format" {
    try std.testing.expect(std.mem.startsWith(u8, TOKEN_PREFIX, "zst_v1"));
    try std.testing.expect(std.mem.endsWith(u8, TOKEN_PREFIX, "."));
}

test "generateKey rejects key shorter than MIN_KEY_LEN" {
    try std.testing.expectError(error.KeyTooShort, generateKey(std.testing.allocator, 0));
    try std.testing.expectError(error.KeyTooShort, generateKey(std.testing.allocator, 1));
    try std.testing.expectError(error.KeyTooShort, generateKey(std.testing.allocator, 16));
    try std.testing.expectError(error.KeyTooShort, generateKey(std.testing.allocator, 31));
}

test "generateKey accepts exactly MIN_KEY_LEN" {
    const key = try generateKey(std.testing.allocator, MIN_KEY_LEN);
    defer std.testing.allocator.free(key);
    try std.testing.expectEqual(MIN_KEY_LEN, key.len);
}

test "generateKey accepts larger lengths" {
    const key64 = try generateKey(std.testing.allocator, 64);
    defer std.testing.allocator.free(key64);
    try std.testing.expectEqual(@as(usize, 64), key64.len);

    const key128 = try generateKey(std.testing.allocator, 128);
    defer std.testing.allocator.free(key128);
    try std.testing.expectEqual(@as(usize, 128), key128.len);
}

test "generateKey produces random keys" {
    const key1 = try generateKey(std.testing.allocator, 32);
    defer std.testing.allocator.free(key1);
    const key2 = try generateKey(std.testing.allocator, 32);
    defer std.testing.allocator.free(key2);
    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "generateKey fills all bytes (no zeros)" {
    const key = try generateKey(std.testing.allocator, 32);
    defer std.testing.allocator.free(key);
    var all_zero = true;
    for (key) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "sign rejects short key" {
    const key = [_]u8{0x42} ** 16;
    const result = sign(std.testing.allocator, "{}", &key, .{});
    try std.testing.expectError(error.KeyTooShort, result);
}

test "sign rejects empty key" {
    const result = sign(std.testing.allocator, "{}", "", .{});
    try std.testing.expectError(error.KeyTooShort, result);
}

test "sign produces valid token with required claims" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":1700000000,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{});
    defer std.testing.allocator.free(token);

    try std.testing.expect(std.mem.startsWith(u8, token, TOKEN_PREFIX));
    var dot_count: usize = 0;
    for (token) |c| {
        if (c == '.') dot_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), dot_count);
}

test "sign applies options to claims" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":1700000000,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{
        .audience = "other.example.com",
        .issuer = "auth.example.com",
        .subject = "user_456",
    });
    defer std.testing.allocator.free(token);
    try std.testing.expect(std.mem.startsWith(u8, token, TOKEN_PREFIX));
}

test "verify rejects short key" {
    const key = [_]u8{0x42} ** 16;
    const result = verify(std.testing.allocator, "token", &key, .{});
    try std.testing.expectError(error.KeyTooShort, result);
}

test "verify rejects empty key" {
    const result = verify(std.testing.allocator, "token", "", .{});
    try std.testing.expectError(error.KeyTooShort, result);
}

test "verify rejects malformed token" {
    const key = [_]u8{0x42} ** 32;
    const result = verify(std.testing.allocator, "some.token.value", &key, .{});
    try std.testing.expectError(error.MalformedToken, result);
}

test "verify rejects token with wrong key" {
    const key1 = [_]u8{0x42} ** 32;
    const key2 = [_]u8{0x43} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":1700000000,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key1, .{});
    defer std.testing.allocator.free(token);

    const result = verify(std.testing.allocator, token, &key2, .{});
    try std.testing.expectError(error.InvalidSignature, result);
}

test "verify roundtrip with valid token" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":4102444800,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{});
    defer std.testing.allocator.free(token);

    const result = try verify(std.testing.allocator, token, &key, .{
        .clock_timestamp = 1700000000,
        .ignore_expiration = false,
    });
    defer {
        freeClaims(std.testing.allocator, result.payload);
    }

    try std.testing.expectEqualStrings("user_123", result.payload.sub.?);
    try std.testing.expectEqualStrings("api.example.com", result.payload.aud.?);
    try std.testing.expect(result.header.encrypted);
}

test "verify rejects expired token" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":1000000000,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{});
    defer std.testing.allocator.free(token);

    const result = verify(std.testing.allocator, token, &key, .{
        .clock_timestamp = 2000000000,
    });
    try std.testing.expectError(error.Expired, result);
}

test "verify respects ignore_expiration" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":1000000000,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{});
    defer std.testing.allocator.free(token);

    const result = try verify(std.testing.allocator, token, &key, .{
        .clock_timestamp = 2000000000,
        .ignore_expiration = true,
    });
    defer freeClaims(std.testing.allocator, result.payload);
    try std.testing.expectEqualStrings("user_123", result.payload.sub.?);
}

test "verify rejects revoked token" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":4102444800,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{});
    defer std.testing.allocator.free(token);

    const result = verify(std.testing.allocator, token, &key, .{
        .current_rev = 5,
        .clock_timestamp = 1700000000,
    });
    try std.testing.expectError(error.Revoked, result);
}

test "verify with all options set" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":4102444800,\"rev\":5}";
    const token = try sign(std.testing.allocator, payload, &key, .{
        .audience = "api.example.com",
        .issuer = "auth.example.com",
        .subject = "user_123",
    });
    defer std.testing.allocator.free(token);

    const result = try verify(std.testing.allocator, token, &key, .{
        .audience = "api.example.com",
        .issuer = "auth.example.com",
        .subject = "user_123",
        .current_rev = 3,
        .clock_tolerance = 30,
        .clock_timestamp = 1700000000,
        .ignore_expiration = true,
        .ignore_not_before = true,
    });
    defer freeClaims(std.testing.allocator, result.payload);
    try std.testing.expectEqualStrings("user_123", result.payload.sub.?);
}

test "decode returns correct header fields for valid token" {
    const key = [_]u8{0x42} ** 32;
    const payload = "{\"sub\":\"user_123\",\"aud\":\"api.example.com\",\"exp\":1700000000,\"rev\":1}";
    const token = try sign(std.testing.allocator, payload, &key, .{});
    defer std.testing.allocator.free(token);

    const header = try decode(token);
    try std.testing.expectEqualStrings("1", header.ver);
    try std.testing.expectEqualStrings("ZST", header.typ);
    try std.testing.expectEqualStrings("local", header.mode);
    try std.testing.expect(header.encrypted);
}

test "decode rejects malformed token" {
    const result = decode("not.a.valid.token");
    try std.testing.expectError(error.MalformedToken, result);
}

test "decode rejects token without prefix" {
    const result = decode("random.string.here");
    try std.testing.expectError(error.MalformedToken, result);
}

test "SignOptions defaults are null" {
    const opts = SignOptions{};
    try std.testing.expect(opts.expires_in == null);
    try std.testing.expect(opts.not_before == null);
    try std.testing.expect(opts.audience == null);
    try std.testing.expect(opts.issuer == null);
    try std.testing.expect(opts.subject == null);
    try std.testing.expect(opts.jwtid == null);
    try std.testing.expect(opts.rev == null);
}

test "VerifyOptions defaults" {
    const opts = VerifyOptions{};
    try std.testing.expect(opts.audience == null);
    try std.testing.expect(opts.issuer == null);
    try std.testing.expect(opts.subject == null);
    try std.testing.expect(opts.jwtid == null);
    try std.testing.expectEqual(@as(u64, 0), opts.current_rev);
    try std.testing.expectEqual(@as(u64, 0), opts.clock_tolerance);
    try std.testing.expect(opts.clock_timestamp == null);
    try std.testing.expect(opts.max_age == null);
    try std.testing.expect(!opts.complete);
    try std.testing.expect(!opts.ignore_expiration);
    try std.testing.expect(!opts.ignore_not_before);
}

test "VerifyResult can hold payload and header" {
    const result = VerifyResult{
        .payload = .{
            .sub = "user_123",
            .aud = "api.example.com",
            .exp = 1700000000,
            .iat = 1699996400,
            .jti = "tok_abc",
            .rev = 1,
        },
        .header = .{
            .ver = "1",
            .typ = "ZST",
            .mode = "local",
            .encrypted = true,
        },
    };
    try std.testing.expectEqualStrings("user_123", result.payload.sub.?);
    try std.testing.expectEqualStrings("1", result.header.ver);
    try std.testing.expect(result.header.encrypted);
}

test "Claims type is accessible" {
    const c = Claims{ .sub = "test" };
    try std.testing.expectEqualStrings("test", c.sub.?);
}

test "Header type is accessible" {
    const h = Header{};
    try std.testing.expectEqualStrings("1", h.ver);
}

test "DecodedHeader type is accessible" {
    const dh = DecodedHeader{ .ver = "1", .typ = "ZST", .mode = "local", .encrypted = true };
    try std.testing.expect(dh.encrypted);
}

test "ZstError type is accessible" {
    const result: ZstError = error.Expired;
    try std.testing.expectEqual(error.Expired, result);
}

test "ErrorCode enum is accessible" {
    const code = ErrorCode.expired;
    try std.testing.expectEqual(ErrorCode.expired, code);
}
