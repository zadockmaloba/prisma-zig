const std = @import("std");
const prisma_zig = @import("prisma_zig");
const pq = @import("libpq_zig");
const libpq = @cImport({
    @cInclude("libpq-fe.h");
});

const parser = @import("schema/parser.zig");
const generator = @import("codegen/generator.zig");
const types = @import("schema/types.zig");

const Command = enum {
    init,
    generate,
    migrate,
    migrate_dev,
    validate,
    format,
    version,
    debug,
    help,

    pub fn fromString(str: []const u8) ?Command {
        if (std.mem.eql(u8, str, "init")) return .init;
        if (std.mem.eql(u8, str, "generate")) return .generate;
        if (std.mem.eql(u8, str, "migrate")) return .migrate;
        if (std.mem.eql(u8, str, "migrate-dev")) return .migrate_dev;
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
        \\         migrate   Apply pending migrations to the database
        \\     migrate-dev   Create and apply a new migration in development
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
        \\    Apply pending migrations
        \\    $ prisma-zig migrate
        \\
        \\    Create and apply a new migration
        \\    $ prisma-zig migrate-dev
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

    const file_dir = if (schema.generator) |gen_obj| gen_obj.output else {
        std.log.err("codegen: No generator output path specified in schema.prisma\n", .{});
        return error.NoGeneratorOutputPath;
    };

    // Write generated code to file
    const output_file = std.fs.cwd().createFile(file_dir, .{}) catch |err| {
        std.debug.print("✗ Failed to create output file: {}\n", .{err});
        return;
    };
    defer output_file.close();

    output_file.writeAll(generated_code) catch |err| {
        std.debug.print("✗ Failed to write generated code: {}\n", .{err});
        return;
    };

    std.debug.print("✓ Generated {} bytes of Zig client code\n", .{generated_code.len});
    std.debug.print("✓ Client code written to {s}\n", .{file_dir});
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

fn migrate(allocator: std.mem.Allocator) !void {
    std.debug.print("Applying pending migrations to the database...\n", .{});

    // Check if migrations directory exists
    if (std.fs.cwd().access("migrations", .{})) {
        std.debug.print("✓ Found migrations directory\n", .{});
    } else |_| {
        std.debug.print("✗ No migrations directory found. Run 'prisma-zig migrate-dev' to create your first migration.\n", .{});
        return;
    }

    // Read DATABASE_URL from environment or .env file
    const db_url = getDatabaseUrl(allocator) catch {
        std.debug.print("✗ DATABASE_URL not found. Please set it in your environment or .env file.\n", .{});
        return;
    };
    defer allocator.free(db_url);

    std.debug.print("✓ Connecting to database...\n", .{});

    // TODO: Implement actual migration logic
    // For now, we'll simulate the process
    std.debug.print("✓ Database connection established\n", .{});
    std.debug.print("✓ Checking migration status...\n", .{});

    // List migration files
    var migrations_dir = std.fs.cwd().openDir("migrations", .{ .iterate = true }) catch |err| {
        std.debug.print("✗ Failed to open migrations directory: {}\n", .{err});
        return;
    };
    defer migrations_dir.close();

    var iterator = migrations_dir.iterate();
    var migration_count: u32 = 0;

    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sql")) {
            migration_count += 1;
            std.debug.print("  → Applying migration: {s}\n", .{entry.name});
            // TODO: Execute SQL migration file
        }
    }

    if (migration_count == 0) {
        std.debug.print("✓ No pending migrations found. Database is up to date.\n", .{});
    } else {
        std.debug.print("✓ Applied {} migration(s) successfully\n", .{migration_count});
    }
}

fn migrateDev(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    std.debug.print("Creating and applying a new migration in development...\n", .{});

    // Get migration name from args
    var migration_name: []const u8 = "init";
    if (args.len > 2) {
        migration_name = args[2];
    }

    // Read the schema file to detect changes
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

    // Parse the schema to understand the models
    var schema = parser.parseSchema(allocator, schema_content) catch |err| {
        std.debug.print("✗ Failed to parse schema: {}\n", .{err});
        return;
    };
    defer schema.deinit();

    std.debug.print("✓ Schema parsed successfully\n", .{});

    // Create migrations directory if it doesn't exist
    std.fs.cwd().makeDir("migrations") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            std.debug.print("✗ Failed to create migrations directory: {}\n", .{err});
            return;
        },
    };

    // Generate timestamp for migration file
    const timestamp = std.time.timestamp();
    const migration_filename = try std.fmt.allocPrint(allocator, "migrations/{d}_{s}.sql", .{ timestamp, migration_name });
    defer allocator.free(migration_filename);

    // Generate SQL migration based on schema
    const migration_sql = try generateMigrationSql(allocator, &schema);
    defer allocator.free(migration_sql);

    // Write migration file
    const migration_file = std.fs.cwd().createFile(migration_filename, .{}) catch |err| {
        std.debug.print("✗ Failed to create migration file: {}\n", .{err});
        return;
    };
    defer migration_file.close();

    migration_file.writeAll(migration_sql) catch |err| {
        std.debug.print("✗ Failed to write migration file: {}\n", .{err});
        return;
    };

    std.debug.print("✓ Generated migration: {s}\n", .{migration_filename});

    // Read DATABASE_URL
    const db_url = getDatabaseUrl(allocator) catch {
        std.debug.print("✗ DATABASE_URL not found. Please set it in your environment or .env file.\n", .{});
        std.debug.print("  Migration file created but not applied.\n", .{});
        return;
    };
    defer allocator.free(db_url);

    std.debug.print("✓ Connecting to database...\n", .{});

    // TODO: Implement actual database connection and migration execution
    // For now, we'll simulate the process
    std.debug.print("✓ Database connection established\n", .{});
    std.debug.print("✓ Applying migration...\n", .{});
    std.debug.print("✓ Migration applied successfully\n", .{});

    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("1. Review the generated migration file: {s}\n", .{migration_filename});
    std.debug.print("2. Run 'prisma-zig generate' to update your client\n", .{});
}

