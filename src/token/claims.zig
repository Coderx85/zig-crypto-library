const std = @import("std");

pub const Claims = struct {
    sub: ?[]const u8 = null,
    aud: ?[]const u8 = null,
    exp: ?u64 = null,
    iat: ?u64 = null,
    jti: ?[]const u8 = null,
    rev: ?u64 = null,
    iss: ?[]const u8 = null,
    nbf: ?u64 = null,
    custom: ?[]const u8 = null,

    pub const MAX_CLAIMS_JSON_LEN = 4096;

    pub fn requiredFieldsPresent(self: Claims) bool {
        return self.sub != null and self.aud != null and self.exp != null and self.rev != null;
    }

    pub fn missingFields(self: Claims) []const []const u8 {
        var missing: [4][]const u8 = undefined;
        var count: usize = 0;
        if (self.sub == null) {
            missing[count] = "sub";
            count += 1;
        }
        if (self.aud == null) {
            missing[count] = "aud";
            count += 1;
        }
        if (self.exp == null) {
            missing[count] = "exp";
            count += 1;
        }
        if (self.rev == null) {
            missing[count] = "rev";
            count += 1;
        }
        return missing[0..count];
    }
};

pub const Header = struct {
    ver: []const u8 = "1",
    typ: []const u8 = "ZST",
    mode: []const u8 = "local",

    pub const HEADER_JSON = "{\"ver\":\"1\",\"typ\":\"ZST\",\"mode\":\"local\"}";
};

pub const DecodedHeader = struct {
    ver: []const u8,
    typ: []const u8,
    mode: []const u8,
    encrypted: bool,
};

const JsonWriter = struct {
    buf: []u8,
    pos: usize,

    fn init(buf: []u8) JsonWriter {
        return .{ .buf = buf, .pos = 0 };
    }

    fn writeByte(self: *JsonWriter, byte: u8) !void {
        if (self.pos >= self.buf.len) return error.NoSpaceLeft;
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    fn writeAll(self: *JsonWriter, slice: []const u8) !void {
        for (slice) |byte| {
            try self.writeByte(byte);
        }
    }

    fn print(self: *JsonWriter, comptime fmt: []const u8, args: anytype) !void {
        const str = try std.fmt.bufPrint(self.buf[self.pos..], fmt, args);
        self.pos += str.len;
    }

    fn writeJsonValue(self: *JsonWriter, value: std.json.Value) !void {
        var w = std.Io.Writer.fixed(self.buf[self.pos..]);
        try std.json.fmt(value, .{}).format(&w);
        self.pos += w.buffered().len;
    }

    fn written(self: *const JsonWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

pub fn serializeClaimsJson(buf: []u8, claims: Claims) ![]const u8 {
    var writer = JsonWriter.init(buf);

    try writer.writeByte('{');
    var first = true;

    if (claims.sub) |sub| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"sub\":\"{s}\"", .{sub});
        first = false;
    }
    if (claims.aud) |aud| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"aud\":\"{s}\"", .{aud});
        first = false;
    }
    if (claims.exp) |exp| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"exp\":{d}", .{exp});
        first = false;
    }
    if (claims.iat) |iat| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"iat\":{d}", .{iat});
        first = false;
    }
    if (claims.jti) |jti| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"jti\":\"{s}\"", .{jti});
        first = false;
    }
    if (claims.rev) |rev| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"rev\":{d}", .{rev});
        first = false;
    }
    if (claims.iss) |iss| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"iss\":\"{s}\"", .{iss});
        first = false;
    }
    if (claims.nbf) |nbf| {
        if (!first) try writer.writeByte(',');
        try writer.print("\"nbf\":{d}", .{nbf});
        first = false;
    }
    if (claims.custom) |custom| {
        if (!first) try writer.writeByte(',');
        try writer.writeAll(custom);
    }

    try writer.writeByte('}');
    return writer.written();
}

const known_fields = [_][]const u8{ "sub", "aud", "exp", "iat", "jti", "rev", "iss", "nbf" };

