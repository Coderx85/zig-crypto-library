const std = @import("std");
const c = @import("c.zig").c;

pub const Error = error{ExceptionThrown};

pub fn throw(env: c.napi_env, comptime msg: [:0]const u8) Error {
    _ = c.napi_throw_error(env, null, msg);
    return Error.ExceptionThrown;
}

pub fn throwRangeError(env: c.napi_env, comptime msg: [:0]const u8) Error {
    var msg_val: c.napi_value = undefined;
    _ = c.napi_create_string_utf8(env, msg, msg.len, &msg_val);
    var range_err: c.napi_value = undefined;
    _ = c.napi_create_range_error(env, null, msg_val, &range_err);
    _ = c.napi_throw(env, range_err);
    return Error.ExceptionThrown;
}

pub fn registerFunction(
    env: c.napi_env,
    exports: c.napi_value,
    comptime name: [:0]const u8,
    function: *const fn (c.napi_env, c.napi_callback_info) callconv(.c) c.napi_value,
) !void {
    var napi_fn: c.napi_value = undefined;
    if (c.napi_create_function(env, null, 0, function, null, &napi_fn) != c.napi_ok) {
        return throw(env, "Failed to create function " ++ name);
    }
    if (c.napi_set_named_property(env, exports, @ptrCast(name), napi_fn) != c.napi_ok) {
        return throw(env, "Failed to set " ++ name);
    }
}

pub fn getUndefined(env: c.napi_env) !c.napi_value {
    var result: c.napi_value = undefined;
    if (c.napi_get_undefined(env, &result) != c.napi_ok) {
        return throw(env, "Failed to get undefined");
    }
    return result;
}

pub fn extractArgs(env: c.napi_env, info: c.napi_callback_info, comptime count: usize) ![count]c.napi_value {
    var argc = count;
    var argv: [count]c.napi_value = undefined;
    if (c.napi_get_cb_info(env, info, &argc, &argv, null, null) != c.napi_ok) {
        return throw(env, "Failed to get args");
    }
    if (argc != count) {
        return throw(env, "Expected " ++ std.fmt.comptimePrint("{}\x00", .{count}) ++ " arguments");
    }
    return argv;
}

pub fn getInt32(env: c.napi_env, value: c.napi_value) !i32 {
    var result: i32 = undefined;
    if (c.napi_get_value_int32(env, value, &result) != c.napi_ok) {
        return throw(env, "Expected number");
    }
    return result;
}

pub fn createBigint(env: c.napi_env, value: u64) !c.napi_value {
    var result: c.napi_value = undefined;
    if (c.napi_create_bigint_uint64(env, value, &result) != c.napi_ok) {
        return throw(env, "Failed to create BigInt");
    }
    return result;
}

pub fn createBigintArray(env: c.napi_env, ids: []const u64) !c.napi_value {
    var array: c.napi_value = undefined;
    if (c.napi_create_array_with_length(env, @intCast(ids.len), &array) != c.napi_ok) {
        return throw(env, "Failed to create array");
    }
    for (ids, 0..) |id, i| {
        var bigint: c.napi_value = undefined;
        if (c.napi_create_bigint_uint64(env, id, &bigint) != c.napi_ok) {
            return throw(env, "Failed to create BigInt");
        }
        if (c.napi_set_element(env, array, @intCast(i), bigint) != c.napi_ok) {
            return throw(env, "Failed to set array element");
        }
    }
    return array;
}

pub fn createString(env: c.napi_env, str: []const u8) !c.napi_value {
    var result: c.napi_value = undefined;
    if (c.napi_create_string_utf8(env, str.ptr, str.len, &result) != c.napi_ok) {
        return throw(env, "Failed to create string");
    }
    return result;
}

pub fn createExternalBuffer(
    env: c.napi_env,
    data: []u8,
    finalizer: ?*const fn (c.napi_env, ?*anyopaque, ?*anyopaque) callconv(.c) void,
    hint: ?*anyopaque,
) !c.napi_value {
    var result: c.napi_value = undefined;
    if (c.napi_create_external_buffer(env, data.len, data.ptr, finalizer, hint, &result) != c.napi_ok) {
        return throw(env, "Failed to create external buffer");
    }
    return result;
}


