const base64Module = @import("codec/base64.zig");
const base58Module = @import("codec/base58.zig");

pub const CodecFormat = enum {
  base64,
  base64_url_safe,
  base58,
  base58_hex
};

const codecFnInput = struct {
  format: CodecFormat,
  len: usize,
};

pub fn codecOutputLen(input: codecFnInput) usize {
  return switch (input.format) {
    .base64 => base64Module.encodeLen(input.len),
    .base64_url_safe => base64Module.encodeLen(input.len),
    .base58 => base58Module.encodeLen(input.len),
    .base58_hex => base58Module.encodeLen(input.len),
  };
}

pub fn codecInputLen(input: codecFnInput) usize {
  return switch (input.format) {
    .base64 => base64Module.decodeLen(input.len),
    .base64_url_safe => base64Module.decodeLen(input.len),
    .base58 => base58Module.decodeLen(input.len),
    .base58_hex => base58Module.decodeLen(input.len),
  };
}

const codecEncodeArgs = struct {
  format: CodecFormat,
  input: []const u8,
  output: []u8,
};

pub fn codecEncode(args: codecEncodeArgs) !usize {
  return switch (args.format) {
    .base64 => base64Module.encode(args.input, args.output),
    .base64_url_safe => base64Module.encodeUrlSafe(args.input, args.output),
    .base64_simd => base64Module.encodeSimd(args.input, args.output, .standard),
    .base58 => base58Module.encode(args.input, args.output),
    .base58_hex => base58Module.encodeHex(args.input, args.output),
  };
}

pub fn codecDecode(args: codecEncodeArgs) !usize {
  return switch (args.format) {
    .base64 => base64Module.decode(args.input, args.output),
    .base64_url_safe => base64Module.decodeUrlSafe(args.input, args.output),
    .base64_simd => base64Module.decodeSimd(args.input, args.output, .standard),
    .base58 => base58Module.decode(args.input, args.output),
    .base58_hex => base58Module.decodeHex(args.input, args.output),
  };
}