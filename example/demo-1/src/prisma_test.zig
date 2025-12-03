const std = @import("std");
const psql = @import("libpq_zig");
const dt = @import("datetime");

pub const Connection = psql.Connection;
pub const QueryBuilder = psql.QueryBuilder;
pub const ResultSet = psql.ResultSet;

/// Generated Prisma client for type-safe database operations
/// User model struct
pub const User = struct {
    /// Database column: id
    /// Primary key
    id: i32,
    /// Database column: email
    /// Unique constraint
    email: []const u8,
    /// Database column: name
    name: ?[]const u8,
    /// Database column: createdAt
    /// Default: now()
    createdAt: i64,
    /// Database column: updatedAt
    /// Default: now()
    updatedAt: i64,

    /// Initialize a new instance
    pub fn init(id: i32, email: []const u8) User {
        return User{
            .id = id,
            .email = email,
            .name = null,
            .createdAt = std.time.timestamp(),
            .updatedAt = std.time.timestamp(),
        };
    }

    /// Convert to SQL values for INSERT/UPDATE
    pub fn toSqlValues(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        var values: std.ArrayList(u8) = .empty;
        var first: bool = true;
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("{d}", .{self.id});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("'{s}'", .{self.email});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        if (self.name) |val| {
            try values.writer(allocator).print("'{s}'", .{val});
        } else {
            try values.appendSlice(allocator, "NULL");
        }
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("to_timestamp({d})", .{self.createdAt});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("to_timestamp({d})", .{self.updatedAt});
        return values.toOwnedSlice(allocator);
    }
};

/// Post model struct
pub const Post = struct {
    /// Database column: id
    /// Primary key
    id: i32,
    /// Database column: title
    title: []const u8,
    /// Database column: content
    content: ?[]const u8,
    /// Database column: published
    /// Default: false
    published: bool,
    /// Database column: authorId
    authorId: i32,
    /// Database column: createdAt
    /// Default: now()
    createdAt: i64,

    /// Initialize a new instance
    pub fn init(id: i32, title: []const u8, authorId: i32) Post {
        return Post{
            .id = id,
            .title = title,
            .content = null,
            .published = false,
            .authorId = authorId,
            .createdAt = std.time.timestamp(),
        };
    }

    /// Convert to SQL values for INSERT/UPDATE
    pub fn toSqlValues(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        var values: std.ArrayList(u8) = .empty;
        var first: bool = true;
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("{d}", .{self.id});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("'{s}'", .{self.title});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        if (self.content) |val| {
            try values.writer(allocator).print("'{s}'", .{val});
        } else {
            try values.appendSlice(allocator, "NULL");
        }
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.appendSlice(allocator, if (self.published) "true" else "false");
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("{d}", .{self.authorId});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("to_timestamp({d})", .{self.createdAt});
        return values.toOwnedSlice(allocator);
    }
};

/// Profile model struct
pub const Profile = struct {
    /// Database column: id
    /// Primary key
    id: i32,
    /// Database column: bio
    bio: ?[]const u8,
    /// Database column: user_id
    /// Unique constraint
    userId: i32,

    /// Initialize a new instance
    pub fn init(id: i32, userId: i32) Profile {
        return Profile{
            .id = id,
            .bio = null,
            .userId = userId,
        };
    }

    /// Convert to SQL values for INSERT/UPDATE
    pub fn toSqlValues(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        var values: std.ArrayList(u8) = .empty;
        var first: bool = true;
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("{d}", .{self.id});
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        if (self.bio) |val| {
            try values.writer(allocator).print("'{s}'", .{val});
        } else {
            try values.appendSlice(allocator, "NULL");
        }
        if (!first) try values.appendSlice(allocator, ", ");
        first = false;
        try values.writer(allocator).print("{d}", .{self.userId});
        return values.toOwnedSlice(allocator);
    }
};

/// String filter options
pub const StringFilter = struct {
    equals: ?[]const u8 = null,
    contains: ?[]const u8 = null,
    startsWith: ?[]const u8 = null,
    endsWith: ?[]const u8 = null,
};

/// Integer filter options
pub const IntFilter = struct {
    equals: ?i32 = null,
    lt: ?i32 = null,
    lte: ?i32 = null,
    gt: ?i32 = null,
    gte: ?i32 = null,
};

/// Boolean filter options
pub const BooleanFilter = struct {
    equals: ?bool = null,
};

/// DateTime filter options
pub const DateTimeFilter = struct {
    equals: ?i64 = null,
    lt: ?i64 = null,
    lte: ?i64 = null,
    gt: ?i64 = null,
    gte: ?i64 = null,
};

