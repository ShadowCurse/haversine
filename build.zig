const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = if (optimize == .ReleaseFast)
        true
    else
        b.option(bool, "use_llvm", "Use LLVM backend") != null;

    const h_mod = b.addModule("haversine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const gen_mod = b.addModule("generator", .{
        .root_source_file = b.path("src/generator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "haversine", .module = h_mod },
        },
    });
    const gen_exe = b.addExecutable(.{
        .name = "generator",
        .root_module = gen_mod,
        .use_llvm = use_llvm,
    });
    b.installArtifact(gen_exe);

    const gen_run_step = b.step("gen", "Generate data");
    const gen_run_cmd = b.addRunArtifact(gen_exe);
    if (b.args) |args| gen_run_cmd.addArgs(args);
    gen_run_step.dependOn(&gen_run_cmd.step);
    gen_run_cmd.step.dependOn(b.getInstallStep());

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "haversine", .module = h_mod },
        },
    });
    const exe = b.addExecutable(.{
        .name = "haversine",
        .root_module = exe_mod,
        .use_llvm = use_llvm,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const mod_tests = b.addTest(.{
        .root_module = h_mod,
        .filters = b.args orelse &.{},
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .filters = b.args orelse &.{},
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
