const std = @import("std");
const builtin = @import("builtin");

pub const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
comptime {
    if (ALPHABET.len != 64) @compileError("ALPHABET must be exactly 64 characters");
}

pub const DEFAULT_LENGTH: usize = 21;

pub const MAX_LENGTH: usize = 128;

pub const MAX_BATCH: usize = 1000;

pub const NanoidError = error{ InvalidLength, InvalidCount, OutOfMemory };

/// Fill buffer with cryptographically secure random bytes.
fn fillRandom(buf: []u8) void {
    switch (comptime builtin.os.tag) {
        .linux => {
            var filled: usize = 0;
            while (filled < buf.len) {
                const rc = std.os.linux.getrandom(buf[filled..].ptr, buf.len - filled, 0);
                filled += rc;
            }
        },
        .macos, .ios, .watchos, .tvos => {
            std.c.arc4random_buf(buf.ptr, buf.len);
        },
        .windows => {
            const status = std.os.windows.BCryptGenRandom(
                null, // hAlgorithm (null for default)
                buf.ptr,
                buf.len,
                0x00000002, // BCRYPT_USE_SYSTEM_PREFERRED_RNG
            );
            if (status != 0) @compileError("BCryptGenRandom failed");
        },
        else => @compileError("Unsupported OS for CSPRNG — add platform-specific random source"),
    }
}

/// Generate a single nanoid of the given length.
pub fn generate(allocator: std.mem.Allocator, length: usize) NanoidError![]u8 {
    if (length < 1 or length > MAX_LENGTH) return error.InvalidLength;

    const buf = allocator.alloc(u8, length) catch return error.OutOfMemory;
    errdefer allocator.free(buf);

    // Fill with cryptographically secure random bytes
    fillRandom(buf);

    // Map each byte to the alphabet using bitmask (zero modulo bias)
    for (buf) |*b| {
        b.* = ALPHABET[b.* & 0x3F];
    }

    return buf;
}

// Generate a batch of nanoids.
pub fn generateBatch(allocator: std.mem.Allocator, count: usize, length: usize) NanoidError![][]u8 {
    if (count < 1 or count > MAX_BATCH) return error.InvalidCount;

    if (length < 1 or length > MAX_LENGTH) return error.InvalidLength;

    const ids = allocator.alloc([]u8, count) catch return error.OutOfMemory;
    errdefer allocator.free(ids);

    var generated: usize = 0;
    errdefer {
        for (ids[0..generated]) |id| {
            allocator.free(id);
        }
    }

    while (generated < count) {
        ids[generated] = try generate(allocator, length);
        generated += 1;
    }

    return ids;
}

// ── Tests ─────────────────────────────────────────────────────────────────────
fn isInAlphabet(ch: u8) bool {
    for (ALPHABET) |a| {
        if (ch == a) return true;
    }
    return false;
}

test "single generation returns correct length" {
    const alloc = std.testing.allocator;
    const id = try generate(alloc, 21);
    defer alloc.free(id);
    try std.testing.expectEqual(@as(usize, 21), id.len);
}

test "default length is 21" {
    try std.testing.expectEqual(@as(usize, 21), DEFAULT_LENGTH);
}

test "all characters are URL-safe" {
    const alloc = std.testing.allocator;
    const id = try generate(alloc, 21);
    defer alloc.free(id);
    for (id) |ch| {
        try std.testing.expect(isInAlphabet(ch));
    }
}

test "uniqueness 1000" {
    const alloc = std.testing.allocator;
    var seen = std.StringHashMap(void).init(alloc);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        seen.deinit();
    }

    for (0..1000) |_| {
        const id = try generate(alloc, 21);
        defer alloc.free(id);
        const duped = try alloc.dupe(u8, id);
        const result = try seen.getOrPut(duped);
        if (result.found_existing) {
            alloc.free(duped);
        }
        try std.testing.expect(!result.found_existing);
    }
}

test "alphabet membership" {
    const alloc = std.testing.allocator;
    const id = try generate(alloc, 128);
    defer alloc.free(id);
    for (id) |ch| {
        try std.testing.expect(isInAlphabet(ch));
    }
}

test "rejects length 0" {
    const alloc = std.testing.allocator;
    const result = generate(alloc, 0);
    try std.testing.expectError(error.InvalidLength, result);
}

test "rejects length 129" {
    const alloc = std.testing.allocator;
    const result = generate(alloc, 129);
    try std.testing.expectError(error.InvalidLength, result);
}

test "batch generation returns correct count" {
    const alloc = std.testing.allocator;
    const ids = try generateBatch(alloc, 500, 21);
    defer {
        for (ids) |id| alloc.free(id);
        alloc.free(ids);
    }
    try std.testing.expectEqual(@as(usize, 500), ids.len);
}

test "batch elements have correct length" {
    const alloc = std.testing.allocator;
    const ids = try generateBatch(alloc, 10, 21);
    defer {
        for (ids) |id| alloc.free(id);
        alloc.free(ids);
    }
    for (ids) |id| {
        try std.testing.expectEqual(@as(usize, 21), id.len);
    }
}

test "batch uniqueness" {
    const alloc = std.testing.allocator;
    const ids = try generateBatch(alloc, 500, 21);
    defer {
        for (ids) |id| alloc.free(id);
        alloc.free(ids);
    }

    var seen = std.StringHashMap(void).init(alloc);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        seen.deinit();
    }

    for (ids) |id| {
        const duped = try alloc.dupe(u8, id);
        const result = try seen.getOrPut(duped);
        if (result.found_existing) {
            alloc.free(duped);
        }
        try std.testing.expect(!result.found_existing);
    }
}

test "rejects batch count 0" {
    const alloc = std.testing.allocator;
    const result = generateBatch(alloc, 0, 21);
    try std.testing.expectError(error.InvalidCount, result);
}

test "rejects batch count 1001" {
    const alloc = std.testing.allocator;
    const result = generateBatch(alloc, 1001, 21);
    try std.testing.expectError(error.InvalidCount, result);
}