/// Main Prisma client
pub const PrismaClient = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    user: UserOperations,
    post: PostOperations,
    profile: ProfileOperations,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection) PrismaClient {
        return PrismaClient{
            .allocator = allocator,
            .connection = connection,
            .user = UserOperations.init(allocator, connection),
            .post = PostOperations.init(allocator, connection),
            .profile = ProfileOperations.init(allocator, connection),
        };
    }
};

/// CRUD operations for User model
pub const UserOperations = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection) UserOperations {
        return UserOperations{
            .allocator = allocator,
            .connection = connection,
        };
    }

    pub const UserWhere = struct {
        id: ?IntFilter = null,
        email: ?StringFilter = null,
        name: ?StringFilter = null,
        createdAt: ?DateTimeFilter = null,
        updatedAt: ?DateTimeFilter = null,
    };

    pub const UserUpdateData = struct {
        id: ?i32 = null,
        email: ?[]const u8 = null,
        name: ?[]const u8 = null,
        createdAt: ?i64 = null,
        updatedAt: ?i64 = null,
    };

    /// Create a new User record
    pub fn create(self: *@This(), data: User) !User {
        const columns = [_][]const u8{"id", "email", "name", "createdAt", "updatedAt"};
        const values = try data.toSqlValues(self.allocator);
        defer self.allocator.free(values);
        const key_list = std.mem.join(self.allocator, ", ", &columns) catch "";
        defer self.allocator.free(key_list);
        const val_list = values;
        const query = try std.fmt.allocPrint(self.allocator, 
            "INSERT INTO \"user\" ({s}) VALUES ({s}) RETURNING *;",
            .{ key_list, val_list }
        );
        defer self.allocator.free(query);
        var result = try self.connection.execSafe(query);
        
        if (result.next()) |row| {
            var record: User = undefined;
            record.id = try row.get("id", i32);
            record.email = try row.get("email", []const u8);
            record.name = try row.getOpt("name", []const u8);
            record.createdAt = try dt.unixTimeFromISO8601(try row.get("createdAt", []const u8));
            record.updatedAt = try dt.unixTimeFromISO8601(try row.get("updatedAt", []const u8));
            return record;
        }
        
        return data; // Fallback if no result returned
    }

    /// Find multiple User records
    pub fn findMany(self: *@This(), options: struct { where: ?UserWhere = null }) ![]User {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("SELECT * FROM \"user\"");
        if (options.where) |where_clause| {
            // TODO: Build WHERE clause from where_clause
            _ = where_clause;
        }

        const query = query_builder.build();
        var result = try self.connection.execSafe(query);
        const row_count = result.rowCount();
        var records = try self.allocator.alloc(User, @intCast(row_count));
        errdefer self.allocator.free(records);

        var idx: usize = 0;
        while (result.next()) |row| : (idx += 1) {
            records[idx].id = try row.get("id", i32);
            records[idx].email = try row.get("email", []const u8);
            records[idx].name = try row.getOpt("name", []const u8);
            records[idx].createdAt = try dt.unixTimeFromISO8601( try row.get("createdAt", []const u8) );
            records[idx].updatedAt = try dt.unixTimeFromISO8601( try row.get("updatedAt", []const u8) );
        }

        return records;
    }

    /// Find a unique User record
    pub fn findUnique(self: *@This(), options: struct { where: UserWhere }) !?User {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("SELECT * FROM \"user\" WHERE ");
        var first_condition = true;

        // Build WHERE clause for unique fields
        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.email) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("email = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.name) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("name = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.createdAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "to_timestamp({d})", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("createdAt = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.updatedAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "to_timestamp({d})", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("updatedAt = ");
                _ = try query_builder.sql(val_str);
            }
        }

        _ = try query_builder.sql(" LIMIT 1");
        const query = query_builder.build();
        var result = try self.connection.execSafe(query);
        
        if (result.rowCount() == 0) {
            return null;
        }

        if (result.next()) |row| {
            var record: User = undefined;
            record.id = try row.get("id", i32);
            record.email = try row.get("email", []const u8);
            record.name = try row.getOpt("name", []const u8);
            record.createdAt = try dt.unixTimeFromISO8601( try row.get("createdAt", []const u8) );
            record.updatedAt = try dt.unixTimeFromISO8601( try row.get("updatedAt", []const u8) );
            return record;
        }

        return null;
    }

    /// Update a User record
    pub fn update(self: *@This(), options: struct { where: UserWhere, data: UserUpdateData }) !void {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("UPDATE \"user\" SET ");
        var first_field = true;

        // Build SET clause - only update fields that are provided
        if (options.data.email) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            _ = try query_builder.sql("email = '");
            _ = try query_builder.sql(value);
            _ = try query_builder.sql("'");
        }
        if (options.data.name) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            _ = try query_builder.sql("name = '");
            _ = try query_builder.sql(value);
            _ = try query_builder.sql("'");
        }
        if (options.data.createdAt) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
            defer self.allocator.free(val_str);
            _ = try query_builder.sql("createdAt = to_timestamp(");
            _ = try query_builder.sql(val_str);
            _ = try query_builder.sql(")");
        }
        if (options.data.updatedAt) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
            defer self.allocator.free(val_str);
            _ = try query_builder.sql("updatedAt = to_timestamp(");
            _ = try query_builder.sql(val_str);
            _ = try query_builder.sql(")");
        }

        // Build WHERE clause
        _ = try query_builder.sql(" WHERE ");
        var first_condition = true;

        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.email) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("email = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.name) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("name = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.createdAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("createdAt = to_timestamp(");
                _ = try query_builder.sql(val_str);
                _ = try query_builder.sql(")");
            }
        }
        if (options.where.updatedAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("updatedAt = to_timestamp(");
                _ = try query_builder.sql(val_str);
                _ = try query_builder.sql(")");
            }
        }

        const query = query_builder.build();
        _ = try self.connection.execSafe(query);
    }

    /// Delete a User record
    pub fn delete(self: *@This(), options: struct { where: UserWhere }) !void {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("DELETE FROM \"user\" WHERE ");
        var first_condition = true;

        // Build WHERE clause
        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.email) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("email = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.name) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("name = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.createdAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "to_timestamp({d})", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("createdAt = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.updatedAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "to_timestamp({d})", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("updatedAt = ");
                _ = try query_builder.sql(val_str);
            }
        }

        const query = query_builder.build();
        _ = try self.connection.execSafe(query);
    }

};

