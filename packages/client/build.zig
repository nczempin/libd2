const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const net = b.dependency("d2_net", .{ .target = target, .optimize = optimize });
    const core = b.dependency("d2_core", .{ .target = target, .optimize = optimize });
    const data = b.dependency("d2_data", .{ .target = target, .optimize = optimize });

    const imports = [_]std.Build.Module.Import{
        .{ .name = "d2-net", .module = net.module("d2-net") },
        .{ .name = "d2-core", .module = core.module("d2-core") },
        .{ .name = "d2-data", .module = data.module("d2-data") },
    };

    const mod = b.addModule("d2-client", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &imports,
    });

    // C-ABI shim: the world model behind a handle, for C/C++/C#/Go/Node (see src/capi.zig).
    const capi_imports = [_]std.Build.Module.Import{.{ .name = "d2-client", .module = mod }};
    const capi = b.option(bool, "capi", "Build the C-ABI shim") orelse true;
    if (capi and !target.result.cpu.arch.isWasm()) {
        const shared_mod = b.createModule(.{
            .root_source_file = b.path("src/capi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &capi_imports,
        });
        const shared_lib = b.addLibrary(.{ .name = "d2client", .linkage = .dynamic, .root_module = shared_mod });
        b.installArtifact(shared_lib);
        b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("include/d2client.h"), "d2client.h").step);
    }

    const test_filter = b.option([]const u8, "test-filter", "Only run tests whose name contains this substring");
    const tests = b.addTest(.{
        .filters = if (test_filter) |f| &.{f} else &.{},
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &imports,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // The shim's own test: every export still compiles against the world model, and a packet
    // applied through the C ABI reads back through it.
    const capi_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/capi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &capi_imports,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(capi_tests).step);
}
