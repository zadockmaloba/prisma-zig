const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const prisma_zig = b.dependency("prisma_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const libpq_zig = b.dependency("libpq_zig", .{
        .target = target,
        .optimize = optimize,
    });


    // Compile a small runner that executes the schema code generator at build-time.
    const codegen_runner = b.addExecutable(.{
        .name = "prisma_zig_codegen",
        .root_module = prisma_zig.module("prisma_zig"),
    });
    const prisma_step = b.step("prisma", "Run Prisma schema code generator");
    const prisma_cmd = b.addRunArtifact(codegen_runner);
    prisma_step.dependOn(&prisma_cmd.step);


    const exe = b.addExecutable(.{
        .name = "demo_1",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "libpq_zig", .module = libpq_zig.module("libpq_zig") },
                .{ .name = "datetime", .module = libpq_zig.module("datetime") },
            },
        }),
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
        prisma_cmd.addArgs(args);
    }


    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
