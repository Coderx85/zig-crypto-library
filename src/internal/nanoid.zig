const std = @import("std");
const builtin = @import("builtin");

pub const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
comptime {
    if (ALPHABET.len != 64) @compileError("ALPHABET must be exactly 64 characters");
}

const LOOKUP: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    for (&table, 0..) |*b, i| {
        b.* = ALPHABET[@as(u8, @truncate(i & 0x3F))];
    }
    break :blk table;
};

pub const DEFAULT_LENGTH: usize = 21;
pub const MAX_LENGTH: usize = 128;
pub const MAX_BATCH: usize = 1000;

pub const NanoidError = error{ InvalidLength, InvalidCount, InvalidAlphabet, OutOfMemory };

const POOL_SIZE: usize = 65536;
threadlocal var rand_pool: [POOL_SIZE]u8 = undefined;
threadlocal var pool_offset: usize = POOL_SIZE;

threadlocal var fast_pool: [POOL_SIZE]u8 = undefined;
threadlocal var fast_offset: usize = POOL_SIZE;
threadlocal var fast_prng: std.Random.DefaultPrng = undefined;
threadlocal var fast_prng_ready: bool = false;

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
            _ = std.os.windows.BCryptGenRandom(null, buf.ptr, buf.len, 0x00000002);
        },
        else => @compileError("Unsupported OS for CSPRNG"),
    }
}

inline fn refillPool() void {
    fillRandom(rand_pool[0..]);
    pool_offset = 0;
}

inline fn refillFastPool() void {
    if (!fast_prng_ready) {
        var seed: u64 = undefined;
        fillRandom(std.mem.asBytes(&seed));
        fast_prng = std.Random.DefaultPrng.init(seed);
        fast_prng_ready = true;
    }
    fast_prng.fill(&fast_pool);
    fast_offset = 0;
}

pub const CustomAlphabet = struct {
    alphabet: []const u8,
    safe_cutoff: u8,
    mask: u8,
    is_power_of_two: bool,

    pub fn init(alphabet: []const u8) NanoidError!CustomAlphabet {
        if (alphabet.len < 2) return error.InvalidAlphabet;
        if (alphabet.len > 256) return error.InvalidAlphabet;
        const rem = 256 % alphabet.len;
        const cutoff: u8 = if (rem == 0) 0 else @intCast(256 - rem);
        return .{
            .alphabet = alphabet,
            .safe_cutoff = cutoff,
            .mask = @intCast(alphabet.len - 1),
            .is_power_of_two = rem == 0,
        };
    }

    pub fn generate(self: *const CustomAlphabet, buf: []u8) NanoidError!void {
        const len = buf.len;
        if (len < 1 or len > MAX_LENGTH) return error.InvalidLength;

        if (self.is_power_of_two) {
            if (pool_offset + len > POOL_SIZE) refillPool();
            writeMapped(buf, rand_pool[pool_offset..][0..len], self.mask, self.alphabet);
            pool_offset += len;
            return;
        }

        const cutoff = self.safe_cutoff;
        const alph = self.alphabet;
        const alph_len = alph.len;

        var pos: usize = 0;
        while (pos < len) {
            const avail = POOL_SIZE - pool_offset;
            if (avail < 1) refillPool();
            const want = (len - pos) * 256 / (cutoff);
            const take = @min(want + 1, POOL_SIZE - pool_offset);
            const end = pool_offset + take;
            var i = pool_offset;
            while (i < end and pos < len) : (i += 1) {
                const b = rand_pool[i];
                if (b < cutoff) {
                    buf[pos] = alph[b % alph_len];
                    pos += 1;
                }
            }
            pool_offset = end;
        }
    }

    pub fn generateBuffer(
        self: *const CustomAlphabet,
        allocator: std.mem.Allocator,
        count: usize,
        length: usize,
    ) NanoidError![]u8 {
        if (count < 1 or count > MAX_BATCH) return error.InvalidCount;
        if (length < 1 or length > MAX_LENGTH) return error.InvalidLength;

        const total = count * length;
        const slab = allocator.alloc(u8, total) catch return error.OutOfMemory;
        errdefer allocator.free(slab);

        if (self.is_power_of_two) {
            const mask = self.mask;
            const alph = self.alphabet;
            var filled: usize = 0;
            while (filled < total) {
                const chunk_len = @min(total - filled, POOL_SIZE);
                if (pool_offset + chunk_len > POOL_SIZE) refillPool();
                writeMapped(slab[filled..][0..chunk_len], rand_pool[pool_offset..][0..chunk_len], mask, alph);
                pool_offset += chunk_len;
                filled += chunk_len;
            }
            return slab;
        }

        const cutoff = self.safe_cutoff;
        const alph = self.alphabet;
        const alph_len = alph.len;

        var pos: usize = 0;
        while (pos < total) {
            const avail = POOL_SIZE - pool_offset;
            if (avail < 1) refillPool();
            const remaining = total - pos;
            const want = remaining * 256 / (cutoff);
            const take = @min(want + 1, POOL_SIZE - pool_offset);
            const end = pool_offset + take;
            var i = pool_offset;
            while (i < end and pos < total) : (i += 1) {
                const b = rand_pool[i];
                if (b < cutoff) {
                    slab[pos] = alph[b % alph_len];
                    pos += 1;
                }
            }
            pool_offset = end;
        }

        return slab;
    }
};

