const std = @import("std");

const SpinLock = std.atomic.Mutex;

pub const EPOCH: u64 = 1767225600000;

// Snowflake structure: 41 bits timestamp, 10 bits node ID, 12 bits sequence
const TIMESTAMP_BITS: u6 = 41;
const NODE_ID_BITS: u6 = 10;
const SEQUENCE_BITS: u6 = 12;

const NODE_ID_SHIFT: u6 = SEQUENCE_BITS;
const TIMESTAMP_SHIFT: u6 = NODE_ID_BITS + SEQUENCE_BITS;

const MAX_SEQUENCE: u12 = (1 << SEQUENCE_BITS) - 1;
const MAX_NODE_ID: u10 = (1 << NODE_ID_BITS) - 1;

pub const SnowflakeState = struct {
    last_timestamp: u64 = 0, 
    sequence: u12 = 0,
    node_id: u10,
    mutex: SpinLock = .unlocked,

    pub fn init() SnowflakeState {
        return SnowflakeState{
        .node_id = deriveNodeId(),
        };
    }

    fn lock(m: *SpinLock) void {
        while (!m.tryLock()) {}
    }

    pub fn generate(self: *SnowflakeState) u64 {
        lock(&self.mutex);
        defer self.mutex.unlock();

        var current_ms = timestampMs();

        if (current_ms < self.last_timestamp) {
            current_ms = waitNextMs(self.last_timestamp);
        }

        if (current_ms == self.last_timestamp) {
            self.sequence += 1;
            if (self.sequence > MAX_SEQUENCE) {
                current_ms = waitNextMs(self.last_timestamp);
                self.sequence = 0;
            }
        } else {
            self.sequence = 0;
        }

        self.last_timestamp = current_ms;
        return pack(current_ms, self.node_id, self.sequence);
    }

    pub fn generateBatch(self: *SnowflakeState, allocator: std.mem.Allocator, count: u16) []u64 {
        const ids = allocator.alloc(u64, count) catch {
            @panic("OOM in snowflake batch");
        };
        for (ids) |*id| {
            id.* = self.generate();
        }
        return ids;
    }
};

fn deriveNodeId() u10 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buf) catch return 0;
    const hash = std.hash.Wyhash.hash(0, hostname);
    return @as(u10, @truncate(hash));
}

fn timestampMs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1000000;
}

fn waitNextMs(last_timestamp: u64) u64 {
    var current = timestampMs();
    while (current <= last_timestamp) {
        current = timestampMs();
    }
    return current;
}

fn pack(timestamp: u64, node_id: u10, sequence: u12) u64 {
    return (timestamp - EPOCH) << TIMESTAMP_SHIFT | @as(u64, node_id) << NODE_ID_SHIFT | sequence;
}

test "generate returns non-zero id" {
    var state = SnowflakeState.init();
    const id = state.generate();
    try std.testing.expect(id > 0);
}

test "generate 1000 ids are unique" {
    var state = SnowflakeState.init();
    var seen = std.AutoHashMap(u64, void).init(std.testing.allocator);
    defer seen.deinit();

    for (0..1000) |_| {
        const id = state.generate();
        try std.testing.expect(!seen.contains(id));
        try seen.put(id, {});
    }
}

test "generate ids are monotonic" {
    var state = SnowflakeState.init();
    var prev = state.generate();
    for (0..100) |_| {
        const id = state.generate();
        try std.testing.expect(id > prev);
        prev = id;
    }
}

test "generateBatch returns correct count" {
    var state = SnowflakeState.init();
    const ids = state.generateBatch(std.testing.allocator, @as(u16, 500));
    defer std.testing.allocator.free(ids);
    try std.testing.expectEqual(@as(usize, 500), ids.len);
}

test "generateBatch ids are unique" {
    var state = SnowflakeState.init();
    const ids = state.generateBatch(std.testing.allocator, @as(u16, 500));
    defer std.testing.allocator.free(ids);

    var seen = std.AutoHashMap(u64, void).init(std.testing.allocator);
    defer seen.deinit();
    for (ids) |id| {
        try std.testing.expect(!seen.contains(id));
        try seen.put(id, {});
    }
}
