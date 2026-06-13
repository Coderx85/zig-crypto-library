const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Napi Module Metadata
    const napi_include = b.option([]const u8, "napi-include", "Path to node-api-headers include directory");

    const mod = b.addModule("zig_snowflake", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "zig_snowflake",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_snowflake", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

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

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const snowflake_mod = b.addModule("snowflake", .{
        .root_source_file = b.path("src/internal/snowflake.zig"),
        .target = target,
    });

    const snowflake_tests = b.addTest(.{
        .root_module = snowflake_mod,
    });
    const run_snowflake_tests = b.addRunArtifact(snowflake_tests);

    const nanoid_mod = b.addModule("nanoid", .{
        .root_source_file = b.path("src/internal/nanoid.zig"),
        .target = target,
    });

    const nanoid_tests = b.addTest(.{
        .root_module = nanoid_mod,
    });
    const run_nanoid_tests = b.addRunArtifact(nanoid_tests);

    const base64_mod = b.addModule("codec_base64", .{
        .root_source_file = b.path("src/codec/base64.zig"),
        .target = target,
    });

    const base64_tests = b.addTest(.{
        .root_module = base64_mod,
    });
    const run_base64_tests = b.addRunArtifact(base64_tests);

    const base58_mod = b.addModule("codec_base58", .{
        .root_source_file = b.path("src/codec/base58.zig"),
        .target = target,
    });

    const base58_tests = b.addTest(.{
        .root_module = base58_mod,
    });
    const run_base58_tests = b.addRunArtifact(base58_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_snowflake_tests.step);
    test_step.dependOn(&run_nanoid_tests.step);
    test_step.dependOn(&run_base64_tests.step);
    test_step.dependOn(&run_base58_tests.step);
}