inline fn writeLookup(dst: []u8, src: []const u8) void {
    const n = dst.len;
    const aligned = n - (n & 7);
    var i: usize = 0;
    while (i < aligned) {
        comptime var j: usize = 0;
        inline while (j < 8) : (j += 1) {
            dst[i + j] = LOOKUP[src[i + j]];
        }
        i += 8;
    }
    while (i < n) : (i += 1) {
        dst[i] = LOOKUP[src[i]];
    }
}

inline fn writeMapped(dst: []u8, src: []const u8, mask: u8, alph: []const u8) void {
    const n = dst.len;
    const aligned = n - (n & 7);
    var i: usize = 0;
    while (i < aligned) {
        comptime var j: usize = 0;
        inline while (j < 8) : (j += 1) {
            dst[i + j] = alph[src[i + j] & mask];
        }
        i += 8;
    }
    while (i < n) : (i += 1) {
        dst[i] = alph[src[i] & mask];
    }
}

pub fn generate(buf: []u8) NanoidError!void {
    const len = buf.len;
    if (len < 1 or len > MAX_LENGTH) return error.InvalidLength;

    if (pool_offset + len > POOL_SIZE) refillPool();
    writeLookup(buf, rand_pool[pool_offset..][0..len]);
    pool_offset += len;
}

pub fn generateBuffer(allocator: std.mem.Allocator, count: usize, length: usize) NanoidError![]u8 {
    if (count < 1 or count > MAX_BATCH) return error.InvalidCount;
    if (length < 1 or length > MAX_LENGTH) return error.InvalidLength;

    const total = count * length;
    const slab = allocator.alloc(u8, total) catch return error.OutOfMemory;
    errdefer allocator.free(slab);

    var filled: usize = 0;
    while (filled < total) {
        const chunk_len = @min(total - filled, POOL_SIZE);
        if (pool_offset + chunk_len > POOL_SIZE) refillPool();
        writeLookup(slab[filled..][0..chunk_len], rand_pool[pool_offset..][0..chunk_len]);
        pool_offset += chunk_len;
        filled += chunk_len;
    }

    return slab;
}

fn isInAlphabet(ch: u8) bool {
    for (ALPHABET) |a| {
        if (ch == a) return true;
    }
    return false;
}

test "single generation returns correct length" {
    var buf: [21]u8 = undefined;
    try generate(&buf);
    try std.testing.expectEqual(@as(usize, 21), buf.len);
}

test "default length is 21" {
    try std.testing.expectEqual(@as(usize, 21), DEFAULT_LENGTH);
}

test "all characters are URL-safe" {
    var buf: [21]u8 = undefined;
    try generate(&buf);
    for (buf) |ch| {
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
        var buf: [21]u8 = undefined;
        try generate(&buf);
        const duped = try alloc.dupe(u8, &buf);
        const result = try seen.getOrPut(duped);
        if (result.found_existing) {
            alloc.free(duped);
        }
        try std.testing.expect(!result.found_existing);
    }
}

test "alphabet membership" {
    var buf: [128]u8 = undefined;
    try generate(&buf);
    for (buf) |ch| {
        try std.testing.expect(isInAlphabet(ch));
    }
}

test "rejects length 0" {
    const result = generate("");
    try std.testing.expectError(error.InvalidLength, result);
}

test "rejects length 129" {
    var buf: [129]u8 = undefined;
    const result = generate(&buf);
    try std.testing.expectError(error.InvalidLength, result);
}

test "buffer batch generation returns correct size" {
    const alloc = std.testing.allocator;
    const buf = try generateBuffer(alloc, 500, 21);
    defer alloc.free(buf);
    try std.testing.expectEqual(@as(usize, 500 * 21), buf.len);
}

test "buffer batch elements have correct length" {
    const alloc = std.testing.allocator;
    const buf = try generateBuffer(alloc, 10, 21);
    defer alloc.free(buf);
    for (0..10) |i| {
        const id = buf[i * 21 ..][0..21];
        try std.testing.expectEqual(@as(usize, 21), id.len);
    }
}

