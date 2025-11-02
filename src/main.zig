const std = @import("std");
const prisma_zig = @import("prisma_zig");
const pq = @import("libpq_zig");
const libpq = @cImport({
    @cInclude("libpq-fe.h");
});

const parser = @import("schema/parser.zig");
const generator = @import("codegen/generator.zig");
const codegen_test = @import("test_codegen.zig");

const Command = enum {
    init,
    generate,
    validate,
    format,
    version,
    debug,
    help,

    pub fn fromString(str: []const u8) ?Command {
        if (std.mem.eql(u8, str, "init")) return .init;
        if (std.mem.eql(u8, str, "generate")) return .generate;
        if (std.mem.eql(u8, str, "validate")) return .validate;
        if (std.mem.eql(u8, str, "format")) return .format;
        if (std.mem.eql(u8, str, "version")) return .version;
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "help") or std.mem.eql(u8, str, "--help") or std.mem.eql(u8, str, "-h")) return .help;
        return null;
    }
};

fn printUsage() void {
    std.debug.print(
        \\
        \\  ◭  Prisma Zig is a modern DB toolkit to query, migrate and model your database
        \\
        \\  Usage
        \\
        \\    $ prisma-zig [command]
        \\
        \\  Commands
        \\
        \\            init   Set up Prisma for your Zig app
        \\        generate   Generate Zig client code from Prisma schema
        \\        validate   Validate your Prisma schema
        \\          format   Format your Prisma schema
        \\         version   Displays Prisma Zig version info
        \\           debug   Displays Prisma Zig debug info
        \\
        \\  Flags
        \\
        \\       --help, -h   Show additional information about a command
        \\
        \\  Examples
        \\
        \\    Set up a new Prisma project
        \\    $ prisma-zig init
        \\
        \\    Generate Zig client code
        \\    $ prisma-zig generate
        \\
        \\    Validate your Prisma schema
        \\    $ prisma-zig validate
        \\
        \\    Format your Prisma schema
        \\    $ prisma-zig format
        \\
        \\    Display version info
        \\    $ prisma-zig version
        \\
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("prisma-zig 0.1.0\n", .{});
}

fn initProject(allocator: std.mem.Allocator) !void {
    std.debug.print("Setting up Prisma Zig project...\n", .{});

    // Create a basic schema.prisma file
    const schema_content =
        \\// This is your Prisma schema file,
        \\// learn more about it in the docs: https://pris.ly/d/prisma-schema
        \\
        \\generator client {
        \\  provider = "prisma-zig"
        \\  output   = "./src/generated"
        \\}
        \\
        \\datasource db {
        \\  provider = "postgresql"
        \\  url      = env("DATABASE_URL")
        \\}
        \\
        \\model User {
        \\  id    Int     @id @default(autoincrement())
        \\  email String  @unique
        \\  name  String?
        \\  posts Post[]
        \\}
        \\
        \\model Post {
        \\  id        Int     @id @default(autoincrement())
        \\  title     String
        \\  content   String?
        \\  published Boolean @default(false)
        \\  authorId  Int
        \\  author    User    @relation(fields: [authorId], references: [id])
        \\}
        \\
    ;

    // Check if schema.prisma already exists
    if (std.fs.cwd().access("schema.prisma", .{})) {
        std.debug.print("✓ schema.prisma already exists\n", .{});
    } else |_| {
        // Create schema.prisma
        const file = std.fs.cwd().createFile("schema.prisma", .{}) catch |err| {
            std.debug.print("✗ Failed to create schema.prisma: {}\n", .{err});
            return;
        };
        defer file.close();

        file.writeAll(schema_content) catch |err| {
            std.debug.print("✗ Failed to write schema.prisma: {}\n", .{err});
            return;
        };

        std.debug.print("✓ Generated schema.prisma\n", .{});
    }

    // Create .env file with DATABASE_URL
    if (std.fs.cwd().access(".env", .{})) {
        std.debug.print("✓ .env already exists\n", .{});
    } else |_| {
        const env_content =
            \\# Environment variables declared in this file are available at runtime
            \\
            \\# See the documentation for all the connection string options:
            \\# https://pris.ly/d/connection-strings
            \\
            \\DATABASE_URL="postgresql://username:password@localhost:5432/mydb?schema=public"
            \\
        ;

        const env_file = std.fs.cwd().createFile(".env", .{}) catch |err| {
            std.debug.print("✗ Failed to create .env: {}\n", .{err});
            return;
        };
        defer env_file.close();

        env_file.writeAll(env_content) catch |err| {
            std.debug.print("✗ Failed to write .env: {}\n", .{err});
            return;
        };

        std.debug.print("✓ Generated .env\n", .{});
    }

    _ = allocator; // Suppress unused parameter warning

    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("1. Set the DATABASE_URL in the .env file to point to your existing database\n", .{});
    std.debug.print("2. Run prisma-zig generate to generate the Zig client\n", .{});
    std.debug.print("3. Start using Prisma Zig in your code\n", .{});
}

fn generateClient(allocator: std.mem.Allocator) !void {
    std.debug.print("Generating Zig client from Prisma schema...\n", .{});

    // Read the schema file
    const schema_content = std.fs.cwd().readFileAlloc(allocator, "schema.prisma", 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("✗ schema.prisma not found. Run 'prisma-zig init' first.\n", .{});
            return;
        },
        else => {
            std.debug.print("✗ Failed to read schema.prisma: {}\n", .{err});
            return;
        },
    };
    defer allocator.free(schema_content);

    // Parse the schema
    var schema = parser.parseSchema(allocator, schema_content) catch |err| {
        std.debug.print("✗ Failed to parse schema: {}\n", .{err});
        return;
    };
    defer schema.deinit();

    std.debug.print("✓ Schema parsed successfully! Found {} models\n", .{schema.models.items.len});

    // Generate client code
    var code_generator = generator.Generator.init(allocator, &schema);
    defer code_generator.deinit();

    const generated_code = code_generator.generateClient() catch |err| {
        std.debug.print("✗ Failed to generate client code: {}\n", .{err});
        return;
    };
    defer allocator.free(generated_code);

    const cwd = std.fs.cwd();
    const root_dir = if (schema.generator) |gen_obj| gen_obj.output else {
        std.log.err("codegen: No generator output path specified in schema.prisma\n", .{});
        return error.NoGeneratorOutputPath;
    };

    const src_dir = try std.mem.concat(allocator, u8, &.{ root_dir, "/src" });
    defer allocator.free(src_dir);

    const root_file = try std.mem.concat(allocator, u8, &.{ root_dir, "/src/root.zig" });
    defer allocator.free(root_file);

    // Create output directory if it doesn't exist
    cwd.makePath(src_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, that's fine
        else => {
            std.debug.print("✗ Failed to create src directory: {}\n", .{err});
            return;
        },
    };

    // Write generated code to file
    const output_file = std.fs.cwd().createFile(root_file, .{}) catch |err| {
        std.debug.print("✗ Failed to create output file: {}\n", .{err});
        return;
    };
    defer output_file.close();

    output_file.writeAll(generated_code) catch |err| {
        std.debug.print("✗ Failed to write generated code: {}\n", .{err});
        return;
    };

    std.debug.print("✓ Generated {} bytes of Zig client code\n", .{generated_code.len});
    std.debug.print("✓ Client code written to {s}\n", .{root_file});
}

