const std = @import("std");


pub fn build(b: *std.Build) void {

    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("prisma_zig", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "prisma_zig",
        .root_module = mod,
    });

    const exe_mod = exe.root_module;

    const libpq_zig = b.dependency("libpq_zig", .{
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("libpq_zig", libpq_zig.module("libpq_zig"));

    mod.addIncludePath(b.path("zig-out/include/"));
    mod.addIncludePath(b.path("zig-out/include/libpq/"));

    exe_mod.addIncludePath(b.path("zig-out/include/"));
    exe_mod.addIncludePath(b.path("zig-out/include/libpq/"));

    b.installArtifact(exe);

    // --- Code generation runner ---
    // Compile a small runner that executes the schema code generator at build-time.
    const codegen_runner = b.addExecutable(.{
        .name = "prisma_zig_codegen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/codegen_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "prisma_zig", .module = mod },
            },
        }),
    });
    _ = codegen_runner;

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

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

}
