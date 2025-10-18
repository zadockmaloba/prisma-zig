const std = @import("std");
const prisma_zig = @import("prisma_zig");
const pq = @import("db/psql.zig");
const libpq = @cImport({
    @cInclude("libpq-fe.h");
});

const parser = @import("schema/parser.zig");

fn getDbHost() []const u8 {
    // Check for environment variable, default to localhost for local development
    return std.process.getEnvVarOwned(std.heap.page_allocator, "DB_HOST") catch "localhost";
}

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try prisma_zig.bufferedPrint();
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(parser);
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

test "simple libpq connection" {
    const db_host = getDbHost();
    const connection_string = std.fmt.allocPrint(std.testing.allocator, "postgresql://postgres:postgres@{s}:5432", .{db_host}) catch "postgresql://postgres:postgres@localhost:5432";
    defer std.testing.allocator.free(connection_string);

    const conn = libpq.PQconnectdb(connection_string.ptr);
    defer libpq.PQfinish(conn);

    if (libpq.PQstatus(conn) != libpq.CONNECTION_OK) {
        std.debug.print("Error: {s} \n", .{libpq.PQerrorMessage(conn)});
        return;
    }

    std.debug.print("Connected to the server\n", .{});
}

test "libpq wrapper API" {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var conn = pq.Connection.init(allocator);
    defer conn.deinit();

    const db_host = getDbHost();
    const connection_string = std.fmt.allocPrint(allocator, "postgresql://postgres:postgres@{s}:5432", .{db_host}) catch "postgresql://postgres:postgres@localhost:5432";
    defer allocator.free(connection_string);

    try conn.connect(connection_string);

    std.debug.print("PSQL Server version: {} \n", .{conn.serverVersion()});
}