/// CRUD operations for Post model
pub const PostOperations = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection) PostOperations {
        return PostOperations{
            .allocator = allocator,
            .connection = connection,
        };
    }

    pub const PostWhere = struct {
        id: ?IntFilter = null,
        title: ?StringFilter = null,
        content: ?StringFilter = null,
        published: ?BooleanFilter = null,
        authorId: ?IntFilter = null,
        createdAt: ?DateTimeFilter = null,
    };

    pub const PostUpdateData = struct {
        id: ?i32 = null,
        title: ?[]const u8 = null,
        content: ?[]const u8 = null,
        published: ?bool = null,
        authorId: ?i32 = null,
        createdAt: ?i64 = null,
    };

    /// Create a new Post record
    pub fn create(self: *@This(), data: Post) !Post {
        const columns = [_][]const u8{"id", "title", "content", "published", "authorId", "createdAt"};
        const values = try data.toSqlValues(self.allocator);
        defer self.allocator.free(values);
        const key_list = std.mem.join(self.allocator, ", ", &columns) catch "";
        defer self.allocator.free(key_list);
        const val_list = values;
        const query = try std.fmt.allocPrint(self.allocator, 
            "INSERT INTO \"posts\" ({s}) VALUES ({s}) RETURNING *;",
            .{ key_list, val_list }
        );
        defer self.allocator.free(query);
        var result = try self.connection.execSafe(query);
        
        if (result.next()) |row| {
            var record: Post = undefined;
            record.id = try row.get("id", i32);
            record.title = try row.get("title", []const u8);
            record.content = try row.getOpt("content", []const u8);
            record.published = try row.get("published", bool);
            record.authorId = try row.get("authorId", i32);
            record.createdAt = try dt.unixTimeFromISO8601(try row.get("createdAt", []const u8));
            return record;
        }
        
        return data; // Fallback if no result returned
    }

    /// Find multiple Post records
    pub fn findMany(self: *@This(), options: struct { where: ?PostWhere = null }) ![]Post {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("SELECT * FROM \"posts\"");
        if (options.where) |where_clause| {
            // TODO: Build WHERE clause from where_clause
            _ = where_clause;
        }

        const query = query_builder.build();
        var result = try self.connection.execSafe(query);
        const row_count = result.rowCount();
        var records = try self.allocator.alloc(Post, @intCast(row_count));
        errdefer self.allocator.free(records);

        var idx: usize = 0;
        while (result.next()) |row| : (idx += 1) {
            records[idx].id = try row.get("id", i32);
            records[idx].title = try row.get("title", []const u8);
            records[idx].content = try row.getOpt("content", []const u8);
            records[idx].published = try row.get("published", bool);
            records[idx].authorId = try row.get("authorId", i32);
            records[idx].createdAt = try dt.unixTimeFromISO8601( try row.get("createdAt", []const u8) );
        }

        return records;
    }

    /// Find a unique Post record
    pub fn findUnique(self: *@This(), options: struct { where: PostWhere }) !?Post {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("SELECT * FROM \"posts\" WHERE ");
        var first_condition = true;

        // Build WHERE clause for unique fields
        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.title) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("title = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.content) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("content = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.published) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("published = ");
                _ = try query_builder.sql(if (value) "true" else "false");
            }
        }
        if (options.where.authorId) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("authorId = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.createdAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "to_timestamp({d})", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("createdAt = ");
                _ = try query_builder.sql(val_str);
            }
        }

        _ = try query_builder.sql(" LIMIT 1");
        const query = query_builder.build();
        var result = try self.connection.execSafe(query);
        
        if (result.rowCount() == 0) {
            return null;
        }

        if (result.next()) |row| {
            var record: Post = undefined;
            record.id = try row.get("id", i32);
            record.title = try row.get("title", []const u8);
            record.content = try row.getOpt("content", []const u8);
            record.published = try row.get("published", bool);
            record.authorId = try row.get("authorId", i32);
            record.createdAt = try dt.unixTimeFromISO8601( try row.get("createdAt", []const u8) );
            return record;
        }

        return null;
    }

    /// Update a Post record
    pub fn update(self: *@This(), options: struct { where: PostWhere, data: PostUpdateData }) !void {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("UPDATE \"posts\" SET ");
        var first_field = true;

        // Build SET clause - only update fields that are provided
        if (options.data.title) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            _ = try query_builder.sql("title = '");
            _ = try query_builder.sql(value);
            _ = try query_builder.sql("'");
        }
        if (options.data.content) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            _ = try query_builder.sql("content = '");
            _ = try query_builder.sql(value);
            _ = try query_builder.sql("'");
        }
        if (options.data.published) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            const bool_str = if (value) "TRUE" else "FALSE";
            _ = try query_builder.sql("published = ");
            _ = try query_builder.sql(bool_str);
        }
        if (options.data.authorId) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
            defer self.allocator.free(val_str);
            _ = try query_builder.sql("authorId = ");
            _ = try query_builder.sql(val_str);
        }
        if (options.data.createdAt) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
            defer self.allocator.free(val_str);
            _ = try query_builder.sql("createdAt = to_timestamp(");
            _ = try query_builder.sql(val_str);
            _ = try query_builder.sql(")");
        }

        // Build WHERE clause
        _ = try query_builder.sql(" WHERE ");
        var first_condition = true;

        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.title) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("title = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.content) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("content = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.published) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const bool_str = if (value) "TRUE" else "FALSE";
                _ = try query_builder.sql("published = ");
                _ = try query_builder.sql(bool_str);
            }
        }
        if (options.where.authorId) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("authorId = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.createdAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("createdAt = to_timestamp(");
                _ = try query_builder.sql(val_str);
                _ = try query_builder.sql(")");
            }
        }

        const query = query_builder.build();
        _ = try self.connection.execSafe(query);
    }

    /// Delete a Post record
    pub fn delete(self: *@This(), options: struct { where: PostWhere }) !void {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("DELETE FROM \"posts\" WHERE ");
        var first_condition = true;

        // Build WHERE clause
        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.title) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("title = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.content) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("content = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.published) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("published = ");
                _ = try query_builder.sql(if (value) "true" else "false");
            }
        }
        if (options.where.authorId) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("authorId = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.createdAt) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "to_timestamp({d})", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("createdAt = ");
                _ = try query_builder.sql(val_str);
            }
        }

        const query = query_builder.build();
        _ = try self.connection.execSafe(query);
    }

};

