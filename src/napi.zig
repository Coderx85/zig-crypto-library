const std = @import("std");
const c = @import("c.zig").c;
const t = @import("translate.zig");
const snowflake = @import("internal/snowflake.zig");
const nanoid = @import("internal/nanoid.zig");

const batch_allocator = std.heap.page_allocator;

var snowflake_state: snowflake.SnowflakeState = undefined;
var snowflake_initialized: bool = false;

fn ensureSnowflakeInit() void {
    if (!snowflake_initialized) {
        snowflake_state = snowflake.SnowflakeState.init();
        snowflake_initialized = true;
    }
}

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    t.registerFunction(env, exports, "Id", Snowflake_Id) catch return null;
    t.registerFunction(env, exports, "Batch", Snowflake_Batch) catch return null;
    t.registerFunction(env, exports, "nanoid", Nanoid_Single) catch return null;
    t.registerFunction(env, exports, "nanoidBatchBuffer", Nanoid_BatchBuffer) catch return null;
    t.registerFunction(env, exports, "nanoidBatchStrings", Nanoid_BatchStrings) catch return null;
    return exports;
}

fn Nanoid_BatchStrings(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
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

    const len = @as(usize, @intCast(length));

    var array: c.napi_value = undefined;
    if (c.napi_create_array_with_length(env, @intCast(count), &array) != c.napi_ok) {
        return null;
    }

    var buf: [nanoid.MAX_LENGTH]u8 = undefined;
    for (0..@as(usize, @intCast(count))) |i| {
        const slice = buf[0..len];
        nanoid.generate(slice) catch {
            t.throw(env, "nanoid generation failed") catch {};
            return null;
        };

        var str: c.napi_value = undefined;
        if (c.napi_create_string_utf8(env, slice.ptr, slice.len, &str) != c.napi_ok) {
            return null;
        }
        if (c.napi_set_element(env, array, @intCast(i), str) != c.napi_ok) {
            return null;
        }
    }

    return array;
}

fn batchBufferFinalizer(env: c.napi_env, data: ?*anyopaque, hint: ?*anyopaque) callconv(.c) void {
    _ = env;
    const len = @intFromPtr(hint);
    const ptr = @as([*]u8, @ptrCast(data));
    batch_allocator.free(ptr[0..len]);
}

fn singleBufferFinalizer(env: c.napi_env, data: ?*anyopaque, hint: ?*anyopaque) callconv(.c) void {
    _ = env;
    _ = hint;
    const ptr = @as([*]u8, @ptrCast(data)).ptr;
    const alloc_len = @as(usize, @intCast(nanoid.MAX_LENGTH));
    batch_allocator.free(ptr[0..alloc_len]);
}

fn Snowflake_Id(env: c.napi_env, _info: c.napi_callback_info) callconv(.c) c.napi_value {
    _ = _info;
    ensureSnowflakeInit();
    const id = snowflake_state.generate();
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

    ensureSnowflakeInit();
    const ids = snowflake_state.generateBatch(batch_allocator, @intCast(count));
    defer batch_allocator.free(ids);

    return t.createBigintArray(env, ids) catch return null;
}

fn Nanoid_Single(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    var length: i32 = @intCast(nanoid.DEFAULT_LENGTH);
    if (argc >= 1) {
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

    var buf: [nanoid.MAX_LENGTH]u8 = undefined;
    const slice = buf[0..@as(usize, @intCast(length))];
    nanoid.generate(slice) catch {
        t.throw(env, "nanoid generation failed") catch {};
        return null;
    };

    return t.createString(env, slice) catch return null;
}

fn Nanoid_BatchBuffer(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
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

    const slab = nanoid.generateBuffer(batch_allocator, @intCast(count), @intCast(length)) catch {
        t.throw(env, "nanoid batch buffer generation failed") catch {};
        return null;
    };

    const total_len = slab.len;
    return t.createExternalBuffer(
        env,
        slab,
        batchBufferFinalizer,
        @ptrFromInt(total_len),
    ) catch return null;
}
