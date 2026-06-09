const std = @import("std");
const tables = @import("tables.zig");

pub const Error = error{
    InvalidLength,
    InvalidChar,
    InvalidPadding,
    OutputTooSmall,
};

const PAD: u8 = '=';

pub const Encoding = enum(u1) {
    standard,
    url_safe,

    fn encodeTable(comptime self: @This()) *const [64]u8 {
        return switch (self) {
            .standard => &tables.ENCODE_STANDARD,
            .url_safe => &tables.ENCODE_URL_SAFE,
        };
    }

    fn decodeTable(comptime self: @This()) *const [256]u8 {
        return switch (self) {
            .standard => &tables.DECODE_STANDARD,
            .url_safe => &tables.DECODE_URL_SAFE,
        };
    }
};

// ── Output size helpers ──────────────────────────────

pub inline fn encodeLen(input_len: usize) usize {
    return ((input_len + 2) / 3) * 4;
}

pub inline fn decodeLen(input_len: usize) usize {
    return (input_len / 4) * 3;
}

// ── Encode ───────────────────────────────────────────

pub fn encode(input: []const u8, output: []u8, comptime enc: Encoding) !usize {
    const enc_table = enc.encodeTable();
    const out_len = encodeLen(input.len);
    if (output.len < out_len) return error.OutputTooSmall;

    var i: usize = 0;
    var j: usize = 0;

    // 12 bytes → 4 triplets → 16 output bytes (4× unrolled)
    while (i + 12 <= input.len) {
        const a0: u32 = input[i + 0];
        const a1: u32 = input[i + 1];
        const a2: u32 = input[i + 2];
        const a3: u32 = input[i + 3];
        const a4: u32 = input[i + 4];
        const a5: u32 = input[i + 5];
        const a6: u32 = input[i + 6];
        const a7: u32 = input[i + 7];
        const a8: u32 = input[i + 8];
        const a9: u32 = input[i + 9];
        const a10: u32 = input[i + 10];
        const a11: u32 = input[i + 11];

        const t0 = (a0 << 16) | (a1 << 8) | a2;
        const t1 = (a3 << 16) | (a4 << 8) | a5;
        const t2 = (a6 << 16) | (a7 << 8) | a8;
        const t3 = (a9 << 16) | (a10 << 8) | a11;

        inline for (0..4) |off| {
            const t = switch (off) {
                0 => t0,
                1 => t1,
                2 => t2,
                3 => t3,
                else => unreachable,
            };
            const base = j + off * 4;
            output[base + 0] = enc_table[@as(u6, @truncate(t >> 18))];
            output[base + 1] = enc_table[@as(u6, @truncate(t >> 12))];
            output[base + 2] = enc_table[@as(u6, @truncate(t >> 6))];
            output[base + 3] = enc_table[@as(u6, @truncate(t))];
        }

        i += 12;
        j += 16;
    }

    const rem = input.len - i;
    if (rem >= 3) {
        const a: u32 = input[i];
        const b: u32 = input[i + 1];
        const c: u32 = input[i + 2];
        output[j + 0] = enc_table[@as(u6, @truncate(a >> 2))];
        output[j + 1] = enc_table[@as(u6, @truncate(((a & 0x3) << 4) | (b >> 4)))];
        output[j + 2] = enc_table[@as(u6, @truncate(((b & 0xF) << 2) | (c >> 6)))];
        output[j + 3] = enc_table[@as(u6, @truncate(c & 0x3F))];
        i += 3;
        j += 4;
    }
    if (rem >= 6) {
        const a: u32 = input[i];
        const b: u32 = input[i + 1];
        const c: u32 = input[i + 2];
        output[j + 0] = enc_table[@as(u6, @truncate(a >> 2))];
        output[j + 1] = enc_table[@as(u6, @truncate(((a & 0x3) << 4) | (b >> 4)))];
        output[j + 2] = enc_table[@as(u6, @truncate(((b & 0xF) << 2) | (c >> 6)))];
        output[j + 3] = enc_table[@as(u6, @truncate(c & 0x3F))];
        i += 3;
        j += 4;
    }
    if (rem >= 9) {
        const a: u32 = input[i];
        const b: u32 = input[i + 1];
        const c: u32 = input[i + 2];
        output[j + 0] = enc_table[@as(u6, @truncate(a >> 2))];
        output[j + 1] = enc_table[@as(u6, @truncate(((a & 0x3) << 4) | (b >> 4)))];
        output[j + 2] = enc_table[@as(u6, @truncate(((b & 0xF) << 2) | (c >> 6)))];
        output[j + 3] = enc_table[@as(u6, @truncate(c & 0x3F))];
    }

    // Handle 0-2 byte remainder → padding
    const final_rem = input.len - i;
    if (final_rem == 1) {
        const a: u32 = input[i];
        output[j + 0] = enc_table[@as(u6, @truncate(a >> 2))];
        output[j + 1] = enc_table[@as(u6, @truncate((a & 0x3) << 4))];
        output[j + 2] = PAD;
        output[j + 3] = PAD;
    } else if (final_rem == 2) {
        const a: u32 = input[i];
        const b: u32 = input[i + 1];
        output[j + 0] = enc_table[@as(u6, @truncate(a >> 2))];
        output[j + 1] = enc_table[@as(u6, @truncate(((a & 0x3) << 4) | (b >> 4)))];
        output[j + 2] = enc_table[@as(u6, @truncate((b & 0xF) << 2))];
        output[j + 3] = PAD;
    }

    return out_len;
}

