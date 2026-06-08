const std = @import("std");
const c = @import("c.zig").c;
const t = @import("translate.zig");
const snowflake = @import("snowflake.zig");

var state: snowflake.SnowflakeState = undefined;
var initialized: bool = false;

fn ensureInit() void {
    if (!initialized) {
        state = snowflake.SnowflakeState.init();
        initialized = true;
    }
}

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    t.registerFunction(env, exports, "Id", Snowflake_Id) catch return null;
    t.registerFunction(env, exports, "Batch", Snowflake_Batch) catch return null;
    return exports;
}

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
