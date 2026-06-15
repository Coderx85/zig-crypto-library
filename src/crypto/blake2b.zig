const std = @import("std");
const Blake2b256 = std.crypto.hash.blake2.Blake2b256;

// BLAKE2b KDF for ZST token key derivation.
// Uses BLAKE2b-256 with master key as MAC key and domain-separated context.

/// Derive an encryption key from a master key using BLAKE2b-256.
/// The master key is used as the BLAKE2b key (MAC mode).
/// The context string provides domain separation.
pub fn deriveKey(master_key: []const u8, context: []const u8, out: *[32]u8) void {
    // BLAKE2b in keyed mode: hash the context string, keyed with master_key
    var hasher = Blake2b256.init(.{ .key = master_key });
    hasher.update(context);
    hasher.final(out);
}

/// Derive an encryption key and return it as a heap-allocated slice.
pub fn deriveKeyAlloc(allocator: std.mem.Allocator, master_key: []const u8, context: []const u8) ![]u8 {
    const key = try allocator.alloc(u8, 32);
    deriveKey(master_key, context, @ptrCast(key[0..32]));
    return key;
}

// ────────────────────────────────────────────────────────
//  Tests
// ────────────────────────────────────────────────────────

test "deriveKey produces 32-byte output" {
    const master_key = [_]u8{0x42} ** 32;
    var out: [32]u8 = undefined;
    deriveKey(&master_key, "zst-v1-local-encryption", &out);
    try std.testing.expectEqual(@as(usize, 32), out.len);
}

test "deriveKey produces deterministic output" {
    const master_key = [_]u8{0x42} ** 32;
    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    deriveKey(&master_key, "zst-v1-local-encryption", &out1);
    deriveKey(&master_key, "zst-v1-local-encryption", &out2);
    try std.testing.expectEqual(out1, out2);
}

test "deriveKey with different contexts produces different keys" {
    const master_key = [_]u8{0x42} ** 32;
    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    deriveKey(&master_key, "zst-v1-local-encryption", &out1);
    deriveKey(&master_key, "zst-v1-local-signing", &out2);
    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "deriveKey with different master keys produces different keys" {
    const key1 = [_]u8{0x42} ** 32;
    const key2 = [_]u8{0x43} ** 32;
    var out1: [32]u8 = undefined;
    var out2: [32]u8 = undefined;
    deriveKey(&key1, "zst-v1-local-encryption", &out1);
    deriveKey(&key2, "zst-v1-local-encryption", &out2);
    try std.testing.expect(!std.mem.eql(u8, &out1, &out2));
}

test "deriveKey with empty context" {
    const master_key = [_]u8{0x42} ** 32;
    var out: [32]u8 = undefined;
    deriveKey(&master_key, "", &out);
    // Just verify no crash
    try std.testing.expect(out.len == 32);
}

test "deriveKeyAlloc works with allocator" {
    const master_key = [_]u8{0x42} ** 32;
    const key = try deriveKeyAlloc(std.testing.allocator, &master_key, "zst-v1-local-encryption");
    defer std.testing.allocator.free(key);
    try std.testing.expectEqual(@as(usize, 32), key.len);
}
