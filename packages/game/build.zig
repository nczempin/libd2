const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("d2_core", .{ .target = target, .optimize = optimize });
    const data = b.dependency("d2_data", .{ .target = target, .optimize = optimize });
    const net = b.dependency("d2_net", .{ .target = target, .optimize = optimize });
    const drlg = b.dependency("d2_drlg", .{ .target = target, .optimize = optimize });
    const item = b.dependency("d2_item", .{ .target = target, .optimize = optimize });
    const wworld = b.dependency("d2_world", .{ .target = target, .optimize = optimize });
    const pathfinding = b.dependency("d2_pathfinding", .{ .target = target, .optimize = optimize });
    const dsave = b.dependency("d2_save", .{ .target = target, .optimize = optimize });

    // Library module: the faithful D2 1.14d runtime game-simulation port.
    // Consumers depend on this via `.d2_game = .{ .path = "../game" }`.
    const mod = b.addModule("d2-game", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("d2-core", core.module("d2-core"));
    mod.addImport("d2-data", data.module("d2-data"));
    mod.addImport("d2-net", net.module("d2-net"));
    mod.addImport("d2-drlg", drlg.module("d2-drlg"));
    mod.addImport("d2-item", item.module("d2-item"));
    mod.addImport("d2-world", wworld.module("d2-world"));
    mod.addImport("d2-pathfinding", pathfinding.module("d2-pathfinding"));

    // Smoke/demo CLI: resolve a single attack (attacker vs defender, seed).
    const exe = b.addExecutable(.{
        .name = "d2-game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("d2-core", core.module("d2-core"));
    exe.root_module.addImport("d2-data", data.module("d2-data"));
    exe.root_module.addImport("d2-net", net.module("d2-net"));
    exe.root_module.addImport("d2-drlg", drlg.module("d2-drlg"));
    exe.root_module.addImport("d2-item", item.module("d2-item"));
    exe.root_module.addImport("d2-world", wworld.module("d2-world"));
    exe.root_module.addImport("d2-pathfinding", pathfinding.module("d2-pathfinding"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the attack-resolution demo CLI");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("d2-core", core.module("d2-core"));
    tests.root_module.addImport("d2-data", data.module("d2-data"));
    tests.root_module.addImport("d2-net", net.module("d2-net"));
    tests.root_module.addImport("d2-drlg", drlg.module("d2-drlg"));
    tests.root_module.addImport("d2-item", item.module("d2-item"));
    tests.root_module.addImport("d2-world", wworld.module("d2-world"));
    tests.root_module.addImport("d2-pathfinding", pathfinding.module("d2-pathfinding"));
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // C-ABI shim (include/d2game.h): one headless game a C/C++/C# host plays like a client.
    // Static + shared `d2game` libs; its own tests run under `zig build test` too.
    const capi = b.option(bool, "capi", "Build the C-ABI shim") orelse true;
    if (capi and !target.result.cpu.arch.isWasm()) {
        const deps = .{
            .{ "d2-core", core.module("d2-core") },
            .{ "d2-data", data.module("d2-data") },
            .{ "d2-net", net.module("d2-net") },
            .{ "d2-drlg", drlg.module("d2-drlg") },
            .{ "d2-item", item.module("d2-item") },
            .{ "d2-world", wworld.module("d2-world") },
            .{ "d2-pathfinding", pathfinding.module("d2-pathfinding") },
            .{ "d2-save", dsave.module("d2-save") },
        };
        const static_mod = b.createModule(.{ .root_source_file = b.path("src/capi.zig"), .target = target, .optimize = optimize });
        static_mod.pic = true;
        const shared_mod = b.createModule(.{ .root_source_file = b.path("src/capi.zig"), .target = target, .optimize = optimize });
        const capi_test_mod = b.createModule(.{ .root_source_file = b.path("src/capi.zig"), .target = target, .optimize = optimize });
        inline for (deps) |d| {
            static_mod.addImport(d[0], d[1]);
            shared_mod.addImport(d[0], d[1]);
            capi_test_mod.addImport(d[0], d[1]);
        }
        const static_lib = b.addLibrary(.{ .name = "d2game", .linkage = .static, .root_module = static_mod });
        const shared_lib = b.addLibrary(.{ .name = "d2game", .linkage = .dynamic, .root_module = shared_mod });
        b.installArtifact(static_lib);
        b.installArtifact(shared_lib);
        b.installFile("include/d2game.h", "include/d2game.h");
        const capi_tests = b.addTest(.{ .root_module = capi_test_mod });
        test_step.dependOn(&b.addRunArtifact(capi_tests).step);
    }
}
