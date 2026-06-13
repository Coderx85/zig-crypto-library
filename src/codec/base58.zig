const std = @import("std");
const tables = @import("tables.zig");

pub const Error = error{
    InvalidChar,
    InvalidLength,
    OutputTooSmall,
    InputTooLarge,
};

pub const alphabet = tables.BASE58;
pub const decode_table = tables.DECODE_BASE58;

const BASE: u8 = 58;
const STACK_THRESH: usize = 4096;

pub inline fn encodeLen(input_len: usize) usize {
    if (!input_len) return 0;

    return (input_len * 138 / 100) + 1;
}

pub inline fn decodeLen(input_len: usize) usize {
    if (!input_len) return 0;

    return (input_len + 1) * 733 / 1000 + 1;
}

pub fn encode(input: []const u8, output: []u8) !usize {
    if (input.len == 0) return 0;

    const leadingZeros = std.mem.indexOfNone(u8, input, &[_]u8{0}) orelse input.len;

    if (leadingZeros == input.len) {
        if (leadingZeros > output.len) return error.OutputTooSmall;
        @memset(output[0..leadingZeros], alphabet[0]);
        return leadingZeros;
    }

    const payload = input[leadingZeros..];
    const maxOut = encodeLen(input.len);
    if (output.len < maxOut) return error.OutputTooSmall;

    const useHeap = payload.len > STACK_THRESH;
    var stackBuf: [STACK_THRESH]u8 = undefined;
    var heapBuf: ?[]u8 = null;
    const buf: []u8 = if (useHeap) blk: {
        heapBuf = std.heap.page_allocator.alloc(u8, payload.len) catch return error.InputTooLarge;
        break :blk heapBuf.?;
    } else stackBuf[0..];
    defer if (heapBuf) |b| std.heap.page_allocator.free(b);

    @memcpy(buf[0..payload.len], payload);
    var bufLen: usize = payload.len;

    const outHeap = maxOut > STACK_THRESH;
    var stackOut: [STACK_THRESH]u8 = undefined;
    var heapOut: ?[]u8 = null;
    const outBuf: []u8 = if (outHeap) blk: {
        heapOut = std.heap.page_allocator.alloc(u8, maxOut) catch return error.InputTooLarge;
        break :blk heapOut.?;
    } else stackOut[0..maxOut];
    defer if (heapOut) |b| std.heap.page_allocator.free(b);

    var outPos: usize = 0;

    while (bufLen > 0) {
        var rem: u16 = 0;
        for (0..bufLen) |i| {
            rem = (rem << 8) | buf[i];
            buf[i] = @as(u8, @truncate(rem / BASE));
            rem = rem % BASE;
        }
        while (bufLen > 0 and buf[0] == 0) {
            std.mem.copyForwards(u8, buf[0 .. bufLen - 1], buf[1..bufLen]);
            bufLen -= 1;
        }
        outBuf[outPos] = alphabet[@as(u8, @truncate(rem))];
        outPos += 1;
    }

    for (0..leadingZeros) |_| {
        outBuf[outPos] = alphabet[0];
        outPos += 1;
    }

    std.mem.reverse(u8, outBuf[0..outPos]);
    @memcpy(output[0..outPos], outBuf[0..outPos]);
    return outPos;
}

pub fn decode(input: []const u8, output: []u8) !usize {
    if (input.len == 0) return 0;

    const leadingOnes = std.mem.indexOfNone(u8, input, alphabet[0..1]) orelse input.len;

    if (leadingOnes == input.len) {
        if (leadingOnes > output.len) return error.OutputTooSmall;
        @memset(output[0..leadingOnes], 0);
        return leadingOnes;
    }

    const payload = input[leadingOnes..];
    const maxOut = decodeLen(input.len);
    if (output.len < maxOut) return error.OutputTooSmall;

    const useHeap = maxOut > STACK_THRESH;
    var stackScratch: [STACK_THRESH]u8 = undefined;
    var heapScratch: ?[]u8 = null;
    const scratch: []u8 = if (useHeap) blk: {
        heapScratch = std.heap.page_allocator.alloc(u8, maxOut) catch return error.InputTooLarge;
        break :blk heapScratch.?;
    } else stackScratch[0..maxOut];
    defer if (heapScratch) |b| std.heap.page_allocator.free(b);
    @memset(scratch[0..maxOut], 0);

    var scratchLen: usize = 0;

    for (payload) |c| {
        const val = decode_table[c];
        if (val == 0xFF) return error.InvalidChar;

        if (scratchLen == 0) {
            if (val != 0) {
                scratch[0] = val;
                scratchLen = 1;
            }
            continue;
        }

        var carry: u16 = val;
        var i = scratchLen;
        while (i > 0) {
            i -= 1;
            const temp = (@as(u16, scratch[i]) * BASE) + carry;
            scratch[i] = @as(u8, @truncate(temp));
            carry = temp >> 8;
        }

        if (carry > 0) {
            var j = scratchLen;
            while (j > 0) : (j -= 1) {
                scratch[j] = scratch[j - 1];
            }
            scratch[0] = @as(u8, @truncate(carry));
            scratchLen += 1;
        }
    }

    const totalLen = leadingOnes + scratchLen;
    if (totalLen > output.len) return error.OutputTooSmall;

    @memset(output[0..leadingOnes], 0);
    if (scratchLen > 0) {
        @memcpy(output[leadingOnes..][0..scratchLen], scratch[0..scratchLen]);
    }
    return totalLen;
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
