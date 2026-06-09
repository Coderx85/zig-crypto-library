const std = @import("std");

pub const BASE64_STANDARD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
pub const BASE64_URL_SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
pub const BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

comptime {
    if (BASE64_STANDARD.len != 64) @compileError("standard alphabet must be exactly 64 characters");
    if (BASE64_URL_SAFE.len != 64) @compileError("URL-safe alphabet must be exactly 64 characters");
    if (BASE58.len != 58) @compileError("base58 alphabet must be exactly 58 characters");
    assertNoDuplicates64(BASE64_STANDARD);
    assertNoDuplicates64(BASE64_URL_SAFE);
    assertNoDuplicates58(BASE58);
}

fn assertNoDuplicates64(alphabet: *const [64]u8) void {
    var seen: [256]bool = [_]bool{false} ** 256;
    for (alphabet) |c| {
        if (seen[c]) @compileError("duplicate character '" ++ [_:0]u8{c} ++ "' in alphabet");
        seen[c] = true;
    }
}

fn assertNoDuplicates58(alphabet: *const [58]u8) void {
    var seen: [256]bool = [_]bool{false} ** 256;
    for (alphabet) |c| {
        if (seen[c]) @compileError("duplicate character '" ++ [_:0]u8{c} ++ "' in base58 alphabet");
        seen[c] = true;
    }
}

pub const ENCODE_STANDARD: [64]u8 = makeEncodeTable(BASE64_STANDARD);
pub const ENCODE_URL_SAFE: [64]u8 = makeEncodeTable(BASE64_URL_SAFE);

pub const DECODE_STANDARD: [256]u8 = makeDecodeTable64(BASE64_STANDARD);
pub const DECODE_URL_SAFE: [256]u8 = makeDecodeTable64(BASE64_URL_SAFE);

pub const DECODE_BASE58: [256]u8 = makeDecodeTable58(BASE58);

fn makeEncodeTable(comptime alphabet: *const [64]u8) [64]u8 {
    var table: [64]u8 = undefined;
    for (&table, alphabet) |*t, c| t.* = c;
    return table;
}

fn makeDecodeTable64(comptime alphabet: *const [64]u8) [256]u8 {
    var table = [_]u8{0xFF} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    table['='] = 0xFE;
    return table;
}

fn makeDecodeTable58(comptime alphabet: *const [58]u8) [256]u8 {
    var table = [_]u8{0xFF} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    return table;
}

test "standard alphabet encode table correct" {
    try std.testing.expectEqualStrings(BASE64_STANDARD, &ENCODE_STANDARD);
}

test "URL-safe alphabet encode table correct" {
    try std.testing.expectEqualStrings(BASE64_URL_SAFE, &ENCODE_URL_SAFE);
}

test "decode table maps valid chars" {
    for (BASE64_STANDARD, 0..) |c, i| {
        const val = DECODE_STANDARD[c];
        try std.testing.expectEqual(@as(u8, @intCast(i)), val);
    }
}

test "decode table maps invalid chars to 0xFF" {
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_STANDARD['!']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_STANDARD['\n']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_STANDARD[' ']);
}

test "decode table maps padding to 0xFE" {
    try std.testing.expectEqual(@as(u8, 0xFE), DECODE_STANDARD['=']);
}

test "base58 alphabet correct length" {
    try std.testing.expectEqual(@as(usize, 58), BASE58.len);
}

test "base58 decode table maps valid chars" {
    for (BASE58, 0..) |c, i| {
        const val = DECODE_BASE58[c];
        try std.testing.expectEqual(@as(u8, @intCast(i)), val);
    }
}

test "base58 decode table rejects excluded chars" {
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['0']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['O']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['I']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['l']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['+']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['/']);
    try std.testing.expectEqual(@as(u8, 0xFF), DECODE_BASE58['!']);
}