/// CRUD operations for Profile model
pub const ProfileOperations = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection) ProfileOperations {
        return ProfileOperations{
            .allocator = allocator,
            .connection = connection,
        };
    }

    pub const ProfileWhere = struct {
        id: ?IntFilter = null,
        bio: ?StringFilter = null,
        userId: ?IntFilter = null,
    };

    pub const ProfileUpdateData = struct {
        id: ?i32 = null,
        bio: ?[]const u8 = null,
        userId: ?i32 = null,
    };

    /// Create a new Profile record
    pub fn create(self: *@This(), data: Profile) !Profile {
        const columns = [_][]const u8{"id", "bio", "user_id"};
        const values = try data.toSqlValues(self.allocator);
        defer self.allocator.free(values);
        const key_list = std.mem.join(self.allocator, ", ", &columns) catch "";
        defer self.allocator.free(key_list);
        const val_list = values;
        const query = try std.fmt.allocPrint(self.allocator, 
            "INSERT INTO \"profile\" ({s}) VALUES ({s}) RETURNING *;",
            .{ key_list, val_list }
        );
        defer self.allocator.free(query);
        var result = try self.connection.execSafe(query);
        
        if (result.next()) |row| {
            var record: Profile = undefined;
            record.id = try row.get("id", i32);
            record.bio = try row.getOpt("bio", []const u8);
            record.userId = try row.get("user_id", i32);
            return record;
        }
        
        return data; // Fallback if no result returned
    }

    /// Find multiple Profile records
    pub fn findMany(self: *@This(), options: struct { where: ?ProfileWhere = null }) ![]Profile {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("SELECT * FROM \"profile\"");
        if (options.where) |where_clause| {
            // TODO: Build WHERE clause from where_clause
            _ = where_clause;
        }

        const query = query_builder.build();
        var result = try self.connection.execSafe(query);
        const row_count = result.rowCount();
        var records = try self.allocator.alloc(Profile, @intCast(row_count));
        errdefer self.allocator.free(records);

        var idx: usize = 0;
        while (result.next()) |row| : (idx += 1) {
            records[idx].id = try row.get("id", i32);
            records[idx].bio = try row.getOpt("bio", []const u8);
            records[idx].userId = try row.get("user_id", i32);
        }

        return records;
    }

    /// Find a unique Profile record
    pub fn findUnique(self: *@This(), options: struct { where: ProfileWhere }) !?Profile {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("SELECT * FROM \"profile\" WHERE ");
        var first_condition = true;

        // Build WHERE clause for unique fields
        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.bio) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("bio = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.userId) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("user_id = ");
                _ = try query_builder.sql(val_str);
            }
        }

        _ = try query_builder.sql(" LIMIT 1");
        const query = query_builder.build();
        var result = try self.connection.execSafe(query);
        
        if (result.rowCount() == 0) {
            return null;
        }

        if (result.next()) |row| {
            var record: Profile = undefined;
            record.id = try row.get("id", i32);
            record.bio = try row.getOpt("bio", []const u8);
            record.userId = try row.get("user_id", i32);
            return record;
        }

        return null;
    }

    /// Update a Profile record
    pub fn update(self: *@This(), options: struct { where: ProfileWhere, data: ProfileUpdateData }) !void {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("UPDATE \"profile\" SET ");
        var first_field = true;

        // Build SET clause - only update fields that are provided
        if (options.data.bio) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            _ = try query_builder.sql("bio = '");
            _ = try query_builder.sql(value);
            _ = try query_builder.sql("'");
        }
        if (options.data.userId) |value| {
            if (!first_field) {
                _ = try query_builder.sql(", ");
            }
            first_field = false;
            const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
            defer self.allocator.free(val_str);
            _ = try query_builder.sql("user_id = ");
            _ = try query_builder.sql(val_str);
        }

        // Build WHERE clause
        _ = try query_builder.sql(" WHERE ");
        var first_condition = true;

        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.bio) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("bio = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.userId) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("user_id = ");
                _ = try query_builder.sql(val_str);
            }
        }

        const query = query_builder.build();
        _ = try self.connection.execSafe(query);
    }

    /// Delete a Profile record
    pub fn delete(self: *@This(), options: struct { where: ProfileWhere }) !void {
        var query_builder = QueryBuilder.init(self.allocator);
        defer query_builder.deinit();
        _ = try query_builder.sql("DELETE FROM \"profile\" WHERE ");
        var first_condition = true;

        // Build WHERE clause
        if (options.where.id) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("id = ");
                _ = try query_builder.sql(val_str);
            }
        }
        if (options.where.bio) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                _ = try query_builder.sql("bio = '");
                _ = try query_builder.sql(value);
                _ = try query_builder.sql("'");
            }
        }
        if (options.where.userId) |filter| {
            if (filter.equals) |value| {
                if (!first_condition) {
                    _ = try query_builder.sql(" AND ");
                }
                first_condition = false;
                const val_str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                defer self.allocator.free(val_str);
                _ = try query_builder.sql("user_id = ");
                _ = try query_builder.sql(val_str);
            }
        }

        const query = query_builder.build();
        _ = try self.connection.execSafe(query);
    }

};

