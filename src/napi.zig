const std = @import("std");
const c = @import("c.zig").c;
const t = @import("translate.zig");
const snowflake = @import("internal/snowflake.zig");
const nanoid = @import("internal/nanoid.zig");
const base64 = @import("codec/base64.zig");
const base58 = @import("codec/base58.zig");
const hex = @import("codec/hex.zig");
const zst = @import("token/zst.zig");

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
    t.registerFunction(env, exports, "base64Encode", Base64_Encode) catch return null;
    t.registerFunction(env, exports, "base64EncodeStr", Base64_EncodeStr) catch return null;
    t.registerFunction(env, exports, "base64Decode", Base64_Decode) catch return null;
    t.registerFunction(env, exports, "base64DecodeStr", Base64_DecodeStr) catch return null;
    t.registerFunction(env, exports, "base64DecodeConst", Base64_DecodeConst) catch return null;
    t.registerFunction(env, exports, "base64DecodeConstStr", Base64_DecodeConstStr) catch return null;
    t.registerFunction(env, exports, "base58Encode", Base58_Encode) catch return null;
    t.registerFunction(env, exports, "base58Decode", Base58_Decode) catch return null;
    t.registerFunction(env, exports, "hexEncode", Hex_Encode) catch return null;
    t.registerFunction(env, exports, "hexDecode", Hex_Decode) catch return null;
    t.registerFunction(env, exports, "zstSign", Zst_Sign) catch return null;
    t.registerFunction(env, exports, "zstVerify", Zst_Verify) catch return null;
    t.registerFunction(env, exports, "zstDecode", Zst_Decode) catch return null;
    t.registerFunction(env, exports, "zstGenerateKey", Zst_GenerateKey) catch return null;
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

fn Base64_Encode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (Buffer)") catch {};
        return null;
    }

    const input = t.getBuffer(env, argv[0]) catch return null;

    var encoding: base64.Encoding = .standard;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "urlSafe") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "urlSafe") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        encoding = .url_safe;
                    }
                }
            }
        }
    }

    const out_len = base64.encodeLen(input.len);
    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, out_len, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..out_len];

    switch (encoding) {
        .standard => _ = base64.encode(input, buf, .standard) catch {
            return null;
        },
        .url_safe => _ = base64.encode(input, buf, .url_safe) catch {
            return null;
        },
    }

    return result;
}

fn Base64_EncodeStr(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (Buffer)") catch {};
        return null;
    }

    const input = t.getBuffer(env, argv[0]) catch return null;

    var encoding: base64.Encoding = .standard;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "urlSafe") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "urlSafe") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        encoding = .url_safe;
                    }
                }
            }
        }
    }

    const out_len = base64.encodeLen(input.len);
    const STACK_THRESH: usize = 8192;

    if (out_len <= STACK_THRESH) {
        var stack_buf: [STACK_THRESH]u8 = undefined;
        const out = stack_buf[0..out_len];
        switch (encoding) {
            .standard => _ = base64.encode(input, out, .standard) catch {
                return null;
            },
            .url_safe => _ = base64.encode(input, out, .url_safe) catch {
                return null;
            },
        }
        return t.createString(env, out) catch return null;
    }

    const heap_buf = batch_allocator.alloc(u8, out_len) catch {
        t.throw(env, "Allocation failed") catch {};
        return null;
    };
    defer batch_allocator.free(heap_buf);

    switch (encoding) {
        .standard => _ = base64.encode(input, heap_buf, .standard) catch {
            return null;
        },
        .url_safe => _ = base64.encode(input, heap_buf, .url_safe) catch {
            return null;
        },
    }

    return t.createString(env, heap_buf) catch return null;
}

fn Base64_Decode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (Buffer)") catch {};
        return null;
    }

    const input = t.getBuffer(env, argv[0]) catch return null;

    var encoding: base64.Encoding = .standard;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "urlSafe") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "urlSafe") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        encoding = .url_safe;
                    }
                }
            }
        }
    }

    const max_out = base64.decodeLen(input.len);
    if (max_out == 0) {
        return t.createArrayBuffer(env, "") catch return null;
    }

    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, max_out, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..max_out];

    const actual = switch (encoding) {
        .standard => base64.decodeSimd(input, buf, .standard) catch {
            return null;
        },
        .url_safe => base64.decodeSimd(input, buf, .url_safe) catch {
            return null;
        },
    };

    if (actual < max_out) {
        var trimmed: c.napi_value = undefined;
        if (c.napi_create_arraybuffer(env, actual, &ptr, &trimmed) != c.napi_ok) {
            return null;
        }
        @memcpy(@as([*]u8, @ptrCast(ptr.?))[0..actual], buf[0..actual]);
        return trimmed;
    }

    return result;
}

