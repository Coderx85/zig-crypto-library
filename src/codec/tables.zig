const std = @import("std");

pub const BASE64_STANDARD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
pub const BASE64_URL_SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

comptime {
    if (BASE64_STANDARD.len != 64) @compileError("standard alphabet must be exactly 64 characters");
    if (BASE64_URL_SAFE.len != 64) @compileError("URL-safe alphabet must be exactly 64 characters");
    assertNoDuplicates(BASE64_STANDARD);
    assertNoDuplicates(BASE64_URL_SAFE);
}

fn assertNoDuplicates(alphabet: *const [64]u8) void {
    var seen: [256]bool = [_]bool{false} ** 256;
    for (alphabet) |c| {
        if (seen[c]) @compileError("duplicate character '" ++ [_:0]u8{c} ++ "' in alphabet");
        seen[c] = true;
    }
}

pub const ENCODE_STANDARD: [64]u8 = makeEncodeTable(BASE64_STANDARD);
pub const ENCODE_URL_SAFE: [64]u8 = makeEncodeTable(BASE64_URL_SAFE);

pub const DECODE_STANDARD: [256]u8 = makeDecodeTable(BASE64_STANDARD);
pub const DECODE_URL_SAFE: [256]u8 = makeDecodeTable(BASE64_URL_SAFE);

fn makeEncodeTable(comptime alphabet: *const [64]u8) [64]u8 {
    var table: [64]u8 = undefined;
    for (&table, alphabet) |*t, c| t.* = c;
    return table;
}

fn makeDecodeTable(comptime alphabet: *const [64]u8) [256]u8 {
    var table = [_]u8{0xFF} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    table['='] = 0xFE;
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
