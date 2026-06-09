const std = @import("std");
const tables = @import("tables.zig");

pub const Error = error{
    InvalidChar,
    InvalidLength,
    OutputTooSmall,
};

pub const alphabet = tables.BASE58;
pub const decode_table = tables.DECODE_BASE58;

const BASE: u8 = 58;

pub inline fn encodeLen(input_len: usize) usize {
    return if (input_len == 0) 0 else input_len * 138 / 100 + 2;
}

pub inline fn decodeLen(input_len: usize) usize {
    return if (input_len == 0) 0 else (input_len + 1) * 733 / 1000 + 1;
}

pub fn encode(input: []const u8, output: []u8) !usize {
    if (input.len == 0) return 0;

    var leading_zeros: usize = 0;
    while (leading_zeros < input.len and input[leading_zeros] == 0) {
        leading_zeros += 1;
    }

    const payload = input[leading_zeros..];
    if (payload.len == 0) {
        if (leading_zeros > output.len) return error.OutputTooSmall;
        @memset(output[0..leading_zeros], alphabet[0]);
        return leading_zeros;
    }

    const max_out = encodeLen(input.len);
    if (output.len < max_out) return error.OutputTooSmall;

    var buf: [256]u8 = undefined;
    @memcpy(buf[0..payload.len], payload);
    var buf_len: usize = payload.len;

    var out_buf: [384]u8 = undefined;
    var out_pos: usize = 0;

    while (buf_len > 0) {
        var rem: u16 = 0;
        for (0..buf_len) |i| {
            rem = (rem << 8) | buf[i];
            buf[i] = @as(u8, @truncate(rem / BASE));
            rem = rem % BASE;
        }
        while (buf_len > 0 and buf[0] == 0) {
            std.mem.copyForwards(u8, buf[0..buf_len], buf[1 .. buf_len + 1]);
            buf_len -= 1;
        }
        out_buf[out_pos] = alphabet[@as(u8, @truncate(rem))];
        out_pos += 1;
    }

    for (0..leading_zeros) |_| {
        out_buf[out_pos] = alphabet[0];
        out_pos += 1;
    }

    std.mem.reverse(u8, out_buf[0..out_pos]);
    @memcpy(output[0..out_pos], out_buf[0..out_pos]);
    return out_pos;
}

pub fn decode(input: []const u8, output: []u8) !usize {
    if (input.len == 0) return 0;

    var leading_ones: usize = 0;
    while (leading_ones < input.len and input[leading_ones] == alphabet[0]) {
        leading_ones += 1;
    }

    const payload = input[leading_ones..];
    if (payload.len == 0) {
        if (leading_ones > output.len) return error.OutputTooSmall;
        @memset(output[0..leading_ones], 0);
        return leading_ones;
    }

    const max_out = decodeLen(input.len);
    if (output.len < max_out) return error.OutputTooSmall;

    var scratch: [256]u8 = undefined;
    var scratch_len: usize = 0;

    for (payload) |c| {
        const val = decode_table[c];
        if (val == 0xFF) return error.InvalidChar;

        if (scratch_len == 0) {
            if (val != 0) {
                scratch[0] = val;
                scratch_len = 1;
            }
            continue;
        }

        var carry: u16 = val;
        var i = scratch_len;
        while (i > 0) {
            i -= 1;
            const temp = (@as(u16, scratch[i]) * BASE) + carry;
            scratch[i] = @as(u8, @truncate(temp));
            carry = temp >> 8;
        }

        if (carry > 0) {
            var j = scratch_len;
            while (j > 0) : (j -= 1) {
                scratch[j] = scratch[j - 1];
            }
            scratch[0] = @as(u8, @truncate(carry));
            scratch_len += 1;
        }
    }

    const total_len = leading_ones + scratch_len;
    if (total_len > output.len) return error.OutputTooSmall;

    @memset(output[0..leading_ones], 0);
    if (scratch_len > 0) {
        @memcpy(output[leading_ones..][0..scratch_len], scratch[0..scratch_len]);
    }
    return total_len;
}

