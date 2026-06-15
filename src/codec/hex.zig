const std = @import("std");

pub const Error = error{
    InvalidChar,
    InvalidLength,
    OutputTooSmall,
};

const HEX_CHARS = "0123456789abcdef";
const HEX_CHARS_UPPER = "0123456789ABCDEF";

const DECODE: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    @memset(&table, 0xFF);
    for (HEX_CHARS, 0..) |ch, i| {
        const val = @as(u8, @truncate(i));
        table[ch] = val;
        table[std.ascii.toUpper(ch)] = val;
    }
    break :blk table;
};

pub inline fn encodeLen(input_len: usize) usize {
    return input_len * 2;
}

pub inline fn decodeLen(input_len: usize) !usize {
    if (input_len % 2 != 0) return error.InvalidLength;
    return input_len / 2;
}

pub const Case = enum { lower, upper };

pub fn encode(input: []const u8, output: []u8, comptime case: Case) !usize {
    const out_len = encodeLen(input.len);
    if (output.len < out_len) return error.OutputTooSmall;

    const chars = switch (case) {
        .lower => HEX_CHARS,
        .upper => HEX_CHARS_UPPER,
    };

    var i: usize = 0;
    var j: usize = 0;

    while (i + 16 <= input.len) {
        const v: @Vector(16, u8) = input[i..][0..16].*;
        inline for (0..16) |k| {
            const byte = v[k];
            output[j + k * 2] = chars[@as(u4, @truncate(byte >> 4))];
            output[j + k * 2 + 1] = chars[@as(u4, @truncate(byte & 0x0F))];
        }
        i += 16;
        j += 32;
    }

    while (i < input.len) : (i += 1) {
        const byte = input[i];
        output[j] = chars[byte >> 4];
        output[j + 1] = chars[byte & 0x0F];
        j += 2;
    }

    return out_len;
}

pub fn decode(input: []const u8, output: []u8) !usize {
    const len = try decodeLen(input.len);
    if (output.len < len) return error.OutputTooSmall;

    var i: usize = 0;
    var j: usize = 0;

    while (i + 32 <= input.len) : (i += 32) {
        const v: @Vector(32, u8) = input[i..][0..32].*;
        inline for (0..16) |k| {
            const hi = DECODE[v[k * 2]];
            const lo = DECODE[v[k * 2 + 1]];
            if (hi == 0xFF or lo == 0xFF) return error.InvalidChar;
            output[j + k] = (hi << 4) | lo;
        }
        j += 16;
    }

    while (i < input.len) : (i += 2) {
        const hi = DECODE[input[i]];
        const lo = DECODE[input[i + 1]];
        if (hi == 0xFF or lo == 0xFF) return error.InvalidChar;
        output[j] = (hi << 4) | lo;
        j += 1;
    }

    return len;
}

test "encode empty" {
    var buf: [4]u8 = undefined;
    const n = try encode("", &buf, .lower);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "encode single byte lower" {
    var buf: [4]u8 = undefined;
    const n = try encode(&[_]u8{0xAB}, &buf, .lower);
    try std.testing.expectEqualStrings("ab", buf[0..n]);
}

test "encode single byte upper" {
    var buf: [4]u8 = undefined;
    const n = try encode(&[_]u8{0xAB}, &buf, .upper);
    try std.testing.expectEqualStrings("AB", buf[0..n]);
}

test "encode standard bytes" {
    const input = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0xFE, 0xFF };
    var buf: [16]u8 = undefined;
    const n = try encode(&input, &buf, .lower);
    try std.testing.expectEqualStrings("00010203feff", buf[0..n]);
}

test "encode all 256 bytes roundtrip" {
    var input: [256]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i);
    var enc: [512]u8 = undefined;
    var dec: [256]u8 = undefined;
    const enc_len = try encode(&input, &enc, .lower);
    const dec_len = try decode(enc[0..enc_len], &dec);
    try std.testing.expectEqual(input.len, dec_len);
    try std.testing.expectEqualSlices(u8, &input, dec[0..dec_len]);
}

test "encode 16-byte aligned exact fit" {
    var input: [16]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i * 17);
    var enc: [32]u8 = undefined;
    var dec: [16]u8 = undefined;
    const enc_len = try encode(&input, &enc, .lower);
    const dec_len = try decode(enc[0..enc_len], &dec);
    try std.testing.expectEqualSlices(u8, &input, dec[0..dec_len]);
}

test "encode 32-byte aligned exact fit" {
    var input: [32]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i * 13);
    var enc: [64]u8 = undefined;
    var dec: [32]u8 = undefined;
    const enc_len = try encode(&input, &enc, .lower);
    const dec_len = try decode(enc[0..enc_len], &dec);
    try std.testing.expectEqualSlices(u8, &input, dec[0..dec_len]);
}

test "encode upper matches lower for case" {
    var input: [8]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i * 31);
    var enc_lower: [16]u8 = undefined;
    var enc_upper: [16]u8 = undefined;
    const n_lower = try encode(&input, &enc_lower, .lower);
    const n_upper = try encode(&input, &enc_upper, .upper);
    try std.testing.expectEqual(n_lower, n_upper);
    var lower_buf: [16]u8 = undefined;
    const lowerd = std.ascii.lowerString(&lower_buf, enc_upper[0..n_upper]);
    try std.testing.expectEqualStrings(enc_lower[0..n_lower], lowerd);
}

test "encode output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, encode(&[_]u8{0xFF}, &buf, .lower));
}