fn Base64_DecodeStr(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (string)") catch {};
        return null;
    }

    const input_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(input_str);

    var encoding: base64.Encoding = .standard;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "urlSafe") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "urlSafe") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        encoding = .url_safe;
                    }
                }
            }
        }
    }

    const max_out = base64.decodeLen(input_str.len);
    if (max_out == 0) {
        return t.createArrayBuffer(env, "") catch return null;
    }

    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, max_out, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..max_out];

    const actual = switch (encoding) {
        .standard => base64.decodeSimd(input_str, buf, .standard) catch {
            return null;
        },
        .url_safe => base64.decodeSimd(input_str, buf, .url_safe) catch {
            return null;
        },
    };

    if (actual < max_out) {
        var trimmed: c.napi_value = undefined;
        if (c.napi_create_arraybuffer(env, actual, &ptr, &trimmed) != c.napi_ok) {
            return null;
        }
        @memcpy(@as([*]u8, @ptrCast(ptr.?))[0..actual], buf[0..actual]);
        return trimmed;
    }

    return result;
}

fn Base64_DecodeConst(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (Buffer)") catch {};
        return null;
    }

    const input = t.getBuffer(env, argv[0]) catch return null;

    var encoding: base64.Encoding = .standard;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "urlSafe") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "urlSafe") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        encoding = .url_safe;
                    }
                }
            }
        }
    }

    const max_out = base64.decodeLen(input.len);
    if (max_out == 0) {
        return t.createArrayBuffer(env, "") catch return null;
    }

    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, max_out, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..max_out];

    const actual = switch (encoding) {
        .standard => base64.decodeConstantTime(input, buf, .standard) catch {
            return null;
        },
        .url_safe => base64.decodeConstantTime(input, buf, .url_safe) catch {
            return null;
        },
    };

    if (actual < max_out) {
        var trimmed: c.napi_value = undefined;
        if (c.napi_create_arraybuffer(env, actual, &ptr, &trimmed) != c.napi_ok) {
            return null;
        }
        @memcpy(@as([*]u8, @ptrCast(ptr.?))[0..actual], buf[0..actual]);
        return trimmed;
    }

    return result;
}

fn Base64_DecodeConstStr(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (string)") catch {};
        return null;
    }

    const input_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(input_str);

    var encoding: base64.Encoding = .standard;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "urlSafe") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "urlSafe") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        encoding = .url_safe;
                    }
                }
            }
        }
    }

    const max_out = base64.decodeLen(input_str.len);
    if (max_out == 0) {
        return t.createArrayBuffer(env, "") catch return null;
    }

    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, max_out, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..max_out];

    const actual = switch (encoding) {
        .standard => base64.decodeConstantTime(input_str, buf, .standard) catch {
            return null;
        },
        .url_safe => base64.decodeConstantTime(input_str, buf, .url_safe) catch {
            return null;
        },
    };

    if (actual < max_out) {
        var trimmed: c.napi_value = undefined;
        if (c.napi_create_arraybuffer(env, actual, &ptr, &trimmed) != c.napi_ok) {
            return null;
        }
        @memcpy(@as([*]u8, @ptrCast(ptr.?))[0..actual], buf[0..actual]);
        return trimmed;
    }

    return result;
}

fn Base58_Encode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (Buffer)") catch {};
        return null;
    }

    const input = t.getBuffer(env, argv[0]) catch return null;
    const out_len = base58.encodeLen(input.len);
    const STACK_THRESH: usize = 8192;

    if (out_len <= STACK_THRESH) {
        var stack_buf: [STACK_THRESH]u8 = undefined;
        const actual = base58.encode(input, stack_buf[0..out_len]) catch {
            t.throw(env, "base58 encode failed") catch {};
            return null;
        };
        return t.createString(env, stack_buf[0..actual]) catch return null;
    }

    const heap_buf = batch_allocator.alloc(u8, out_len) catch {
        t.throw(env, "Allocation failed") catch {};
        return null;
    };
    defer batch_allocator.free(heap_buf);

    const actual = base58.encode(input, heap_buf) catch {
        t.throw(env, "base58 encode failed") catch {};
        return null;
    };
    return t.createString(env, heap_buf[0..actual]) catch return null;
}

