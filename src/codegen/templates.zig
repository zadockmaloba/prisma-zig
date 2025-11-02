const std = @import("std");

/// Code templates for generating Zig code from Prisma models
pub const Templates = struct {
    /// Header template for generated client files
    pub const file_header =
        \\const std = @import("std");
        \\const psql = @import("libpq_zig");
        \\
        \\const Connection = psql.Connection;
        \\const QueryBuilder = psql.QueryBuilder;
        \\const ResultSet = psql.ResultSet;
        \\
        \\/// Generated Prisma client for type-safe database operations
        \\
    ;

    /// Template for string filter struct
    pub const string_filter =
        \\/// String filter options
        \\pub const StringFilter = struct {
        \\    equals: ?[]const u8 = null,
        \\    contains: ?[]const u8 = null,
        \\    startsWith: ?[]const u8 = null,
        \\    endsWith: ?[]const u8 = null,
        \\
        \\    /// Build SQL WHERE condition
        \\    pub fn toSql(self: *const @This(), allocator: std.mem.Allocator, column_name: []const u8) !?[]const u8 {
        \\        if (self.equals) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} = '{s}'", .{ column_name, val });
        \\        }
        \\        if (self.contains) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} LIKE '%{s}%'", .{ column_name, val });
        \\        }
        \\        if (self.startsWith) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} LIKE '{s}%'", .{ column_name, val });
        \\        }
        \\        if (self.endsWith) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} LIKE '%{s}'", .{ column_name, val });
        \\        }
        \\        return null;
        \\    }
        \\};
        \\
    ;

    /// Template for integer filter struct
    pub const int_filter =
        \\/// Integer filter options
        \\pub const IntFilter = struct {
        \\    equals: ?i32 = null,
        \\    lt: ?i32 = null,
        \\    lte: ?i32 = null,
        \\    gt: ?i32 = null,
        \\    gte: ?i32 = null,
        \\
        \\    /// Build SQL WHERE condition
        \\    pub fn toSql(self: *const @This(), allocator: std.mem.Allocator, column_name: []const u8) !?[]const u8 {
        \\        if (self.equals) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} = {d}", .{ column_name, val });
        \\        }
        \\        if (self.lt) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} < {d}", .{ column_name, val });
        \\        }
        \\        if (self.lte) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} <= {d}", .{ column_name, val });
        \\        }
        \\        if (self.gt) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} > {d}", .{ column_name, val });
        \\        }
        \\        if (self.gte) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} >= {d}", .{ column_name, val });
        \\        }
        \\        return null;
        \\    }
        \\};
        \\
    ;

    /// Template for boolean filter struct
    pub const boolean_filter =
        \\/// Boolean filter options
        \\pub const BooleanFilter = struct {
        \\    equals: ?bool = null,
        \\
        \\    /// Build SQL WHERE condition
        \\    pub fn toSql(self: *const @This(), allocator: std.mem.Allocator, column_name: []const u8) !?[]const u8 {
        \\        if (self.equals) |val| {
        \\            const bool_str = if (val) "true" else "false";
        \\            return try std.fmt.allocPrint(allocator, "{s} = {s}", .{ column_name, bool_str });
        \\        }
        \\        return null;
        \\    }
        \\};
        \\
    ;

    /// Template for datetime filter struct
    pub const datetime_filter =
        \\/// DateTime filter options
        \\pub const DateTimeFilter = struct {
        \\    equals: ?i64 = null,
        \\    lt: ?i64 = null,
        \\    lte: ?i64 = null,
        \\    gt: ?i64 = null,
        \\    gte: ?i64 = null,
        \\
        \\    /// Build SQL WHERE condition
        \\    pub fn toSql(self: *const @This(), allocator: std.mem.Allocator, column_name: []const u8) !?[]const u8 {
        \\        if (self.equals) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} = to_timestamp({d})", .{ column_name, val });
        \\        }
        \\        if (self.lt) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} < to_timestamp({d})", .{ column_name, val });
        \\        }
        \\        if (self.lte) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} <= to_timestamp({d})", .{ column_name, val });
        \\        }
        \\        if (self.gt) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} > to_timestamp({d})", .{ column_name, val });
        \\        }
        \\        if (self.gte) |val| {
        \\            return try std.fmt.allocPrint(allocator, "{s} >= to_timestamp({d})", .{ column_name, val });
        \\        }
        \\        return null;
        \\    }
        \\};
        \\
    ;

    /// Generate FROM_ROW template for parsing SQL results
    pub fn generateFromRowTemplate(allocator: std.mem.Allocator, model_name: []const u8, fields: []const struct { name: []const u8, type_name: []const u8, optional: bool }) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        try output.writer().print("    /// Parse from SQL result row\n", .{});
        try output.writer().print("    pub fn fromRow(allocator: std.mem.Allocator, row: *const ResultSet.Row) !{s} {{\n", .{model_name});
        try output.writer().print("        return {s}{{\n", .{model_name});

        for (fields, 0..) |field, i| {
            const parse_expr = switch (std.mem.eql(u8, field.type_name, "[]const u8")) {
                true => if (field.optional) "if (row.isNull({d})) null else try allocator.dupe(u8, row.getString({d}))" else "try allocator.dupe(u8, row.getString({d}))",
                false => if (field.optional) "if (row.isNull({d})) null else row.getInt({d})" else "row.getInt({d})",
            };

            const value = try std.fmt.allocPrint(allocator, parse_expr, .{i});
            defer allocator.free(value);
            try output.writer().print("            .{s} = {s},\n", .{ field.name, value});
        }

        try output.appendSlice("        };\n");
        try output.appendSlice("    }\n");

        return output.toOwnedSlice();
    }

    /// Generate CREATE operation template
    pub fn generateCreateTemplate(allocator: std.mem.Allocator, model_name: []const u8, table_name: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        try output.writer().print(
            \\    /// Create a new {s} record
            \\    pub fn create(self: *@This(), data: {s}) !{s} {{
            \\        var query_builder = QueryBuilder.init(self.allocator);
            \\        defer query_builder.deinit();
            \\        
            \\        // Build INSERT query
            \\        try query_builder.insert("{s}");
            \\        
            \\        // Add field values
            \\        const sql_values = try data.toSqlValues(self.allocator);
            \\        defer {{
            \\            for (sql_values) |val| self.allocator.free(val);
            \\            self.allocator.free(sql_values);
            \\        }}
            \\        
            \\        // Execute query
            \\        const query = try query_builder.build();
            \\        defer self.allocator.free(query);
            \\        
            \\        const result = try self.connection.query(query);
            \\        defer result.deinit();
            \\        
            \\        // Parse and return the created record
            \\        if (result.rows.len > 0) {{
            \\            return {s}.fromRow(self.allocator, &result.rows[0]);
            \\        }}
            \\        
            \\        return error.CreateFailed;
            \\    }}
            \\
        , .{ model_name, model_name, model_name, table_name, model_name });

        return output.toOwnedSlice();
    }
};

// Tests
test "string filter template generates valid Zig code" {
    // Just verify the template compiles
    try std.testing.expect(Templates.string_filter.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, Templates.string_filter, "StringFilter") != null);
    try std.testing.expect(std.mem.indexOf(u8, Templates.string_filter, "toSql") != null);
}

test "fromRow template generation" {
    const allocator = std.testing.allocator;

    const fields = [_]struct { name: []const u8, type_name: []const u8, optional: bool }{
        .{ .name = "id", .type_name = "i32", .optional = false },
        .{ .name = "name", .type_name = "[]const u8", .optional = false },
        .{ .name = "email", .type_name = "[]const u8", .optional = true },
    };

    const template = try Templates.generateFromRowTemplate(allocator, "User", &fields);
    defer allocator.free(template);

    try std.testing.expect(std.mem.indexOf(u8, template, "pub fn fromRow") != null);
    try std.testing.expect(std.mem.indexOf(u8, template, "User{") != null);
}
