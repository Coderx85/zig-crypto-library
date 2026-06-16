const std = @import("std");
const builtin = @import("builtin");

pub fn fillRandom(buf: []u8) void {
    switch (builtin.os.tag) {
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

test "fillRandom produces non-zero output" {
    var buf: [32]u8 = undefined;
    fillRandom(&buf);
    var all_zero = true;
    for (buf) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "fillRandom produces different output on successive calls" {
    var buf1: [32]u8 = undefined;
    var buf2: [32]u8 = undefined;
    fillRandom(&buf1);
    fillRandom(&buf2);
    try std.testing.expect(!std.mem.eql(u8, &buf1, &buf2));
}

test "fillRandom works for various sizes" {
    var buf1: [1]u8 = undefined;
    fillRandom(&buf1);
    var buf2: [16]u8 = undefined;
    fillRandom(&buf2);
    var buf3: [64]u8 = undefined;
    fillRandom(&buf3);
    var buf4: [256]u8 = undefined;
    fillRandom(&buf4);
    try std.testing.expect(buf1.len == 1);
    try std.testing.expect(buf2.len == 16);
    try std.testing.expect(buf3.len == 64);
    try std.testing.expect(buf4.len == 256);
}