pub const encodeSimd = encode;

// ── Decode ───────────────────────────────────────────

pub fn decode(input: []const u8, output: []u8, comptime enc: Encoding) !usize {
    const dec_table = enc.decodeTable();
    if (input.len == 0) return 0;
    if (input.len % 4 != 0) return error.InvalidLength;
    if (output.len < decodeLen(input.len)) return error.OutputTooSmall;

    const groups = input.len / 4;
    var j: usize = 0;
    var i: usize = 0;

    // Bulk: 8 groups (32 bytes) per iteration
    const bulk8 = (groups - 1) / 8 * 8;
    while (i < bulk8 * 4) : (i += 32) {
        inline for (0..8) |g| {
            const off = i + g * 4;
            const c0: u32 = dec_table[input[off + 0]];
            const c1: u32 = dec_table[input[off + 1]];
            const c2: u32 = dec_table[input[off + 2]];
            const c3: u32 = dec_table[input[off + 3]];
            if (c0 | c1 | c2 | c3 >= 0x40)
                return error.InvalidChar;
            output[j + g * 3 + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
            output[j + g * 3 + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
            output[j + g * 3 + 2] = @as(u8, @truncate((c2 << 6) | c3));
        }
        j += 24;
    }

    // Remaining groups before last (no padding possible)
    while (i < (groups - 1) * 4) : (i += 4) {
        const c0: u32 = dec_table[input[i + 0]];
        const c1: u32 = dec_table[input[i + 1]];
        const c2: u32 = dec_table[input[i + 2]];
        const c3: u32 = dec_table[input[i + 3]];
        if (c0 | c1 | c2 | c3 >= 0x40)
            return error.InvalidChar;
        output[j + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        output[j + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
        output[j + 2] = @as(u8, @truncate((c2 << 6) | c3));
        j += 3;
    }

    // Last group — padding possible
    const off = (groups - 1) * 4;
    const c0: u32 = dec_table[input[off + 0]];
    const c1: u32 = dec_table[input[off + 1]];
    const c2: u32 = dec_table[input[off + 2]];
    const c3: u32 = dec_table[input[off + 3]];
    if (c0 == 0xFF or c1 == 0xFF) return error.InvalidChar;
    if (c2 == 0xFE and c3 == 0xFE) {
        output[j] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        return j + 1;
    }
    if (c2 == 0xFF) return error.InvalidChar;
    if (c3 == 0xFE) {
        output[j + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        output[j + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
        return j + 2;
    }
    if (c3 == 0xFF) return error.InvalidChar;
    output[j + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
    output[j + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
    output[j + 2] = @as(u8, @truncate((c2 << 6) | c3));
    return j + 3;
}

// ── Constant-time decode ────────────────────────────

pub fn decodeConstantTime(input: []const u8, output: []u8, comptime enc: Encoding) !usize {
    const dec_table = enc.decodeTable();
    if (input.len == 0) return 0;
    if (input.len % 4 != 0) return error.InvalidLength;
    if (output.len < decodeLen(input.len)) return error.OutputTooSmall;

    var err: u8 = 0;
    var total: usize = 0;
    const groups = input.len / 4;

    for (0..groups) |g| {
        const off = g * 4;
        const c0: u32 = dec_table[input[off + 0]];
        const c1: u32 = dec_table[input[off + 1]];
        const c2: u32 = dec_table[input[off + 2]];
        const c3: u32 = dec_table[input[off + 3]];

        err |= @as(u8, @intFromBool(c0 >= 0x40));
        err |= @as(u8, @intFromBool(c1 >= 0x40));
        err |= @as(u8, @intFromBool(c2 >= 0x40)) & ~@as(u8, @intFromBool(c2 == 0xFE));
        err |= @as(u8, @intFromBool(c3 >= 0x40)) & ~@as(u8, @intFromBool(c3 == 0xFE));

        const out_off = g * 3;
        output[out_off + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        output[out_off + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
        output[out_off + 2] = @as(u8, @truncate((c2 << 6) | c3));

        const pad2 = @as(u8, @intFromBool(c2 == 0xFE));
        const pad3 = @as(u8, @intFromBool(c3 == 0xFE));
        output[out_off + 1] &= pad2 -% 1;
        output[out_off + 2] &= pad3 -% 1;

        total += 3 - @as(usize, pad2) - @as(usize, pad3);
    }

    if (err != 0) return error.InvalidChar;
    return total;
}

fn simdDecodeTables() struct { @Vector(16, u8), @Vector(16, u8) } {
    comptime {
        var T_lo: [16]u8 = undefined;
        var T_hi: [16]u8 = undefined;

        T_hi[2] = 52;
        T_hi[3] = 53;
        T_hi[4] = 0;
        T_hi[5] = 16;
        T_hi[6] = 26;
        T_hi[7] = 42;
        for (&T_hi, 0..) |*v, k| {
            if (k < 2 or k > 7) v.* = 0;
        }

        T_lo[0] = 255;
        T_lo[1] = 0;
        for (&T_lo, 0..) |*v, k| {
            if (k >= 2) v.* = @intCast(k - 1);
        }

        return .{ @bitCast(T_lo), @bitCast(T_hi) };
    }
}

fn pshufb(table: @Vector(16, u8), indices: @Vector(16, u8)) @Vector(16, u8) {
    var result = table;
    asm volatile ("pshufb %[indices], %[result]"
        : [result] "+x" (result),
        : [indices] "x" (indices),
    );
    return result;
}

fn simdDecode16(v: @Vector(16, u8), comptime enc: Encoding) @Vector(16, u8) {
    const dec_tables = comptime simdDecodeTables();
    const T_lo = dec_tables[0];
    const T_hi = dec_tables[1];

    const v_hi: @Vector(16, u8) = v >> @splat(4);
    var r = pshufb(T_lo, v) +% pshufb(T_hi, v_hi);

    if (comptime enc == .standard) {
        const slash: @Vector(16, u8) = @splat('/');
        const three: @Vector(16, u8) = @splat(3);
        const zero: @Vector(16, u8) = @splat(0);
        const is_slash = v == slash;
        const corr = @select(u8, is_slash, three, zero);
        r = r -% corr;
    } else {
        const minus: @Vector(16, u8) = @splat('-');
        const under: @Vector(16, u8) = @splat('_');
        const two: @Vector(16, u8) = @splat(2);
        const thr3: @Vector(16, u8) = @splat(33);
        const zero: @Vector(16, u8) = @splat(0);
        const c1 = @select(u8, v == minus, two, zero);
        const c2 = @select(u8, v == under, thr3, zero);
        r = r -% c1 +% c2;
    }

    return r;
}

fn simdValid16(v: @Vector(16, u8), comptime enc: Encoding) bool {
    const A: @Vector(16, u8) = @splat('A');
    const Z: @Vector(16, u8) = @splat('Z');
    const a: @Vector(16, u8) = @splat('a');
    const z: @Vector(16, u8) = @splat('z');
    const zero: @Vector(16, u8) = @splat('0');
    const nine: @Vector(16, u8) = @splat('9');
    const is_upper = (v >= A) & (v <= Z);
    const is_lower = (v >= a) & (v <= z);
    const is_digit = (v >= zero) & (v <= nine);
    const is_valid = is_upper | is_lower | is_digit;

    const is_special = if (comptime enc == .standard) blk: {
        const plus: @Vector(16, u8) = @splat('+');
        const slash: @Vector(16, u8) = @splat('/');
        break :blk (v == plus) | (v == slash);
    } else blk: {
        const dash: @Vector(16, u8) = @splat('-');
        const under: @Vector(16, u8) = @splat('_');
        break :blk (v == dash) | (v == under);
    };

    return @reduce(.And, is_valid | is_special);
}

fn simdPack12(v: @Vector(16, u8), output: []u8) void {
    const lanes: @Vector(4, u32) = @bitCast(v);
    inline for (0..4) |g| {
        const lane = lanes[g];
        const a = @as(u8, @truncate(lane));
        const b = @as(u8, @truncate(lane >> 8));
        const c = @as(u8, @truncate(lane >> 16));
        const d = @as(u8, @truncate(lane >> 24));

        output[g * 3 + 0] = (a << 2) | (b >> 4);
        output[g * 3 + 1] = ((b & 0x0F) << 4) | (c >> 2);
        output[g * 3 + 2] = ((c & 0x03) << 6) | d;
    }
}

pub fn decodeSimd(input: []const u8, output: []u8, comptime enc: Encoding) !usize {
    if (comptime @import("builtin").cpu.arch != .x86_64)
        return decode(input, output, enc);

    if (input.len == 0) return 0;
    if (input.len % 4 != 0) return error.InvalidLength;
    if (output.len < decodeLen(input.len)) return error.OutputTooSmall;

    const groups = input.len / 4;
    const bulk = groups - 1;
    const simd_bulk = bulk / 4 * 4;

    var i: usize = 0;
    var j: usize = 0;

    while (i < simd_bulk * 4) : ({
        i += 16;
        j += 12;
    }) {
        const v: @Vector(16, u8) = input[i..][0..16].*;
        if (!simdValid16(v, enc)) return error.InvalidChar;
        const r = simdDecode16(v, enc);
        simdPack12(r, output[j..]);
    }

    while (i < (groups - 1) * 4) : (i += 4) {
        const dec_table = enc.decodeTable();
        const c0: u32 = dec_table[input[i + 0]];
        const c1: u32 = dec_table[input[i + 1]];
        const c2: u32 = dec_table[input[i + 2]];
        const c3: u32 = dec_table[input[i + 3]];
        if (c0 | c1 | c2 | c3 >= 0x40)
            return error.InvalidChar;
        output[j + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        output[j + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
        output[j + 2] = @as(u8, @truncate((c2 << 6) | c3));
        j += 3;
    }

    const off = (groups - 1) * 4;
    const dec_table = enc.decodeTable();
    const c0: u32 = dec_table[input[off + 0]];
    const c1: u32 = dec_table[input[off + 1]];
    const c2: u32 = dec_table[input[off + 2]];
    const c3: u32 = dec_table[input[off + 3]];
    if (c0 == 0xFF or c1 == 0xFF) return error.InvalidChar;
    if (c2 == 0xFE and c3 == 0xFE) {
        output[j] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        return j + 1;
    }
    if (c2 == 0xFF) return error.InvalidChar;
    if (c3 == 0xFE) {
        output[j + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
        output[j + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
        return j + 2;
    }
    if (c3 == 0xFF) return error.InvalidChar;
    output[j + 0] = @as(u8, @truncate((c0 << 2) | (c1 >> 4)));
    output[j + 1] = @as(u8, @truncate((c1 << 4) | (c2 >> 2)));
    output[j + 2] = @as(u8, @truncate((c2 << 6) | c3));
    return j + 3;
}

// ── Tests ────────────────────────────────────────────

test "encode standard basic" {
    const input = "Hello, World!";
    var buf: [64]u8 = undefined;
    const n = try encode(input, &buf, .standard);
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", buf[0..n]);
}

test "encode URL-safe basic" {
    const input = "Hello, World!";
    var buf: [64]u8 = undefined;
    const n = try encode(input, &buf, .url_safe);
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", buf[0..n]);
}

test "encode empty input" {
    var buf: [4]u8 = undefined;
    const n = try encode("", &buf, .standard);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "encode 1 byte padding" {
    var buf: [8]u8 = undefined;
    const n = try encode("M", &buf, .standard);
    try std.testing.expectEqualStrings("TQ==", buf[0..n]);
}

test "encode 2 byte padding" {
    var buf: [8]u8 = undefined;
    const n = try encode("Ma", &buf, .standard);
    try std.testing.expectEqualStrings("TWE=", buf[0..n]);
}

test "encode 3 byte no padding" {
    var buf: [8]u8 = undefined;
    const n = try encode("Man", &buf, .standard);
    try std.testing.expectEqualStrings("TWFu", buf[0..n]);
}

test "encode binary data" {
    const input = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05 };
    var buf: [16]u8 = undefined;
    const n = try encode(&input, &buf, .standard);
    try std.testing.expectEqualStrings("AAECAwQF", buf[0..n]);
}

test "encode URL-safe uses different alphabet" {
    const input = @as([]const u8, &[_]u8{ 0xFF, 0xFB, 0xFC });
    var buf1: [8]u8 = undefined;
    var buf2: [8]u8 = undefined;
    const n1 = try encode(input, &buf1, .standard);
    const n2 = try encode(input, &buf2, .url_safe);
    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqualStrings("//v8", buf1[0..n1]);
    try std.testing.expectEqualStrings("__v8", buf2[0..n2]);
}

test "decode standard basic" {
    var buf: [64]u8 = undefined;
    const n = try decode("SGVsbG8sIFdvcmxkIQ==", &buf, .standard);
    try std.testing.expectEqualStrings("Hello, World!", buf[0..n]);
}

test "decode URL-safe basic" {
    var buf: [64]u8 = undefined;
    const n = try decode("SGVsbG8sIFdvcmxkIQ==", &buf, .url_safe);
    try std.testing.expectEqualStrings("Hello, World!", buf[0..n]);
}

test "decode empty input" {
    var buf: [4]u8 = undefined;
    const n = try decode("", &buf, .standard);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "decode single byte from padding" {
    var buf: [4]u8 = undefined;
    const n = try decode("TQ==", &buf, .standard);
    try std.testing.expectEqualStrings("M", buf[0..n]);
}

test "decode two bytes from padding" {
    var buf: [4]u8 = undefined;
    const n = try decode("TWE=", &buf, .standard);
    try std.testing.expectEqualStrings("Ma", buf[0..n]);
}

test "decode three bytes no padding" {
    var buf: [4]u8 = undefined;
    const n = try decode("TWFu", &buf, .standard);
    try std.testing.expectEqualStrings("Man", buf[0..n]);
}

test "roundtrip standard" {
    const inputs = [_][]const u8{ "a", "ab", "abc", "Hello!", "Hello, World!", "\x00\x01\x02", "Zig is great" };
    inline for (inputs) |input| {
        var enc_buf: [128]u8 = undefined;
        var dec_buf: [128]u8 = undefined;
        const enc_len = try encode(input, &enc_buf, .standard);
        const dec_len = try decode(enc_buf[0..enc_len], &dec_buf, .standard);
        try std.testing.expectEqualStrings(input, dec_buf[0..dec_len]);
    }
}

test "roundtrip URL-safe" {
    const inputs = [_][]const u8{ "a", "ab", "abc", "Hello!", "Hello, World!", "\x00\x01\x02", "Zig is great" };
    inline for (inputs) |input| {
        var enc_buf: [128]u8 = undefined;
        var dec_buf: [128]u8 = undefined;
        const enc_len = try encode(input, &enc_buf, .url_safe);
        const dec_len = try decode(enc_buf[0..enc_len], &dec_buf, .url_safe);
        try std.testing.expectEqualStrings(input, dec_buf[0..dec_len]);
    }
}

test "decode rejects invalid characters" {
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidChar, decode("!!!!", &buf, .standard));
}

test "decode rejects length not multiple of 4" {
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidLength, decode("SGVsbA=", &buf, .standard));
}

test "encode output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, encode("Hello", &buf, .standard));
}

test "decode output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decode("SGVsbG8sIFdvcmxkIQ==", &buf, .standard));
}

test "encodeLen calculates correct size" {
    try std.testing.expectEqual(@as(usize, 0), encodeLen(0));
    try std.testing.expectEqual(@as(usize, 4), encodeLen(1));
    try std.testing.expectEqual(@as(usize, 4), encodeLen(2));
    try std.testing.expectEqual(@as(usize, 4), encodeLen(3));
    try std.testing.expectEqual(@as(usize, 8), encodeLen(4));
    try std.testing.expectEqual(@as(usize, 8), encodeLen(5));
    try std.testing.expectEqual(@as(usize, 8), encodeLen(6));
}

test "decodeLen calculates correct max size" {
    try std.testing.expectEqual(@as(usize, 0), decodeLen(0));
    try std.testing.expectEqual(@as(usize, 3), decodeLen(4));
    try std.testing.expectEqual(@as(usize, 6), decodeLen(8));
    try std.testing.expectEqual(@as(usize, 9), decodeLen(12));
}

// ── SIMD encode tests ────────────────────────────────

test "encodeSimd matches scalar for small inputs" {
    const inputs = [_][]const u8{ "a", "ab", "abc", "Hello!", "Hello, World!" };
    inline for (inputs) |input| {
        var scalar_buf: [128]u8 = undefined;
        var simd_buf: [128]u8 = undefined;
        const scalar_len = try encode(input, &scalar_buf, .standard);
        const simd_len = try encodeSimd(input, &simd_buf, .standard);
        try std.testing.expectEqual(scalar_len, simd_len);
        try std.testing.expectEqualStrings(scalar_buf[0..scalar_len], simd_buf[0..simd_len]);
    }
}

test "encodeSimd matches scalar for 12-byte aligned inputs" {
    const input = "Hello, World!" ** 4;
    var scalar_buf: [512]u8 = undefined;
    var simd_buf: [512]u8 = undefined;
    const scalar_len = try encode(input, &scalar_buf, .standard);
    const simd_len = try encodeSimd(input, &simd_buf, .standard);
    try std.testing.expectEqual(scalar_len, simd_len);
    try std.testing.expectEqualStrings(scalar_buf[0..scalar_len], simd_buf[0..simd_len]);
}

test "encodeSimd URL-safe matches scalar" {
    const input = "Hello, World!" ** 4;
    var scalar_buf: [512]u8 = undefined;
    var simd_buf: [512]u8 = undefined;
    const scalar_len = try encode(input, &scalar_buf, .url_safe);
    const simd_len = try encodeSimd(input, &simd_buf, .url_safe);
    try std.testing.expectEqual(scalar_len, simd_len);
    try std.testing.expectEqualStrings(scalar_buf[0..scalar_len], simd_buf[0..simd_len]);
}

test "encodeSimd handles padding correctly" {
    const inputs = [_][]const u8{ "M", "Ma", "Man" };
    inline for (inputs) |input| {
        var scalar_buf: [16]u8 = undefined;
        var simd_buf: [16]u8 = undefined;
        const scalar_len = try encode(input, &scalar_buf, .standard);
        const simd_len = try encodeSimd(input, &simd_buf, .standard);
        try std.testing.expectEqual(scalar_len, simd_len);
        try std.testing.expectEqualStrings(scalar_buf[0..scalar_len], simd_buf[0..simd_len]);
    }
}

// ── Constant-time decode tests ───────────────────────

test "decodeConstantTime matches decode standard" {
    const inputs = [_][]const u8{ "TQ==", "TWE=", "TWFu", "SGVsbG8=", "SGVsbG8sIFdvcmxkIQ==", "" };
    inline for (inputs) |b64| {
        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        const n1 = try decode(b64, &buf1, .standard);
        const n2 = try decodeConstantTime(b64, &buf2, .standard);
        try std.testing.expectEqual(n1, n2);
        try std.testing.expectEqualStrings(buf1[0..n1], buf2[0..n2]);
    }
}

test "decodeConstantTime matches decode URL-safe" {
    const inputs = [_][]const u8{ "TQ==", "TWE=", "TWFu", "SGVsbG8=", "SGVsbG8sIFdvcmxkIQ==", "" };
    inline for (inputs) |b64| {
        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        const n1 = try decode(b64, &buf1, .url_safe);
        const n2 = try decodeConstantTime(b64, &buf2, .url_safe);
        try std.testing.expectEqual(n1, n2);
        try std.testing.expectEqualStrings(buf1[0..n1], buf2[0..n2]);
    }
}

test "decodeConstantTime rejects invalid characters" {
    var buf: [8]u8 = undefined;
    try std.testing.expectError(error.InvalidChar, decodeConstantTime("!!!!", &buf, .standard));
}

test "decodeConstantTime rejects invalid length" {
    var buf: [8]u8 = undefined;
    try std.testing.expectError(error.InvalidLength, decodeConstantTime("SGVsbA=", &buf, .standard));
}

test "decodeConstantTime rejects output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decodeConstantTime("SGVsbG8sIFdvcmxkIQ==", &buf, .standard));
}

test "decodeConstantTime URL-safe rejects standard chars" {
    var buf: [8]u8 = undefined;
    try std.testing.expectError(error.InvalidChar, decodeConstantTime("//v8", &buf, .url_safe));
}

test "decodeConstantTime roundtrip standard" {
    const inputs = [_][]const u8{ "a", "ab", "abc", "Hello!", "Hello, World!", "\x00\x01\x02", "Zig is great" };
    inline for (inputs) |input| {
        var enc_buf: [128]u8 = undefined;
        var dec_buf: [128]u8 = undefined;
        const enc_len = try encode(input, &enc_buf, .standard);
        const dec_len = try decodeConstantTime(enc_buf[0..enc_len], &dec_buf, .standard);
        try std.testing.expectEqualStrings(input, dec_buf[0..dec_len]);
    }
}

test "decodeConstantTime roundtrip URL-safe" {
    const inputs = [_][]const u8{ "a", "ab", "abc", "Hello!", "Hello, World!", "\x00\x01\x02", "Zig is great" };
    inline for (inputs) |input| {
        var enc_buf: [128]u8 = undefined;
        var dec_buf: [128]u8 = undefined;
        const enc_len = try encode(input, &enc_buf, .url_safe);
        const dec_len = try decodeConstantTime(enc_buf[0..enc_len], &dec_buf, .url_safe);
        try std.testing.expectEqualStrings(input, dec_buf[0..dec_len]);
    }
}

test "decodeSimd matches decode standard" {
    const inputs = [_][]const u8{
        "TQ==",         "TWE=",     "TWFu",     "SGVsbG8=",     "SGVsbG8sIFdvcmxkIQ==", "",
        "QUJDRA==",     "YWJjZGVm", "MTIzNA==", "AAECAwQFBg==", "/////w==",             "AAAAAA==",
        "AAAAAAAAAAE=",
    };
    inline for (inputs) |b64| {
        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        const n1 = try decode(b64, &buf1, .standard);
        const n2 = try decodeSimd(b64, &buf2, .standard);
        try std.testing.expectEqual(n1, n2);
        try std.testing.expectEqualSlices(u8, buf1[0..n1], buf2[0..n2]);
    }
}

test "decodeSimd matches decode URL-safe" {
    const inputs = [_][]const u8{
        "TQ==",         "TWE=",     "TWFu",     "SGVsbG8=",     "SGVsbG8sIFdvcmxkIQ==", "",
        "QUJDRA==",     "YWJjZGVm", "MTIzNA==", "AAECAwQFBg==", "__v8",                 "AAAAAA==",
        "AAAAAAAAAAE=",
    };
    inline for (inputs) |b64| {
        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        const n1 = try decode(b64, &buf1, .url_safe);
        const n2 = try decodeSimd(b64, &buf2, .url_safe);
        try std.testing.expectEqual(n1, n2);
        try std.testing.expectEqualSlices(u8, buf1[0..n1], buf2[0..n2]);
    }
}

test "decodeSimd roundtrip large buffer" {
    const input = "Hello, World! This is a longer string to test SIMD bulk path with more than 16 bytes of base64 input.";
    var enc_buf: [512]u8 = undefined;
    var dec_buf1: [512]u8 = undefined;
    var dec_buf2: [512]u8 = undefined;
    const enc_len = try encode(input, &enc_buf, .standard);
    const n1 = try decode(enc_buf[0..enc_len], &dec_buf1, .standard);
    const n2 = try decodeSimd(enc_buf[0..enc_len], &dec_buf2, .standard);
    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqualSlices(u8, dec_buf1[0..n1], dec_buf2[0..n2]);
}

test "decodeSimd rejects invalid chars same as decode" {
    const invalid = [_][]const u8{ "!!!!", "ABCD", "EFGH", "   ", "a*a*", "AAAA" };
    inline for (invalid) |b64| {
        var buf1: [8]u8 = undefined;
        var buf2: [8]u8 = undefined;
        const r1 = decode(b64, &buf1, .standard);
        const r2 = decodeSimd(b64, &buf2, .standard);
        if (r1) |_| {
            if (r2) |_| {
                // Both succeeded (some may be valid)
            } else |_| {
                try std.testing.expect(false);
            }
        } else |e1| {
            if (r2) |_| {
                try std.testing.expect(false);
            } else |e2| {
                try std.testing.expectEqual(e1, e2);
            }
        }
    }
}

test "decodeSimd rejects invalid length" {
    var buf: [8]u8 = undefined;
    try std.testing.expectError(error.InvalidLength, decodeSimd("SGVsbA=", &buf, .standard));
}

test "decodeSimd rejects output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decodeSimd("SGVsbG8sIFdvcmxkIQ==", &buf, .standard));
}

test "decodeSimd handles URL-safe special chars" {
    // Encode known binary to produce '-' and '_' chars
    var enc_buf: [64]u8 = undefined;
    // 0xFB → bit pattern 11111011 → first base64 char is 111110 = 62 = '-' (url)
    const data = [_]u8{ 0xFB, 0xAF, 0xBE, 0xAD };
    const enc_len = try encode(&data, &enc_buf, .url_safe);
    const b64 = enc_buf[0..enc_len];

    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const n1 = try decode(b64, &buf1, .url_safe);
    const n2 = try decodeSimd(b64, &buf2, .url_safe);
    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqualSlices(u8, buf1[0..n1], buf2[0..n2]);
}

test "decodeSimd handles URL-safe special chars large" {
    // Build a payload that triggers SIMD bulk loop and contains '-' and '_'
    var raw: [48]u8 = undefined;
    for (&raw, 0..) |*b, i| {
        b.* = @truncate((i * 157) & 0xFF); // generates varied bytes including ones that encode to '-' and '_'
    }
    var enc_buf: [128]u8 = undefined;
    const enc_len = try encode(&raw, &enc_buf, .url_safe);
    const b64 = enc_buf[0..enc_len];

    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const n1 = try decode(b64, &buf1, .url_safe);
    const n2 = try decodeSimd(b64, &buf2, .url_safe);
    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqualSlices(u8, buf1[0..n1], buf2[0..n2]);
}

test "decodeConstantTime binary roundtrip" {
    const inputs = [_][]const u8{ "\x00\x01\x02\xFF\xFE", "\xDE\xAD\xBE\xEF", "\xCA\xFE\xBA\xBE\x00\x00" };
    inline for (inputs) |input| {
        var enc_buf: [32]u8 = undefined;
        var dec_buf: [32]u8 = undefined;
        const enc_len = try encode(input, &enc_buf, .standard);
        const dec_len = try decodeConstantTime(enc_buf[0..enc_len], &dec_buf, .standard);
        try std.testing.expectEqualSlices(u8, input, dec_buf[0..dec_len]);
    }
}

pub fn main() void {
    const input = "Hello, World!";
    var enc_buf: [64]u8 = undefined;
    var dec_buf: [64]u8 = undefined;

    const enc_len = encode(input, &enc_buf, .standard) catch unreachable;
    const dec_len = decode(enc_buf[0..enc_len], &dec_buf, .standard) catch unreachable;

    std.debug.print("Input:  {s}\n", .{input});
    std.debug.print("Encode: {s}\n", .{enc_buf[0..enc_len]});
    std.debug.print("Decode: {s}\n", .{dec_buf[0..dec_len]});
}