test "decode empty" {
    var buf: [4]u8 = undefined;
    const n = try decode("", &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "decode single byte" {
    var buf: [4]u8 = undefined;
    const n = try decode("ab", &buf);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u8, 0xAB), buf[0]);
}

test "decode uppercase" {
    var buf: [4]u8 = undefined;
    const n = try decode("AB", &buf);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(u8, 0xAB), buf[0]);
}

test "decode mixed case" {
    var buf: [4]u8 = undefined;
    const n = try decode("AbCdEf", &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAB, 0xCD, 0xEF }, buf[0..n]);
}

test "decode rejects odd length" {
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidLength, decode("abc", &buf));
}

test "decode rejects invalid chars" {
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidChar, decode("x!", &buf));
    try std.testing.expectError(error.InvalidChar, decode("gg", &buf));
    try std.testing.expectError(error.InvalidChar, decode("z0", &buf));
}

test "decode rejects non-hex special chars" {
    var buf: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidChar, decode("@@", &buf));
    try std.testing.expectError(error.InvalidChar, decode("  ", &buf));
    try std.testing.expectError(error.InvalidChar, decode("//", &buf));
}

test "decode output too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decode("abcd", &buf));
}

test "roundtrip various lengths" {
    const lengths = [_]usize{ 0, 1, 2, 3, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 255, 256 };
    inline for (lengths) |len| {
        var input: [256]u8 = undefined;
        if (len > 0) {
            for (&input, 0..) |*b, i| b.* = @truncate(i * 17 + 13);
        }
        const in_slice = input[0..len];
        var enc: [512]u8 = undefined;
        var dec: [256]u8 = undefined;
        const enc_len = try encode(in_slice, &enc, .lower);
        const dec_len = try decode(enc[0..enc_len], &dec);
        try std.testing.expectEqual(len, dec_len);
        try std.testing.expectEqualSlices(u8, in_slice, dec[0..dec_len]);
    }
}

test "roundtrip all lengths 0-32" {
    var buf: [64]u8 = undefined;
    var enc: [128]u8 = undefined;
    var dec: [64]u8 = undefined;
    for (0..33) |len| {
        for (&buf, 0..) |*b, i| {
            if (i < len) b.* = @truncate(i * 7 + 3);
        }
        const enc_len = try encode(buf[0..len], &enc, .lower);
        const dec_len = try decode(enc[0..enc_len], &dec);
        try std.testing.expectEqual(len, dec_len);
        try std.testing.expectEqualSlices(u8, buf[0..len], dec[0..dec_len]);
    }
}

test "encodeLen calculates correct size" {
    try std.testing.expectEqual(@as(usize, 0), encodeLen(0));
    try std.testing.expectEqual(@as(usize, 2), encodeLen(1));
    try std.testing.expectEqual(@as(usize, 4), encodeLen(2));
    try std.testing.expectEqual(@as(usize, 6), encodeLen(3));
    try std.testing.expectEqual(@as(usize, 32), encodeLen(16));
    try std.testing.expectEqual(@as(usize, 512), encodeLen(256));
}

test "decodeLen calculates correct size" {
    try std.testing.expectEqual(@as(usize, 0), try decodeLen(0));
    try std.testing.expectEqual(@as(usize, 1), try decodeLen(2));
    try std.testing.expectEqual(@as(usize, 2), try decodeLen(4));
    try std.testing.expectEqual(@as(usize, 16), try decodeLen(32));
    try std.testing.expectEqual(@as(usize, 128), try decodeLen(256));
}

test "decodeLen rejects odd lengths" {
    try std.testing.expectError(error.InvalidLength, decodeLen(1));
    try std.testing.expectError(error.InvalidLength, decodeLen(3));
    try std.testing.expectError(error.InvalidLength, decodeLen(17));
}

test "decode specific hex values" {
    var buf: [32]u8 = undefined;
    const n = try decode("deadbeef", &buf);
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, buf[0..n]);
}

test "decode cafebabe" {
    var buf: [32]u8 = undefined;
    const n = try decode("cafebabe", &buf);
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xCA, 0xFE, 0xBA, 0xBE }, buf[0..n]);
}

test "decode 010203040506" {
    var buf: [32]u8 = undefined;
    const n = try decode("010203040506", &buf);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 }, buf[0..n]);
}

test "decode long mixed case" {
    var buf: [64]u8 = undefined;
    const hex_str = "01Ab23Cd45Ef67Ab89Cd00Ff11Ee22Aa";
    const expected = [_]u8{
        0x01, 0xAB, 0x23, 0xCD, 0x45, 0xEF, 0x67, 0xAB,
        0x89, 0xCD, 0x00, 0xFF, 0x11, 0xEE, 0x22, 0xAA,
    };
    const n = try decode(hex_str, &buf);
    try std.testing.expectEqual(expected.len, n);
    try std.testing.expectEqualSlices(u8, &expected, buf[0..n]);
}

test "decode hex string to ASCII" {
    var buf: [64]u8 = undefined;
    const n = try decode("48656c6c6f2c20576f726c6421", &buf);
    try std.testing.expectEqualStrings("Hello, World!", buf[0..n]);
}

pub fn main() void {
    const input = "Hello, World!";
    var enc_buf: [64]u8 = undefined;
    var dec_buf: [64]u8 = undefined;

    const enc_len = encode(input, &enc_buf, .lower) catch unreachable;
    const dec_len = decode(enc_buf[0..enc_len], &dec_buf) catch unreachable;

    std.debug.print("Input:  {s}\n", .{input});
    std.debug.print("Encode: {s}\n", .{enc_buf[0..enc_len]});
    std.debug.print("Decode: {s}\n", .{dec_buf[0..dec_len]});
}