// ── Tests ──

test "encode empty" {
    var buf: [4]u8 = undefined;
    const n = try encode("", &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "encode all zeros" {
    var buf: [16]u8 = undefined;
    const input = [_]u8{ 0, 0, 0 };
    const n = try encode(&input, &buf);
    try std.testing.expectEqualStrings("111", buf[0..n]);
}

test "encode single zero" {
    var buf: [16]u8 = undefined;
    const n = try encode(&[_]u8{0x00}, &buf);
    try std.testing.expectEqualStrings("1", buf[0..n]);
}

test "encode single byte 1" {
    var buf: [16]u8 = undefined;
    const n = try encode(&[_]u8{1}, &buf);
    try std.testing.expectEqualStrings("2", buf[0..n]);
}

test "encode leading zero then 1" {
    var buf: [16]u8 = undefined;
    const input = [_]u8{ 0x00, 0x01 };
    const n = try encode(&input, &buf);
    try std.testing.expectEqualStrings("12", buf[0..n]);
}

test "encode 0xFF" {
    var buf: [16]u8 = undefined;
    const n = try encode(&[_]u8{0xFF}, &buf);
    try std.testing.expectEqualStrings("5Q", buf[0..n]);
}

test "decode empty" {
    var buf: [4]u8 = undefined;
    const n = try decode("", &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "decode one char" {
    var buf: [4]u8 = undefined;
    const n = try decode("2", &buf);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u8, 1), buf[0]);
}

test "decode leading 1s" {
    var buf: [16]u8 = undefined;
    const n = try decode("111", &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    for (0..3) |i| {
        try std.testing.expectEqual(@as(u8, 0), buf[i]);
    }
}

test "decode Bitcoin P2PKH roundtrip" {
    const input = [_]u8{
        0x00, 0x6a, 0xe3, 0x5b, 0x5d, 0x13, 0x45, 0x53,
        0x2d, 0x27, 0x8e, 0x11, 0x0e, 0x9a, 0x6c, 0x9c,
        0x6a, 0x22, 0xc2, 0x63, 0x10, 0x65, 0xfb, 0x36,
        0x16,
    };
    var enc_buf: [64]u8 = undefined;
    var dec_buf: [64]u8 = undefined;
    const enc_len = try encode(&input, &enc_buf);
    const dec_len = try decode(enc_buf[0..enc_len], &dec_buf);
    try std.testing.expectEqual(input.len, dec_len);
    try std.testing.expectEqualSlices(u8, &input, dec_buf[0..dec_len]);
}

test "roundtrip various" {
    const inputs = [_][]const u8{
        &[_]u8{0x01},
        &[_]u8{0xFF},
        &[_]u8{ 0x00, 0x00 },
        &[_]u8{ 0x00, 0x01 },
        &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF },
        &[_]u8{ 0xCA, 0xFE, 0xBA, 0xBE },
        &[_]u8{ 0x00, 0x00, 0x00, 0x01 },
        &[_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF },
        &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
    };
    inline for (inputs) |input| {
        var enc_buf: [64]u8 = undefined;
        var dec_buf: [64]u8 = undefined;
        const enc_len = try encode(input, &enc_buf);
        const dec_len = try decode(enc_buf[0..enc_len], &dec_buf);
        try std.testing.expectEqual(input.len, dec_len);
        try std.testing.expectEqualSlices(u8, input, dec_buf[0..dec_len]);
    }
}

test "decode rejects invalid chars" {
    var buf: [8]u8 = undefined;
    const invalids = [_][]const u8{ "0", "O", "I", "l", "+", "/", "!", "@", " " };
    inline for (invalids) |s| {
        try std.testing.expectError(error.InvalidChar, decode(s, &buf));
    }
}

test "encode output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, encode(&[_]u8{0xFF}, &buf));
}

test "decode output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decode("5Q", &buf));
}
