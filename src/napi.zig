const std = @import("std");
const c = @import("c.zig").c;
const t = @import("translate.zig");
const snowflake = @import("snowflake.zig");
const nanoid = @import("nanoid.zig");

var state: snowflake.SnowflakeState = undefined;
var initialized: bool = false;

fn ensureInit() void {
    if (!initialized) {
        state = snowflake.SnowflakeState.init();
        initialized = true;
    }
}

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    // Snowflake exports
    t.registerFunction(env, exports, "Id", Snowflake_Id) catch return null;
    t.registerFunction(env, exports, "Batch", Snowflake_Batch) catch return null;
    // Nanoid exports
    t.registerFunction(env, exports, "nanoid", Nanoid_Single) catch return null;
    t.registerFunction(env, exports, "nanoidBatch", Nanoid_Batch) catch return null;
    return exports;
}

// ── Snowflake ──────────────────────────────────────────────────

fn Snowflake_Id(env: c.napi_env, _info: c.napi_callback_info) callconv(.c) c.napi_value {
    _ = _info;
    ensureInit();
    const id = state.generate();
    return t.createBigint(env, id) catch return null;
}

fn Snowflake_Batch(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    const args = t.extractArgs(env, info, 1) catch return null;
    const count = t.getInt32(env, args[0]) catch return null;

    if (count < 1) {
        t.throwRangeError(env, "count must be >= 1") catch {};
        return null;
    }
    if (count > 1000) {
        t.throwRangeError(env, "count must be <= 1000") catch {};
        return null;
    }

    ensureInit();
    const ids = state.generateBatch(std.heap.page_allocator, @intCast(count));
    defer std.heap.page_allocator.free(ids);

    return t.createBigintArray(env, ids) catch return null;
}

// ── Nanoid ─────────────────────────────────────────────────────

fn Nanoid_Single(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    // Parse optional length argument (default 21)
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    var length: i32 = @intCast(nanoid.DEFAULT_LENGTH);
    if (argc >= 1) {
        // Check if argument is undefined
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[0], &arg_type) == c.napi_ok) {
            if (arg_type != c.napi_undefined) {
                length = t.getInt32(env, argv[0]) catch return null;
            }
        }
    }

    if (length < 1) {
        t.throwRangeError(env, "length must be >= 1") catch {};
        return null;
    }
    if (length > 128) {
        t.throwRangeError(env, "length must be <= 128") catch {};
        return null;
    }

    const allocator = std.heap.page_allocator;
    const id = nanoid.generate(allocator, @intCast(length)) catch {
        t.throw(env, "nanoid generation failed") catch {};
        return null;
    };
    defer allocator.free(id);

    return t.createString(env, id) catch return null;
}

fn Nanoid_Batch(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    // Parse args: count (required), length (optional, default 21)
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument") catch {};
        return null;
    }

    const count = t.getInt32(env, argv[0]) catch return null;
    if (count < 1) {
        t.throwRangeError(env, "count must be >= 1") catch {};
        return null;
    }
    if (count > 1000) {
        t.throwRangeError(env, "count must be <= 1000") catch {};
        return null;
    }

    var length: i32 = @intCast(nanoid.DEFAULT_LENGTH);
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type != c.napi_undefined) {
                length = t.getInt32(env, argv[1]) catch return null;
            }
        }
    }

    if (length < 1) {
        t.throwRangeError(env, "length must be >= 1") catch {};
        return null;
    }
    if (length > 128) {
        t.throwRangeError(env, "length must be <= 128") catch {};
        return null;
    }

    const allocator = std.heap.page_allocator;
    const ids = nanoid.generateBatch(allocator, @intCast(count), @intCast(length)) catch {
        t.throw(env, "nanoid batch generation failed") catch {};
        return null;
    };
    defer {
        for (ids) |id| allocator.free(id);
        allocator.free(ids);
    }

    // Convert [][]u8 to [][]const u8 for createStringArray
    const const_ids: []const []const u8 = @ptrCast(ids);
    return t.createStringArray(env, const_ids) catch return null;
}
