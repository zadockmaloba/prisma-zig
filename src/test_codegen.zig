const std = @import("std");
const schema_parser = @import("schema/parser.zig");
const generator = @import("codegen/generator.zig");

pub fn test_codegen() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    
    // Read the schema file
    const schema_content = std.fs.cwd().readFileAlloc(allocator, "schema.prisma", 1024 * 1024) catch |err| {
        std.log.err("Failed to read schema.prisma: {}", .{err});
        return;
    };
    defer allocator.free(schema_content);
    
    // Parse the schema
    var schema = schema_parser.parseSchema(allocator, schema_content) catch |err| {
        std.log.err("Failed to parse schema: {}", .{err});
        return err;
    };
    defer schema.deinit();
    errdefer {
        allocator.free(schema_content);
        schema.deinit();
    }
    
    std.log.info("Schema parsed successfully! Found {d} models", .{schema.models.items.len});
    
    // Generate client code
    var code_generator = generator.Generator.init(allocator, &schema);
    defer code_generator.deinit();
    const generated_code = code_generator.generateClient() catch |err| {
        std.log.err("Failed to generate client code: {}", .{err});
        return;
    };
    defer allocator.free(generated_code);
    
    std.log.info("Code generation completed! Generated {d} bytes of code", .{generated_code.len});
    
    // Write generated code to file
    const output_file = std.fs.cwd().createFile("src/generated_client.zig", .{}) catch |err| {
        std.log.err("Failed to create output file: {}", .{err});
        return;
    };
    defer output_file.close();
    
    output_file.writeAll(generated_code) catch |err| {
        std.log.err("Failed to write generated code: {}", .{err});
        return;
    };
    
    std.log.info("Generated client code written to src/generated_client.zig", .{});
    
    // Print a preview of the generated code
    const preview_len = @min(500, generated_code.len);
    std.log.info("Preview of generated code:", .{});
    std.log.info("{s}...", .{generated_code[0..preview_len]});
}