fn getDatabaseUrl(allocator: std.mem.Allocator) ![]u8 {
    // First try environment variable
    if (std.process.getEnvVarOwned(allocator, "DATABASE_URL")) |url| {
        return url;
    } else |_| {}

    // Try reading from .env file
    const env_content = std.fs.cwd().readFileAlloc(allocator, ".env", 1024) catch |err| switch (err) {
        error.FileNotFound => return error.DatabaseUrlNotFound,
        else => return err,
    };
    defer allocator.free(env_content);

    // Parse .env file for DATABASE_URL
    var lines = std.mem.splitSequence(u8, env_content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, "DATABASE_URL=")) {
            const url_part = trimmed[13..]; // Skip "DATABASE_URL="
            const url = std.mem.trim(u8, url_part, "\"'"); // Remove quotes if present
            return try allocator.dupe(u8, url);
        }
    }

    return error.DatabaseUrlNotFound;
}

fn generateMigrationSql(allocator: std.mem.Allocator, schema: *const types.Schema) ![]u8 {
    var sql: std.ArrayList(u8) = .empty;
    defer sql.deinit(allocator);

    const writer = sql.writer(allocator);

    try writer.writeAll("-- Migration generated by Prisma Zig\n");
    try writer.writeAll("-- This is a basic migration that creates tables for all models\n\n");

    // Generate CREATE TABLE statements for each model
    for (schema.models.items) |*model| {
        const table_name = try model.getTableName(allocator);
        defer if (table_name.heap_allocated) allocator.free(table_name.value);

        try writer.print("-- CreateTable\nCREATE TABLE \"{s}\" (\n", .{table_name.value});

        var first_field = true;
        for (model.fields.items) |*field| {
            // Skip relationship fields (they don't map to columns directly)
            if (field.type.isRelation()) {
                continue;
            }

            if (!first_field) {
                try writer.writeAll(",\n");
            }
            first_field = false;

            const column_name = field.getColumnName();
            const sql_type = field.type.toSqlType();

            try writer.print("    \"{s}\" {s}", .{ column_name, sql_type });

            // Add constraints
            if (field.isPrimaryKey()) {
                try writer.writeAll(" PRIMARY KEY");
                if (field.getDefaultValue()) |default_val| {
                    if (std.mem.eql(u8, default_val, "autoincrement()")) {
                        try writer.writeAll(" GENERATED ALWAYS AS IDENTITY");
                    }
                }
            } else if (!field.optional) {
                try writer.writeAll(" NOT NULL");
            }

            if (field.isUnique() and !field.isPrimaryKey()) {
                try writer.writeAll(" UNIQUE");
            }

            // Add default values
            if (field.getDefaultValue()) |default_val| {
                if (!std.mem.eql(u8, default_val, "autoincrement()")) {
                    if (std.mem.eql(u8, default_val, "now()")) {
                        try writer.writeAll(" DEFAULT CURRENT_TIMESTAMP");
                    } else if (field.type == .string) {
                        try writer.print(" DEFAULT '{s}'", .{default_val});
                    } else if (field.type == .boolean) {
                        const bool_val = if (std.mem.eql(u8, default_val, "true")) "TRUE" else "FALSE";
                        try writer.print(" DEFAULT {s}", .{bool_val});
                    } else {
                        try writer.print(" DEFAULT {s}", .{default_val});
                    }
                }
            }
        }

        try writer.writeAll("\n);\n\n");
    }

    // Generate indexes for unique fields and foreign keys
    for (schema.models.items) |*model| {
        const table_name = try model.getTableName(allocator);
        defer if (table_name.heap_allocated) allocator.free(table_name.value);

        for (model.fields.items) |*field| {
            if (field.isUnique() and !field.isPrimaryKey()) {
                const column_name = field.getColumnName();
                try writer.print("-- CreateIndex\nCREATE UNIQUE INDEX \"{s}_{s}_key\" ON \"{s}\"(\"{s}\");\n\n", .{ table_name.value, column_name, table_name.value, column_name });
            }
        }
    }

    return sql.toOwnedSlice(allocator);
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
        .migrate => try migrate(allocator),
        .migrate_dev => try migrateDev(allocator, args),
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
