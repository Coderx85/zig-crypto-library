const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Napi Module Metadata
    const napi_include = b.option([]const u8, "napi-include", "Path to node-api-headers include directory");

    const napi_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_id",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/napi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (napi_include) |path| {
        napi_lib.root_module.addIncludePath(.{ .cwd_relative = path });
    }
    b.installArtifact(napi_lib);

    const rand_mod = b.addModule("rand", .{
        .root_source_file = b.path("src/crypto/rand.zig"),
        .target = target,
    });
    const rand_tests = b.addTest(.{ .root_module = rand_mod });
    const run_rand_tests = b.addRunArtifact(rand_tests);

    const snowflake_mod = b.addModule("snowflake", .{
        .root_source_file = b.path("src/id/snowflake.zig"),
        .target = target,
    });
    const snowflake_tests = b.addTest(.{ .root_module = snowflake_mod });
    const run_snowflake_tests = b.addRunArtifact(snowflake_tests);

    const nanoid_mod = b.addModule("nanoid", .{
        .root_source_file = b.path("src/id/nanoid.zig"),
        .target = target,
    });
    nanoid_mod.addImport("rand", rand_mod);
    const nanoid_tests = b.addTest(.{ .root_module = nanoid_mod });
    const run_nanoid_tests = b.addRunArtifact(nanoid_tests);

    const hex_mod = b.addModule("codec_hex", .{
        .root_source_file = b.path("src/codec/hex.zig"),
        .target = target,
    });
    const hex_tests = b.addTest(.{ .root_module = hex_mod });
    const run_hex_tests = b.addRunArtifact(hex_tests);

    // NOTE: base64_mod and token_mod excluded from standalone test targets
    // due to cross-directory imports (../c.zig). They compile fine when
    // imported by napi.zig. Run their tests via the N-API build instead.

    // ── ZST module test targets ──────────────────────────

    const xchacha20_mod = b.addModule("xchacha20", .{
        .root_source_file = b.path("src/token/xchacha20.zig"),
        .target = target,
    });
    const xchacha20_tests = b.addTest(.{ .root_module = xchacha20_mod });
    const run_xchacha20_tests = b.addRunArtifact(xchacha20_tests);

    const blake2b_mod = b.addModule("blake2b", .{
        .root_source_file = b.path("src/crypto/blake2b.zig"),
        .target = target,
    });
    const blake2b_tests = b.addTest(.{ .root_module = blake2b_mod });
    const run_blake2b_tests = b.addRunArtifact(blake2b_tests);

    const zst_mod = b.addModule("zst", .{
        .root_source_file = b.path("src/token/zst.zig"),
        .target = target,
    });
    zst_mod.addImport("blake2b", blake2b_mod);
    zst_mod.addImport("xchacha20", xchacha20_mod);
    zst_mod.addImport("rand", rand_mod);
    const zst_tests = b.addTest(.{ .root_module = zst_mod });
    const run_zst_tests = b.addRunArtifact(zst_tests);

    const zst_claims_mod = b.addModule("zst_claims", .{
        .root_source_file = b.path("src/token/claims.zig"),
        .target = target,
    });
    const zst_claims_tests = b.addTest(.{ .root_module = zst_claims_mod });
    const run_zst_claims_tests = b.addRunArtifact(zst_claims_tests);

    const zst_errors_mod = b.addModule("zst_errors", .{
        .root_source_file = b.path("src/token/errors.zig"),
        .target = target,
    });
    const zst_errors_tests = b.addTest(.{ .root_module = zst_errors_mod });
    const run_zst_errors_tests = b.addRunArtifact(zst_errors_tests);

    // ── Test step ────────────────────────────────────────

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_snowflake_tests.step);
    test_step.dependOn(&run_nanoid_tests.step);
    test_step.dependOn(&run_hex_tests.step);
    test_step.dependOn(&run_rand_tests.step);
    test_step.dependOn(&run_zst_tests.step);
    test_step.dependOn(&run_zst_claims_tests.step);
    test_step.dependOn(&run_zst_errors_tests.step);
    test_step.dependOn(&run_xchacha20_tests.step);
    test_step.dependOn(&run_blake2b_tests.step);
}
