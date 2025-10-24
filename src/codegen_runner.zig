const std = @import("std");
const parser = @import("schema/parser.zig");
const generator = @import("codegen/generator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read schema.prisma from project root
    const schema_content = std.fs.cwd().readFileAlloc(allocator, "schema.prisma", 1024 * 1024) catch |err| {
        std.debug.print("codegen: Failed to read schema.prisma: {any}\n", .{err});
        return err;
    };
    defer allocator.free(schema_content);

    // Parse schema
    var schema = parser.parseSchema(allocator, schema_content) catch |err| {
        std.debug.print("codegen: Failed to parse schema: {any}\n", .{err});
        return err;
    };
    defer schema.deinit();

    // Generate client code
    var gen = generator.Generator.init(allocator, &schema);
    defer gen.deinit();

    const code = gen.generateClient() catch |err| {
        std.debug.print("codegen: generateClient failed: {any}\n", .{err});
        return err;
    };
    defer allocator.free(code);

    // Ensure target directory exists: generated_client/src
    const cwd = std.fs.cwd();
    try cwd.makePath("generated_client/src");

    const out_path = "generated_client/src/generated_client.zig";
    const out_file = cwd.createFile(out_path, .{ .truncate = true }) catch |err| {
        std.debug.print("codegen: Failed to create {s}: {any}\n", .{ out_path, err });
        return err;
    };
    defer out_file.close();

    out_file.writeAll(code) catch |err| {
        std.debug.print("codegen: Failed to write generated code: {any}\n", .{err});
        return err;
    };

    std.debug.print("codegen: Wrote generated code to {s}\n", .{out_path});
}