fn validateSchema(allocator: std.mem.Allocator) !void {
    std.debug.print("Validating Prisma schema...\n", .{});

    // Read the schema file
    const schema_content = std.fs.cwd().readFileAlloc(allocator, "schema.prisma", 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("✗ schema.prisma not found\n", .{});
            return;
        },
        else => {
            std.debug.print("✗ Failed to read schema.prisma: {}\n", .{err});
            return;
        },
    };
    defer allocator.free(schema_content);

    // Parse the schema
    var schema = parser.parseSchema(allocator, schema_content) catch |err| {
        std.debug.print("✗ Schema validation failed: {}\n", .{err});
        return;
    };
    defer schema.deinit();

    std.debug.print("✓ Schema is valid!\n", .{});
    std.debug.print("  Found {} models\n", .{schema.models.items.len});

    for (schema.models.items) |*model| {
        std.debug.print("  - {s} ({} fields)\n", .{ model.name, model.fields.items.len });
    }
}

fn formatSchema(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Schema formatting is not yet implemented.\n", .{});
    std.debug.print("This feature will format your schema.prisma file with consistent styling.\n", .{});
}

fn printDebugInfo(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Prisma Zig Debug Information:\n", .{});
    std.debug.print("  Version: 0.1.0\n", .{});
    std.debug.print("  Zig version: 0.15.1\n", .{});
}

fn getDbHost() []const u8 {
    // Check for environment variable, default to localhost for local development
    return std.process.getEnvVarOwned(std.heap.page_allocator, "DB_HOST") catch "localhost";
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // If no arguments provided, show help
    if (args.len < 2) {
        printUsage();
        return;
    }

    // Parse command
    const command_str = args[1];
    const command = Command.fromString(command_str) orelse {
        std.debug.print("Unknown command: {s}\n", .{command_str});
        printUsage();
        return;
    };

    // Execute command
    switch (command) {
        .init => try initProject(allocator),
        .generate => try generateClient(allocator),
        .validate => try validateSchema(allocator),
        .format => try formatSchema(allocator),
        .version => printVersion(),
        .debug => try printDebugInfo(allocator),
        .help => printUsage(),
    }
}

test {
    std.testing.refAllDecls(parser);
    std.testing.refAllDecls(generator);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