fn Base58_Decode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (string)") catch {};
        return null;
    }

    const input_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(input_str);

    const max_out = base58.decodeLen(input_str.len);
    if (max_out == 0) {
        return t.createArrayBuffer(env, "") catch return null;
    }

    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, max_out, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..max_out];

    const actual = base58.decode(input_str, buf) catch {
        t.throw(env, "base58 decode failed") catch {};
        return null;
    };

    if (actual < max_out) {
        var trimmed: c.napi_value = undefined;
        if (c.napi_create_arraybuffer(env, actual, &ptr, &trimmed) != c.napi_ok) {
            return null;
        }
        @memcpy(@as([*]u8, @ptrCast(ptr.?))[0..actual], buf[0..actual]);
        return trimmed;
    }

    return result;
}

fn Hex_Encode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 2;
    var argv: [2]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (Buffer)") catch {};
        return null;
    }

    const input = t.getBuffer(env, argv[0]) catch return null;

    var case: hex.Case = .lower;
    if (argc >= 2) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[1], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                if (t.hasNamedProperty(env, argv[1], "upper") catch false) {
                    const prop = t.getNamedProperty(env, argv[1], "upper") catch return null;
                    if (t.getBool(env, prop) catch false) {
                        case = .upper;
                    }
                }
            }
        }
    }

    const out_len = hex.encodeLen(input.len);
    const STACK_THRESH: usize = 8192;

    if (out_len <= STACK_THRESH) {
        var stack_buf: [STACK_THRESH]u8 = undefined;
        const out = stack_buf[0..out_len];
        switch (case) {
            .lower => _ = hex.encode(input, out, .lower) catch return null,
            .upper => _ = hex.encode(input, out, .upper) catch return null,
        }
        return t.createString(env, out) catch return null;
    }

    const heap_buf = batch_allocator.alloc(u8, out_len) catch {
        t.throw(env, "Allocation failed") catch {};
        return null;
    };
    defer batch_allocator.free(heap_buf);

    switch (case) {
        .lower => _ = hex.encode(input, heap_buf, .lower) catch return null,
        .upper => _ = hex.encode(input, heap_buf, .upper) catch return null,
    }

    return t.createString(env, heap_buf) catch return null;
}

fn Hex_Decode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "Expected at least 1 argument (string)") catch {};
        return null;
    }

    const input_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(input_str);

    const max_out = hex.decodeLen(input_str.len) catch {
        t.throw(env, "Invalid hex length (must be even)") catch {};
        return null;
    };
    if (max_out == 0) {
        return t.createArrayBuffer(env, "") catch return null;
    }

    var ptr: ?*anyopaque = undefined;
    var result: c.napi_value = undefined;
    if (c.napi_create_arraybuffer(env, max_out, &ptr, &result) != c.napi_ok) {
        return null;
    }
    const buf = @as([*]u8, @ptrCast(ptr.?))[0..max_out];

    const actual = hex.decode(input_str, buf) catch {
        t.throw(env, "Hex decode failed: invalid character") catch {};
        return null;
    };

    if (actual < max_out) {
        var trimmed: c.napi_value = undefined;
        if (c.napi_create_arraybuffer(env, actual, &ptr, &trimmed) != c.napi_ok) {
            return null;
        }
        @memcpy(@as([*]u8, @ptrCast(ptr.?))[0..actual], buf[0..actual]);
        return trimmed;
    }

    return result;
}

