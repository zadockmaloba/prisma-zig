const std = @import("std");
const prisma = @import("prisma_test.zig");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("Memory leaks detected!");

    const alloc = gpa.allocator();

    var conn = prisma.Connection.init(alloc);
    defer conn.deinit();
    conn.connect("postgresql://postgres:postgres@localhost:5432/postgres") catch |err| {
        std.debug.print("Failed to connect to database: {}\n", .{err});
        return err;
    };

    var client = prisma.PrismaClient.init(alloc, &conn);
    _ = client.user.create(.init(
        1,
        "alice@example.com",
    )) catch |err| {
        std.debug.print("Failed to create user: {}\n", .{err});
    };
    _ = try client.user.findMany(.{ .where = .{.email = .{ .contains = "alice" } } });
 
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
