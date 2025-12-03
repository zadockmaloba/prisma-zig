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

    // Demo: findMany - get all users with email containing "alice"
    std.debug.print("\n=== findMany Demo ===\n", .{});
    const records = try client.user.findMany(.{ .where = .{ .email = .{ .contains = "alice" } } });
    for (records) |record| {
        std.debug.print("User: id={}, email={s}\n", .{ record.id, record.email });
    }
    defer alloc.free(records);

    // Demo: findUnique - get a specific user by id
    std.debug.print("\n=== findUnique Demo ===\n", .{});
    const unique_user = try client.user.findUnique(.{ .where = .{ .id = .{ .equals = 1 } } });
    if (unique_user) |user| {
        std.debug.print("Found user: id={}, email={s}, name={?s}\n", .{ user.id, user.email, user.name });
    } else {
        std.debug.print("User not found\n", .{});
    }

    // Demo: findUnique by email (unique field)
    const user_by_email = try client.user.findUnique(.{ .where = .{ .email = .{ .equals = "alice@example.com" } } });
    if (user_by_email) |user| {
        std.debug.print("Found user by email: id={}, email={s}\n", .{ user.id, user.email });
    } else {
        std.debug.print("User not found by email\n", .{});
    }

    // Demo: update - update a user's name
    std.debug.print("\n=== update Demo ===\n", .{});
    try client.user.update(.{
        .where = .{ .id = .{ .equals = 1 } },
        .data = .{
            .name = "Alice Wonderland",
            .updatedAt = std.time.timestamp(),
        },
    });
    std.debug.print("Updated user name to 'Alice Wonderland'\n", .{});

    // Verify the update
    const verified = try client.user.findUnique(.{ .where = .{ .id = .{ .equals = 1 } } });
    if (verified) |user| {
        std.debug.print("Verified update: id={}, email={s}, name={?s}\n", .{ user.id, user.email, user.name });
    }

    // Demo: Create another user for delete test
    std.debug.print("\n=== delete Demo ===\n", .{});
    _ = client.user.create(.init(
        999,
        "temp@example.com",
    )) catch |err| {
        std.debug.print("Failed to create temp user: {}\n", .{err});
    };

    // Verify it exists
    const temp_user = try client.user.findUnique(.{ .where = .{ .id = .{ .equals = 999 } } });
    if (temp_user) |user| {
        std.debug.print("Created temp user: id={}, email={s}\n", .{ user.id, user.email });
    }

    // Delete the temp user
    try client.user.delete(.{ .where = .{ .id = .{ .equals = 999 } } });
    std.debug.print("Deleted user with id=999\n", .{});

    // Verify it's gone
    const deleted_user = try client.user.findUnique(.{ .where = .{ .id = .{ .equals = 999 } } });
    if (deleted_user) |user| {
        std.debug.print("User still exists: id={}, email={s}\n", .{ user.id, user.email });
    } else {
        std.debug.print("Confirmed: User with id=999 has been deleted\n", .{});
    }
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