pub fn parseClaimsJson(allocator: std.mem.Allocator, json_str: []const u8) !Claims {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    var claims: Claims = .{};

    if (obj.get("sub")) |sub| {
        if (sub == .string) claims.sub = try allocator.dupe(u8, sub.string);
    }
    if (obj.get("aud")) |aud| {
        if (aud == .string) claims.aud = try allocator.dupe(u8, aud.string);
    }
    if (obj.get("exp")) |exp| {
        if (exp == .integer) claims.exp = @intCast(exp.integer);
    }
    if (obj.get("iat")) |iat| {
        if (iat == .integer) claims.iat = @intCast(iat.integer);
    }
    if (obj.get("jti")) |jti| {
        if (jti == .string) claims.jti = try allocator.dupe(u8, jti.string);
    }
    if (obj.get("rev")) |rev| {
        if (rev == .integer) claims.rev = @intCast(rev.integer);
    }
    if (obj.get("iss")) |iss| {
        if (iss == .string) claims.iss = try allocator.dupe(u8, iss.string);
    }
    if (obj.get("nbf")) |nbf| {
        if (nbf == .integer) claims.nbf = @intCast(nbf.integer);
    }

    // Collect custom fields not in the known set
    var custom_buf: [Claims.MAX_CLAIMS_JSON_LEN]u8 = undefined;
    var custom_writer = JsonWriter.init(&custom_buf);
    var first_custom = true;

    var it = obj.iterator();
    while (it.next()) |entry| {
        var is_known = false;
        for (known_fields) |kf| {
            if (std.mem.eql(u8, entry.key_ptr.*, kf)) {
                is_known = true;
                break;
            }
        }
        if (!is_known) {
            if (!first_custom) try custom_writer.writeByte(',');
            try custom_writer.print("\"{s}\":", .{entry.key_ptr.*});
            try custom_writer.writeJsonValue(entry.value_ptr.*);
            first_custom = false;
        }
    }
    if (custom_writer.pos > 0) {
        claims.custom = try allocator.dupe(u8, custom_writer.written());
    }

    return claims;
}

test "claims required fields" {
    const full = Claims{ .sub = "user", .aud = "api", .exp = 100, .rev = 1 };
    try std.testing.expect(full.requiredFieldsPresent());

    const missing = Claims{ .sub = "user" };
    try std.testing.expect(!missing.requiredFieldsPresent());
}

test "header json is valid" {
    try std.testing.expectEqualStrings("{\"ver\":\"1\",\"typ\":\"ZST\",\"mode\":\"local\"}", Header.HEADER_JSON);
}

test "serialize minimal claims" {
    var buf: [4096]u8 = undefined;
    const claims = Claims{ .sub = "user_123", .aud = "api.example.com", .exp = 1700000000, .rev = 1 };
    const json = try serializeClaimsJson(&buf, claims);
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"sub\":\"user_123\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"exp\":1700000000"));
}

test "serialize empty claims" {
    var buf: [4096]u8 = undefined;
    const claims = Claims{};
    const json = try serializeClaimsJson(&buf, claims);
    try std.testing.expectEqualStrings("{}", json);
}

test "serialize all optional fields" {
    var buf: [4096]u8 = undefined;
    const claims = Claims{
        .sub = "user",
        .aud = "api",
        .exp = 1000,
        .iat = 999,
        .jti = "tok_123",
        .rev = 5,
        .iss = "auth.example.com",
        .nbf = 998,
    };
    const json = try serializeClaimsJson(&buf, claims);
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"sub\":\"user\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"aud\":\"api\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"exp\":1000"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"iat\":999"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"jti\":\"tok_123\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"rev\":5"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"iss\":\"auth.example.com\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"nbf\":998"));
}

test "missing fields detection" {
    const c = Claims{ .sub = "user" };
    const missing = c.missingFields();
    try std.testing.expectEqual(@as(usize, 3), missing.len);
}

test "no missing fields when all present" {
    const c = Claims{ .sub = "user", .aud = "api", .exp = 100, .rev = 1 };
    const missing = c.missingFields();
    try std.testing.expectEqual(@as(usize, 0), missing.len);
}