test "buffer batch uniqueness" {
    const alloc = std.testing.allocator;
    const buf = try generateBuffer(alloc, 500, 21);
    defer alloc.free(buf);

    var seen = std.StringHashMap(void).init(alloc);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        seen.deinit();
    }

    for (0..500) |i| {
        const id = buf[i * 21 ..][0..21];
        const duped = try alloc.dupe(u8, id);
        const result = try seen.getOrPut(duped);
        if (result.found_existing) {
            alloc.free(duped);
        }
        try std.testing.expect(!result.found_existing);
    }
}

test "rejects buffer batch count 0" {
    const alloc = std.testing.allocator;
    const result = generateBuffer(alloc, 0, 21);
    try std.testing.expectError(error.InvalidCount, result);
}

test "rejects buffer batch count 1001" {
    const alloc = std.testing.allocator;
    const result = generateBuffer(alloc, 1001, 21);
    try std.testing.expectError(error.InvalidCount, result);
}

// ── CustomAlphabet ──────────────────────────────────

test "CustomAlphabet init rejects too short" {
    const result = CustomAlphabet.init("a");
    try std.testing.expectError(error.InvalidAlphabet, result);
}

test "CustomAlphabet init rejects too long" {
    var buf: [257]u8 = undefined;
    @memset(&buf, 'a');
    const result = CustomAlphabet.init(&buf);
    try std.testing.expectError(error.InvalidAlphabet, result);
}

test "CustomAlphabet hex (power of 2)" {
    const hex = try CustomAlphabet.init("0123456789abcdef");
    try std.testing.expect(hex.is_power_of_two);
    try std.testing.expectEqual(@as(u8, 15), hex.mask);

    var buf: [16]u8 = undefined;
    try hex.generate(&buf);
    for (buf) |ch| {
        try std.testing.expect(ch == '-' or
            (ch >= '0' and ch <= '9') or
            (ch >= 'a' and ch <= 'f'));
    }
}

test "CustomAlphabet base36 (non-power of 2)" {
    const base36 = try CustomAlphabet.init("0123456789abcdefghijklmnopqrstuvwxyz");
    try std.testing.expect(!base36.is_power_of_two);
    try std.testing.expectEqual(@as(u8, 252), base36.safe_cutoff);

    var buf: [21]u8 = undefined;
    try base36.generate(&buf);
    for (buf) |ch| {
        try std.testing.expect(
            (ch >= '0' and ch <= '9') or
            (ch >= 'a' and ch <= 'z'));
    }
}

test "CustomAlphabet base58 (non-power of 2)" {
    const base58 = try CustomAlphabet.init("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz");
    try std.testing.expect(!base58.is_power_of_two);
    try std.testing.expectEqual(@as(u8, 232), base58.safe_cutoff);

    var buf: [21]u8 = undefined;
    try base58.generate(&buf);
    for (buf) |ch| {
        const ok = (ch >= '1' and ch <= '9') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= 'a' and ch <= 'z');
        try std.testing.expect(ok);
    }
}

test "CustomAlphabet uniqueness 1000 (power of 2)" {
    const hex = try CustomAlphabet.init("0123456789abcdef");
    const alloc = std.testing.allocator;
    var seen = std.StringHashMap(void).init(alloc);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen.deinit();
    }
    for (0..1000) |_| {
        var buf: [21]u8 = undefined;
        try hex.generate(&buf);
        const duped = try alloc.dupe(u8, &buf);
        const result = try seen.getOrPut(duped);
        if (result.found_existing) alloc.free(duped);
        try std.testing.expect(!result.found_existing);
    }
}

test "CustomAlphabet uniqueness 1000 (non-power of 2)" {
    const base36 = try CustomAlphabet.init("0123456789abcdefghijklmnopqrstuvwxyz");
    const alloc = std.testing.allocator;
    var seen = std.StringHashMap(void).init(alloc);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen.deinit();
    }
    for (0..1000) |_| {
        var buf: [21]u8 = undefined;
        try base36.generate(&buf);
        const duped = try alloc.dupe(u8, &buf);
        const result = try seen.getOrPut(duped);
        if (result.found_existing) alloc.free(duped);
        try std.testing.expect(!result.found_existing);
    }
}

test "CustomAlphabet buffer batch (power of 2)" {
    const hex = try CustomAlphabet.init("0123456789abcdef");
    const alloc = std.testing.allocator;
    const buf = try hex.generateBuffer(alloc, 100, 16);
    defer alloc.free(buf);
    try std.testing.expectEqual(@as(usize, 1600), buf.len);
    for (0..100) |i| {
        const id = buf[i * 16 ..][0..16];
        for (id) |ch| {
            const ok = (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f');
            try std.testing.expect(ok);
        }
    }
}

test "CustomAlphabet buffer batch (non-power of 2)" {
    const base36 = try CustomAlphabet.init("0123456789abcdefghijklmnopqrstuvwxyz");
    const alloc = std.testing.allocator;
    const buf = try base36.generateBuffer(alloc, 50, 21);
    defer alloc.free(buf);
    try std.testing.expectEqual(@as(usize, 1050), buf.len);
}