fn Zst_Sign(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 3;
    var argv: [3]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 2) {
        t.throw(env, "zst.sign requires 2 arguments: (payload, key, options?)") catch {};
        return null;
    }

    const payload_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(payload_str);

    const key_bytes = t.getBuffer(env, argv[1]) catch {
        const key_str = t.getString(env, argv[1], batch_allocator) catch {
            t.throw(env, "key must be a Buffer or string") catch {};
            return null;
        };
        defer batch_allocator.free(key_str);
        const token = zst.sign(batch_allocator, payload_str, key_str, .{}) catch |err| {
            t.throw(env, @typeName(@TypeOf(err))) catch {};
            return null;
        };
        defer batch_allocator.free(token);
        return t.createString(env, token) catch return null;
    };

    var options: zst.SignOptions = .{};
    if (argc >= 3) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[2], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                options = .{
                    .audience = t.getOptionalString(env, argv[2], "audience", batch_allocator) catch null,
                    .issuer = t.getOptionalString(env, argv[2], "issuer", batch_allocator) catch null,
                    .subject = t.getOptionalString(env, argv[2], "subject", batch_allocator) catch null,
                    .jwtid = t.getOptionalString(env, argv[2], "jwtid", batch_allocator) catch null,
                    .rev = t.getOptionalUint64(env, argv[2], "rev") catch null,
                };
            }
        }
    }
    defer {
        if (options.audience) |aud| batch_allocator.free(aud);
        if (options.issuer) |iss| batch_allocator.free(iss);
        if (options.subject) |sub| batch_allocator.free(sub);
        if (options.jwtid) |jti| batch_allocator.free(jti);
    }

    const token = zst.sign(batch_allocator, payload_str, key_bytes, options) catch |err| {
        t.throw(env, @typeName(@TypeOf(err))) catch {};
        return null;
    };
    defer batch_allocator.free(token);

    return t.createString(env, token) catch return null;
}

fn Zst_Verify(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 3;
    var argv: [3]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 2) {
        t.throw(env, "zst.verify requires 2 arguments: (token, key, options?)") catch {};
        return null;
    }

    const token_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(token_str);

    const key_bytes = t.getBuffer(env, argv[1]) catch {
        const key_str = t.getString(env, argv[1], batch_allocator) catch {
            t.throw(env, "key must be a Buffer or string") catch {};
            return null;
        };
        defer batch_allocator.free(key_str);
        _ = zst.verify(batch_allocator, token_str, key_str, .{}) catch |err| {
            t.throw(env, @typeName(@TypeOf(err))) catch {};
            return null;
        };
        return null;
    };

    var options: zst.VerifyOptions = .{};
    if (argc >= 3) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[2], &arg_type) == c.napi_ok) {
            if (arg_type == c.napi_object) {
                options = .{
                    .audience = t.getOptionalString(env, argv[2], "audience", batch_allocator) catch null,
                    .issuer = t.getOptionalString(env, argv[2], "issuer", batch_allocator) catch null,
                    .subject = t.getOptionalString(env, argv[2], "subject", batch_allocator) catch null,
                    .jwtid = t.getOptionalString(env, argv[2], "jwtid", batch_allocator) catch null,
                    .current_rev = t.getOptionalUint64(env, argv[2], "currentRev") catch 0 orelse 0,
                    .clock_tolerance = t.getOptionalUint64(env, argv[2], "clockTolerance") catch 0 orelse 0,
                    .ignore_expiration = getOptionalBool(env, argv[2], "ignoreExpiration") catch false,
                    .ignore_not_before = getOptionalBool(env, argv[2], "ignoreNotBefore") catch false,
                };
            }
        }
    }
    defer {
        if (options.audience) |aud| batch_allocator.free(aud);
        if (options.issuer) |iss| batch_allocator.free(iss);
        if (options.subject) |sub| batch_allocator.free(sub);
        if (options.jwtid) |jti| batch_allocator.free(jti);
    }

    const result = zst.verify(batch_allocator, token_str, key_bytes, options) catch |err| {
        t.throw(env, @typeName(@TypeOf(err))) catch {};
        return null;
    };
    defer zst.freeClaims(batch_allocator, result.payload);

    var obj: c.napi_value = undefined;
    if (c.napi_create_object(env, &obj) != c.napi_ok) return null;

    if (result.payload.sub) |sub| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_string_utf8(env, sub.ptr, sub.len, &val);
        _ = c.napi_set_named_property(env, obj, "sub", val);
    }
    if (result.payload.aud) |aud| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_string_utf8(env, aud.ptr, aud.len, &val);
        _ = c.napi_set_named_property(env, obj, "aud", val);
    }
    if (result.payload.exp) |exp| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_double(env, @floatFromInt(exp), &val);
        _ = c.napi_set_named_property(env, obj, "exp", val);
    }
    if (result.payload.iat) |iat| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_double(env, @floatFromInt(iat), &val);
        _ = c.napi_set_named_property(env, obj, "iat", val);
    }
    if (result.payload.rev) |rev| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_double(env, @floatFromInt(rev), &val);
        _ = c.napi_set_named_property(env, obj, "rev", val);
    }
    if (result.payload.iss) |iss| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_string_utf8(env, iss.ptr, iss.len, &val);
        _ = c.napi_set_named_property(env, obj, "iss", val);
    }
    if (result.payload.nbf) |nbf| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_double(env, @floatFromInt(nbf), &val);
        _ = c.napi_set_named_property(env, obj, "nbf", val);
    }
    if (result.payload.jti) |jti| {
        var val: c.napi_value = undefined;
        _ = c.napi_create_string_utf8(env, jti.ptr, jti.len, &val);
        _ = c.napi_set_named_property(env, obj, "jti", val);
    }

    return obj;
}

