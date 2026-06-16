const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig");
const nanoid = @import("nanoid.zig");
const hex = @import("../codec/hex.zig");
const rand = @import("../crypto/rand.zig");

pub const TokenKind = enum { hex, base64url, alphanumeric, numeric };

pub const Error = error{
    InvalidLength,
    InvalidChar,
    InvalidAlphabet,
    OutOfMemory,
};

const ALPHANUMERIC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const NUMERIC = "0123456789";

pub fn generate(comptime kind: TokenKind, output: []u8, length: usize) !usize {
    switch (kind) {
        .hex => {
            const byte_len = length / 2;
            if (byte_len * 2 != length) return error.InvalidLength;
            var bytes: [nanoid.MAX_LENGTH]u8 = undefined;
            rand.fillRandom(bytes[0..byte_len]);
            return hex.encode(bytes[0..byte_len], output, .lower);
        },
        .base64url => {
            if (length < 1 or length > nanoid.MAX_LENGTH) return error.InvalidLength;
            var buf: [nanoid.MAX_LENGTH]u8 = undefined;
            nanoid.generate(buf[0..length]);
            @memcpy(output, buf[0..length]);
            return length;
        },
        .alphanumeric => {
            return generateCustom(output, length, ALPHANUMERIC);
        },
        .numeric => {
            return generateCustom(output, length, NUMERIC);
        },
    }
}

pub fn generatePrefixed(comptime kind: TokenKind, prefix: []const u8, output: []u8, rand_len: usize) !usize {
    if (output.len < prefix.len + rand_len) return error.OutputTooSmall;
    @memcpy(output[0..prefix.len], prefix);
    const written = try generate(kind, output[prefix.len..], rand_len);
    return prefix.len + written;
}

pub fn generateCustom(output: []u8, length: usize, alphabet: []const u8) !usize {
    if (length < 1) return error.InvalidLength;
    if (alphabet.len < 2 or alphabet.len > 255) return error.InvalidAlphabet;
    if (output.len < length) return error.OutputTooSmall;

    var i: usize = 0;
    while (i < length) : (i += 1) {
        var rand_byte: u8 = 0;
        rand.fillRandom(&.{rand_byte});
        const max_val = 256 - (256 % alphabet.len);
        while (rand_byte >= max_val) {
            rand.fillRandom(&.{rand_byte});
        }
        const idx = rand_byte % @as(u8, @truncate(alphabet.len));
        output[i] = alphabet[idx];
    }

    return length;
}