fn Zst_Decode(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    if (argc < 1) {
        t.throw(env, "zst.decode requires 1 argument: (token)") catch {};
        return null;
    }

    const token_str = t.getString(env, argv[0], batch_allocator) catch return null;
    defer batch_allocator.free(token_str);

    const header = zst.decode(token_str) catch |err| {
        t.throw(env, @typeName(@TypeOf(err))) catch {};
        return null;
    };

    var obj: c.napi_value = undefined;
    if (c.napi_create_object(env, &obj) != c.napi_ok) return null;

    var ver_val: c.napi_value = undefined;
    _ = c.napi_create_string_utf8(env, header.ver.ptr, header.ver.len, &ver_val);
    _ = c.napi_set_named_property(env, obj, "ver", ver_val);

    var typ_val: c.napi_value = undefined;
    _ = c.napi_create_string_utf8(env, header.typ.ptr, header.typ.len, &typ_val);
    _ = c.napi_set_named_property(env, obj, "typ", typ_val);

    var mode_val: c.napi_value = undefined;
    _ = c.napi_create_string_utf8(env, header.mode.ptr, header.mode.len, &mode_val);
    _ = c.napi_set_named_property(env, obj, "mode", mode_val);

    var enc_val: c.napi_value = undefined;
    _ = c.napi_get_boolean(env, header.encrypted, &enc_val);
    _ = c.napi_set_named_property(env, obj, "encrypted", enc_val);

    return obj;
}

fn Zst_GenerateKey(env: c.napi_env, info: c.napi_callback_info) callconv(.c) c.napi_value {
    var argc: usize = 1;
    var argv: [1]c.napi_value = undefined;
    _ = c.napi_get_cb_info(env, info, &argc, &argv, null, null);

    var length: usize = zst.MIN_KEY_LEN;
    if (argc >= 1) {
        var arg_type: c.napi_valuetype = undefined;
        if (c.napi_typeof(env, argv[0], &arg_type) == c.napi_ok) {
            if (arg_type != c.napi_undefined) {
                const num = t.getDouble(env, argv[0]) catch 32.0;
                length = @intFromFloat(num);
            }
        }
    }

    if (length < zst.MIN_KEY_LEN) {
        t.throwRangeError(env, "Key length must be >= 32") catch {};
        return null;
    }

    const key = zst.generateKey(batch_allocator, length) catch {
        t.throw(env, "Failed to generate key") catch {};
        return null;
    };
    defer batch_allocator.free(key);

    return t.createArrayBuffer(env, key) catch return null;
}

fn getOptionalBool(env: c.napi_env, obj: c.napi_value, comptime name: [:0]const u8) !bool {
    if (!try t.hasNamedProperty(env, obj, name)) return false;
    const val = try t.getNamedProperty(env, obj, name);
    var val_type: c.napi_valuetype = undefined;
    if (c.napi_typeof(env, val, &val_type) != c.napi_ok) return false;
    if (val_type == c.napi_undefined or val_type == c.napi_null) return false;
    return t.getBool(env, val);
}
