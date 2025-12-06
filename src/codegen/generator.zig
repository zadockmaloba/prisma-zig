const std = @import("std");
const schema_types = @import("../schema/types.zig");

const Schema = schema_types.Schema;
const PrismaModel = schema_types.PrismaModel;
const Field = schema_types.Field;
const FieldType = schema_types.FieldType;
const FieldAttribute = schema_types.FieldAttribute;

/// Code generation errors
pub const CodeGenError = error{
    OutOfMemory,
    InvalidModel,
    InvalidField,
    UnsupportedType,
};

/// Main code generator struct
pub const Generator = struct {
    allocator: std.mem.Allocator,
    schema: *const Schema,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, schema: *const Schema) Generator {
        return Generator{
            .allocator = allocator,
            .schema = schema,
            .output = .empty,
        };
    }

    pub fn deinit(self: *Generator) void {
        self.output.deinit(self.allocator);
    }

    /// Generate complete client code for all models in the schema
    pub fn generateClient(self: *Generator) CodeGenError![]u8 {
        // Generate file header
        try self.generateHeader();

        // Generate model structs
        for (self.schema.models.items) |*model| {
            try self.generateModelStruct(model);
            try self.output.append(self.allocator, '\n');
        }

        // Generate where clause types
        try self.generateWhereTypes();

        // Generate client struct with CRUD operations
        try self.generateClientStruct();

        // Generate model-specific namespaces with operations
        for (self.schema.models.items) |*model| {
            try self.generateModelOperations(model);
        }

        return self.output.toOwnedSlice(self.allocator);
    }

    /// Generate file imports and basic setup
    fn generateHeader(self: *Generator) CodeGenError!void {
        const header =
            \\const std = @import("std");
            \\const psql = @import("libpq_zig");
            \\const dt = @import("datetime");
            \\
            \\pub const Connection = psql.Connection;
            \\pub const QueryBuilder = psql.QueryBuilder;
            \\pub const ResultSet = psql.ResultSet;
            \\
            \\/// Generated Prisma client for type-safe database operations
            \\
        ;
        try self.output.appendSlice(self.allocator, header);
    }

    /// Generate a Zig struct for a Prisma model
    fn generateModelStruct(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        // Generate struct comment
        try self.output.writer(self.allocator).print("/// {s} model struct\n", .{model.name});
        try self.output.writer(self.allocator).print("pub const {s} = struct {{\n", .{model.name});

        // Generate fields
        for (model.fields.items) |*field| {
            // Skip relationship fields for now - they'll be handled separately
            if (field.type.isRelation()) {
                continue;
            }

            const zig_type = field.type.toZigType();
            const optional_marker = if (field.optional) "?" else "";

            // Add field comment with database column info
            const column_name = field.getColumnName();
            try self.output.writer(self.allocator).print("    /// Database column: {s}\n", .{column_name});

            // Add constraint information
            if (field.isPrimaryKey()) {
                try self.output.appendSlice(self.allocator, "    /// Primary key\n");
            }
            if (field.isUnique() and !field.isPrimaryKey()) {
                try self.output.appendSlice(self.allocator, "    /// Unique constraint\n");
            }
            if (field.getDefaultValue()) |default_val| {
                try self.output.writer(self.allocator).print("    /// Default: {s}\n", .{default_val});
            }

            try self.output.writer(self.allocator).print("    {s}: {s}{s},\n", .{ field.name, optional_marker, zig_type });
        }

        // Generate helper methods
        try self.generateModelMethods(model);

        try self.output.appendSlice(self.allocator, "};\n");
    }

    /// Generate helper methods for a model struct
    fn generateModelMethods(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        // Generate init method
        try self.output.appendSlice(self.allocator, "\n    /// Initialize a new instance\n");
        try self.output.writer(self.allocator).print("    pub fn init(", .{});

        // Add required fields as parameters (exclude auto-increment primary keys and fields with defaults)
        var first = true;
        for (model.fields.items) |*field| {
            // Skip relationship fields, optional fields, and fields with defaults
            if (field.type.isRelation() or field.optional or field.getDefaultValue() != null) {
                continue;
            }
            // Skip primary keys with autoincrement (they're database-generated)
            if (field.isPrimaryKey() and field.getDefaultValue() != null) {
                continue;
            }
            if (!first) try self.output.appendSlice(self.allocator, ", ");
            first = false;
            try self.output.writer(self.allocator).print("{s}: {s}", .{ field.name, field.type.toZigType() });
        }

        try self.output.writer(self.allocator).print(") {s} {{\n", .{model.name});
        try self.output.writer(self.allocator).print("        return {s}{{\n", .{model.name});

        // Initialize all fields
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) {
                // Skip relationship fields - they'll be loaded separately
                continue;
            } else if (!field.optional and field.getDefaultValue() == null) {
                try self.output.writer(self.allocator).print("            .{s} = {s},\n", .{ field.name, field.name });
            } else if (field.getDefaultValue()) |default_val| {
                // Handle different default value types - skip autoincrement as it's undefined
                if (std.mem.eql(u8, default_val, "autoincrement()")) {
                    try self.output.writer(self.allocator).print("            .{s} = undefined,\n", .{field.name});
                } else if (std.mem.eql(u8, default_val, "now()")) {
                    try self.output.writer(self.allocator).print("            .{s} = std.time.timestamp(),\n", .{field.name});
                } else if (field.type == .string) {
                    try self.output.writer(self.allocator).print("            .{s} = \"{s}\",\n", .{ field.name, default_val });
                } else {
                    try self.output.writer(self.allocator).print("            .{s} = {s},\n", .{ field.name, default_val });
                }
            } else {
                try self.output.writer(self.allocator).print("            .{s} = null,\n", .{field.name});
            }
        }

        try self.output.appendSlice(self.allocator, "        };\n    }\n");

        // Generate toSql method for CREATE operations
        try self.generateToSqlMethod(model);
    }

    /// Generate toSql method for converting struct to SQL values
    fn generateToSqlMethod(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;

        try output.appendSlice(self.allocator, "\n    /// Convert to SQL values for INSERT/UPDATE\n");
        try output.appendSlice(self.allocator, "    pub fn toSqlValues(self: *const @This(), allocator: std.mem.Allocator, columns: []const []const u8) ![]const u8 {\n");
        try output.appendSlice(self.allocator, "        var values: std.ArrayList(u8) = .empty;\n");
        try output.appendSlice(self.allocator, "        var first: bool = true;\n");
        try output.appendSlice(self.allocator, "\n        // Helper to check if column is in the list\n");
        try output.appendSlice(self.allocator, "        const hasColumn = struct {\n");
        try output.appendSlice(self.allocator, "            fn contains(cols: []const []const u8, name: []const u8) bool {\n");
        try output.appendSlice(self.allocator, "                for (cols) |col| {\n");
        try output.appendSlice(self.allocator, "                    if (std.mem.eql(u8, col, name)) return true;\n");
        try output.appendSlice(self.allocator, "                }\n");
        try output.appendSlice(self.allocator, "                return false;\n");
        try output.appendSlice(self.allocator, "            }\n");
        try output.appendSlice(self.allocator, "        }.contains;\n");

        for (model.fields.items) |*field| {
            // Skip relationship fields in SQL generation
            if (field.type.isRelation()) {
                continue;
            }

            const column_name = field.getColumnName();
            try output.writer(self.allocator).print("\n        // Process {s} field\n", .{field.name});
            try output.writer(self.allocator).print("        if (hasColumn(columns, \"{s}\")) {{\n", .{column_name});

            if (!field.optional) {
                // Non-optional fields
                try output.appendSlice(self.allocator, "            if (!first) try values.appendSlice(allocator, \", \");\n");
                try output.appendSlice(self.allocator, "            first = false;\n");
                switch (field.type) {
                    .string => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"'{{s}}'\", .{{self.{s}}});\n", .{field.name}),
                    .int => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"{{d}}\", .{{self.{s}}});\n", .{field.name}),
                    .boolean => try output.writer(self.allocator).print("            try values.appendSlice(allocator, if (self.{s}) \"true\" else \"false\");\n", .{field.name}),
                    .datetime => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"to_timestamp({{d}})\", .{{self.{s}}});\n", .{field.name}),
                    .model_ref, .model_array => {
                        // Relationship fields should be skipped above, but handle gracefully
                        try output.appendSlice(self.allocator, "            // Relationship field - handled separately\n");
                    },
                }
                try output.appendSlice(self.allocator, "        }\n");
                continue;
            }

            // Optional fields
            try output.appendSlice(self.allocator, "            if (!first) try values.appendSlice(allocator, \", \");\n");
            try output.appendSlice(self.allocator, "            first = false;\n");
            try output.writer(self.allocator).print("            if (self.{s}) |val| {{\n", .{field.name});

            switch (field.type) {
                .string => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"'{s}'\", .{val});\n"),
                .int => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"{d}\", .{val});\n"),
                .boolean => try output.appendSlice(self.allocator, "                try values.appendSlice(allocator, if (val) \"true\" else \"false\");\n"),
                .datetime => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"to_timestamp({d})\", .{val});\n"),
                .model_ref, .model_array => {
                    // Relationship fields should be skipped above, but handle gracefully
                    try output.appendSlice(self.allocator, "                // Relationship field - handled separately\n");
                },
            }

            try output.appendSlice(self.allocator, "            } else {\n");
            try output.appendSlice(self.allocator, "                try values.appendSlice(allocator, \"NULL\");\n");
            try output.appendSlice(self.allocator, "            }\n");
            try output.appendSlice(self.allocator, "        }\n");
        }

        try output.appendSlice(self.allocator, "        return values.toOwnedSlice(allocator);\n");
        try output.appendSlice(self.allocator, "    }\n");
    }

    /// Generate WHERE clause types for type-safe querying
    fn generateWhereTypes(self: *Generator) CodeGenError!void {
        var output = &self.output;

        try output.appendSlice(self.allocator, "/// String filter options\n");
        try output.appendSlice(self.allocator, "pub const StringFilter = struct {\n");
        try output.appendSlice(self.allocator, "    equals: ?[]const u8 = null,\n");
        try output.appendSlice(self.allocator, "    contains: ?[]const u8 = null,\n");
        try output.appendSlice(self.allocator, "    startsWith: ?[]const u8 = null,\n");
        try output.appendSlice(self.allocator, "    endsWith: ?[]const u8 = null,\n");
        try output.appendSlice(self.allocator, "};\n\n");

        try output.appendSlice(self.allocator, "/// Integer filter options\n");
        try output.appendSlice(self.allocator, "pub const IntFilter = struct {\n");
        try output.appendSlice(self.allocator, "    equals: ?i32 = null,\n");
        try output.appendSlice(self.allocator, "    lt: ?i32 = null,\n");
        try output.appendSlice(self.allocator, "    lte: ?i32 = null,\n");
        try output.appendSlice(self.allocator, "    gt: ?i32 = null,\n");
        try output.appendSlice(self.allocator, "    gte: ?i32 = null,\n");
        try output.appendSlice(self.allocator, "};\n\n");

        try output.appendSlice(self.allocator, "/// Boolean filter options\n");
        try output.appendSlice(self.allocator, "pub const BooleanFilter = struct {\n");
        try output.appendSlice(self.allocator, "    equals: ?bool = null,\n");
        try output.appendSlice(self.allocator, "};\n\n");

        try output.appendSlice(self.allocator, "/// DateTime filter options\n");
        try output.appendSlice(self.allocator, "pub const DateTimeFilter = struct {\n");
        try output.appendSlice(self.allocator, "    equals: ?i64 = null,\n");
        try output.appendSlice(self.allocator, "    lt: ?i64 = null,\n");
        try output.appendSlice(self.allocator, "    lte: ?i64 = null,\n");
        try output.appendSlice(self.allocator, "    gt: ?i64 = null,\n");
        try output.appendSlice(self.allocator, "    gte: ?i64 = null,\n");
        try output.appendSlice(self.allocator, "};\n\n");
    }

    /// Generate the main client struct
    fn generateClientStruct(self: *Generator) CodeGenError!void {
        var output = &self.output;
        try output.appendSlice(self.allocator, "/// Main Prisma client\n");
        try output.appendSlice(self.allocator, "pub const PrismaClient = struct {\n");
        try output.appendSlice(self.allocator, "    allocator: std.mem.Allocator,\n");
        try output.appendSlice(self.allocator, "    connection: *Connection,\n");

        // Generate model namespaces
        for (self.schema.models.items) |*model| {
            const lowercase_name = try self.toLowercase(model.name);
            defer self.allocator.free(lowercase_name);
            try output.writer(self.allocator).print("    {s}: {s}Operations,\n", .{ lowercase_name, model.name });
        }

        try output.appendSlice(self.allocator, "\n    pub fn init(allocator: std.mem.Allocator, connection: *Connection) PrismaClient {\n");
        try output.appendSlice(self.allocator, "        return PrismaClient{\n");
        try output.appendSlice(self.allocator, "            .allocator = allocator,\n");
        try output.appendSlice(self.allocator, "            .connection = connection,\n");

        // Initialize model operations
        for (self.schema.models.items) |*model| {
            const lowercase_name = try self.toLowercase(model.name);
            defer self.allocator.free(lowercase_name);
            try output.writer(self.allocator).print("            .{s} = {s}Operations.init(allocator, connection),\n", .{ lowercase_name, model.name });
        }

        try output.appendSlice(self.allocator, "        };\n");
        try output.appendSlice(self.allocator, "    }\n");
        try output.appendSlice(self.allocator, "};\n\n");
    }

    /// Generate CRUD operations for a specific model
    fn generateModelOperations(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;
        try output.writer(self.allocator).print("/// CRUD operations for {s} model\n", .{model.name});
        try output.writer(self.allocator).print("pub const {s}Operations = struct {{\n", .{model.name});
        try output.appendSlice(self.allocator, "    allocator: std.mem.Allocator,\n");
        try output.appendSlice(self.allocator, "    connection: *Connection,\n");
        try output.appendSlice(self.allocator, "\n");

        try output.writer(self.allocator).print("    pub fn init(allocator: std.mem.Allocator, connection: *Connection) {s}Operations {{\n", .{model.name});
        try output.writer(self.allocator).print("        return {s}Operations{{\n", .{model.name});
        try output.appendSlice(self.allocator, "            .allocator = allocator,\n");
        try output.appendSlice(self.allocator, "            .connection = connection,\n");
        try output.appendSlice(self.allocator, "        };\n");
        try output.appendSlice(self.allocator, "    }\n\n");

        // Generate WHERE type for this model
        try self.generateModelWhereType(model);

        // Generate CREATE operation
        try self.generateCreateOperation(model);

        // Generate FIND operations
        try self.generateFindManyOperation(model);
        try self.generateFindUniqueOperation(model);

        // Generate UPDATE operation
        try self.generateUpdateOperation(model);

        // Generate DELETE operation
        try self.generateDeleteOperation(model);

        try output.appendSlice(self.allocator, "};\n\n");
    }

    /// Generate WHERE type for a specific model
    fn generateModelWhereType(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;

        try output.writer(self.allocator).print("    pub const {s}Where = struct {{\n", .{model.name});

        for (model.fields.items) |*field| {
            // Skip relationship fields in WHERE clauses for now
            if (field.type.isRelation()) {
                continue;
            }

            const filter_type = switch (field.type) {
                .string => "StringFilter",
                .int => "IntFilter",
                .boolean => "BooleanFilter",
                .datetime => "DateTimeFilter",
                .model_ref, .model_array => unreachable, // Should be skipped above
            };

            try output.writer(self.allocator).print("        {s}: ?{s} = null,\n", .{ field.name, filter_type });
        }

        try output.appendSlice(self.allocator, "    };\n\n");

        // Generate UpdateData type with all optional fields
        try output.writer(self.allocator).print("    pub const {s}UpdateData = struct {{\n", .{model.name});

        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const zig_type = field.type.toZigType();
            try output.writer(self.allocator).print("        {s}: ?{s} = null,\n", .{ field.name, zig_type });
        }

        try output.appendSlice(self.allocator, "    };\n\n");
    }

    /// Generate CREATE operation
    fn generateCreateOperation(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        const table_name = try model.getTableName(self.allocator);
        defer if (table_name.heap_allocated) self.allocator.free(table_name.value);
        var output = &self.output;

        try output.writer(self.allocator).print("    /// Create a new {s} record\n", .{model.name});
        try output.writer(self.allocator).print("    pub fn create(self: *@This(), data: {s}) !{s} {{\n", .{ model.name, model.name });

        // Build INSERT query
        try output.writer(self.allocator).print("        const columns = [_][]const u8{{", .{});
        var first = true;
        for (model.fields.items) |*field| {
            if (field.isPrimaryKey() and field.getDefaultValue() != null) continue;
            if (field.type.isRelation()) continue; // Skip relationship fields
            if (!first) try output.appendSlice(self.allocator, ", ");
            first = false;
            try output.writer(self.allocator).print("\"{s}\"", .{field.getColumnName()});
        }
        try output.appendSlice(self.allocator, "};\n");

        try output.appendSlice(self.allocator, "        const values = try data.toSqlValues(self.allocator, &columns);\n");
        try output.appendSlice(self.allocator, "        defer self.allocator.free(values);\n");

        try output.appendSlice(self.allocator, "        const key_list = std.mem.join(self.allocator, \", \", &columns) catch \"\";\n");
        try output.appendSlice(self.allocator, "        defer self.allocator.free(key_list);\n");
        try output.appendSlice(self.allocator, "        const val_list = values;\n");

        try output.writer(self.allocator).print("        const query = try std.fmt.allocPrint(self.allocator, \n", .{});
        try output.writer(self.allocator).print("            \"INSERT INTO \\\"{s}\\\" ({{s}}) VALUES ({{s}}) RETURNING *;\",\n", .{table_name.value});
        try output.appendSlice(self.allocator, "            .{ key_list, val_list }\n");
        try output.appendSlice(self.allocator, "        );\n");
        try output.appendSlice(self.allocator, "        defer self.allocator.free(query);\n");

        try output.appendSlice(self.allocator, "        var result = try self.connection.execSafe(query);\n");
        try output.appendSlice(self.allocator, "        \n");
        try output.appendSlice(self.allocator, "        if (result.next()) |row| {\n");
        try output.appendSlice(self.allocator, "            var record: ");
        try output.writer(self.allocator).print("{s} = undefined;\n", .{model.name});

        // Generate field parsing for the returned record
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const column_name = field.getColumnName();

            if (field.optional) {
                // Optional field handling
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"{s}\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"{s}\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"{s}\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"{s}\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            record.{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                // Non-optional field handling
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"{s}\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"{s}\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"{s}\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            record.{s} = try dt.unixTimeFromISO8601(try row.get(\"{s}\", []const u8));\n", .{ field.name, column_name });
                    },
                    else => {},
                }
            }
        }

        try output.appendSlice(self.allocator, "            return record;\n");
        try output.appendSlice(self.allocator, "        }\n");
        try output.appendSlice(self.allocator, "        \n");
        try output.appendSlice(self.allocator, "        return data; // Fallback if no result returned\n");
        try output.appendSlice(self.allocator, "    }\n\n");
    }

    /// Generate FIND_MANY operation
    fn generateFindManyOperation(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;
        const table_name = try model.getTableName(self.allocator);
        defer if (table_name.heap_allocated) self.allocator.free(table_name.value);

        try output.writer(self.allocator).print("    /// Find multiple {s} records\n", .{model.name});
        try output.writer(self.allocator).print("    pub fn findMany(self: *@This(), options: struct {{ where: ?{s}Where = null }}) ![]{s} {{\n", .{ model.name, model.name });

        try output.writer(self.allocator).print("        var query_builder = QueryBuilder.init(self.allocator);\n", .{});
        try output.appendSlice(self.allocator, "        defer query_builder.deinit();\n");

        try output.writer(self.allocator).print("        _ = try query_builder.sql(\"SELECT * FROM \\\"{s}\\\"\");\n", .{table_name.value});

        try output.appendSlice(self.allocator, "        if (options.where) |where_clause| {\n");
        try output.appendSlice(self.allocator, "            // TODO: Build WHERE clause from where_clause\n");
        try output.appendSlice(self.allocator, "            _ = where_clause;\n");
        try output.appendSlice(self.allocator, "        }\n\n");

        try output.appendSlice(self.allocator, "        const query = query_builder.build();\n");
        try output.appendSlice(self.allocator, "        var result = try self.connection.execSafe(query);\n");
        //try output.appendSlice(self.allocator, "        defer result.deinit();\n\n");

        try output.appendSlice(self.allocator, "        const row_count = result.rowCount();\n");
        try output.writer(self.allocator).print("        var records = try self.allocator.alloc({s}, @intCast(row_count));\n", .{model.name});
        try output.appendSlice(self.allocator, "        errdefer self.allocator.free(records);\n\n");

        try output.appendSlice(self.allocator, "        var idx: usize = 0;\n");
        try output.appendSlice(self.allocator, "        while (result.next()) |row| : (idx += 1) {\n");

        // Generate field parsing for each field
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const column_name = field.getColumnName();

            if (field.optional) {
                // Optional field handling
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.getOpt(\"{s}\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.getOpt(\"{s}\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.getOpt(\"{s}\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"{s}\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            records[idx].{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                // Non-optional field handling
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.get(\"{s}\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.get(\"{s}\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.get(\"{s}\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try dt.unixTimeFromISO8601( try row.get(\"{s}\", []const u8) );\n", .{ field.name, column_name });
                    },
                    else => {},
                }
            }
        }

        try output.appendSlice(self.allocator, "        }\n\n");
        try output.appendSlice(self.allocator, "        return records;\n");
        try output.appendSlice(self.allocator, "    }\n\n");
    }

    /// Generate FIND_UNIQUE operation
    fn generateFindUniqueOperation(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;
        const table_name = try model.getTableName(self.allocator);
        defer if (table_name.heap_allocated) self.allocator.free(table_name.value);

        try output.writer(self.allocator).print("    /// Find a unique {s} record\n", .{model.name});
        try output.writer(self.allocator).print("    pub fn findUnique(self: *@This(), options: struct {{ where: {s}Where }}) !?{s} {{\n", .{ model.name, model.name });

        try output.appendSlice(self.allocator, "        var query_builder = QueryBuilder.init(self.allocator);\n");
        try output.appendSlice(self.allocator, "        defer query_builder.deinit();\n");
        try output.writer(self.allocator).print("        _ = try query_builder.sql(\"SELECT * FROM \\\"{s}\\\" WHERE \");\n", .{table_name.value});

        try output.appendSlice(self.allocator, "        var first_condition = true;\n\n");

        // Build WHERE conditions for unique fields
        try output.appendSlice(self.allocator, "        // Build WHERE clause for unique fields\n");
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const filter_type = switch (field.type) {
                .string => "StringFilter",
                .int => "IntFilter",
                .boolean => "BooleanFilter",
                .datetime => "DateTimeFilter",
                else => continue,
            };
            _ = filter_type;

            const column_name = field.getColumnName();

            try output.writer(self.allocator).print("        if (options.where.{s}) |filter| {{\n", .{field.name});
            try output.appendSlice(self.allocator, "            if (filter.equals) |value| {\n");
            try output.appendSlice(self.allocator, "                if (!first_condition) {\n");
            try output.appendSlice(self.allocator, "                    _ = try query_builder.sql(\" AND \");\n");
            try output.appendSlice(self.allocator, "                }\n");
            try output.appendSlice(self.allocator, "                first_condition = false;\n");

            switch (field.type) {
                .string => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.writer(self.allocator).print("                const val_str = try std.fmt.allocPrint(self.allocator, \"{{d}}\", .{{value}});\n", .{});
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(if (value) \"true\" else \"false\");\n");
                },
                .datetime => {
                    try output.writer(self.allocator).print("                const val_str = try std.fmt.allocPrint(self.allocator, \"to_timestamp({{d}})\", .{{value}});\n", .{});
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                else => {},
            }

            try output.appendSlice(self.allocator, "            }\n");
            //try output.writer(self.allocator).print("            _ = filter; // Silence unused variable warning for other {s} fields\n", .{filter_type});
            try output.appendSlice(self.allocator, "        }\n");
        }

        try output.appendSlice(self.allocator, "\n        _ = try query_builder.sql(\" LIMIT 1\");\n");
        try output.appendSlice(self.allocator, "        const query = query_builder.build();\n");
        try output.appendSlice(self.allocator, "        var result = try self.connection.execSafe(query);\n");
        try output.appendSlice(self.allocator, "        \n");
        try output.appendSlice(self.allocator, "        if (result.rowCount() == 0) {\n");
        try output.appendSlice(self.allocator, "            return null;\n");
        try output.appendSlice(self.allocator, "        }\n\n");

        try output.appendSlice(self.allocator, "        if (result.next()) |row| {\n");
        try output.writer(self.allocator).print("            var record: {s} = undefined;\n", .{model.name});

        // Generate field parsing for each field (same as findMany)
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const column_name = field.getColumnName();

            if (field.optional) {
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"{s}\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"{s}\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"{s}\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"{s}\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            record.{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"{s}\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"{s}\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"{s}\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            record.{s} = try dt.unixTimeFromISO8601(try row.get(\"{s}\", []const u8));\n", .{ field.name, column_name });
                    },
                    else => {},
                }
            }
        }

        try output.appendSlice(self.allocator, "            return record;\n");
        try output.appendSlice(self.allocator, "        }\n\n");
        try output.appendSlice(self.allocator, "        return null;\n");
        try output.appendSlice(self.allocator, "    }\n\n");
    }

    /// Generate UPDATE operation
    fn generateUpdateOperation(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;
        const table_name = try model.getTableName(self.allocator);
        defer if (table_name.heap_allocated) self.allocator.free(table_name.value);

        try output.writer(self.allocator).print("    /// Update a {s} record\n", .{model.name});
        try output.writer(self.allocator).print("    pub fn update(self: *@This(), options: struct {{ where: {s}Where, data: {s}UpdateData }}) !void {{\n", .{ model.name, model.name });

        try output.appendSlice(self.allocator, "        var query_builder = QueryBuilder.init(self.allocator);\n");
        try output.appendSlice(self.allocator, "        defer query_builder.deinit();\n");
        try output.writer(self.allocator).print("        _ = try query_builder.sql(\"UPDATE \\\"{s}\\\" SET \");\n", .{table_name.value});
        try output.appendSlice(self.allocator, "        var first_field = true;\n\n");

        // Generate SET clause for each non-primary-key field
        try output.appendSlice(self.allocator, "        // Build SET clause - only update fields that are provided\n");
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;
            if (field.isPrimaryKey()) continue; // Don't update primary keys

            const column_name = field.getColumnName();

            // All fields in UpdateData are optional, so always check if they're provided
            try output.writer(self.allocator).print("        if (options.data.{s}) |value| {{\n", .{field.name});
            try output.appendSlice(self.allocator, "            if (!first_field) {\n");
            try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\", \");\n");
            try output.appendSlice(self.allocator, "            }\n");
            try output.appendSlice(self.allocator, "            first_field = false;\n");

            switch (field.type) {
                .string => {
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"{s} = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.appendSlice(self.allocator, "            const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "            defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.appendSlice(self.allocator, "            const bool_str = if (value) \"TRUE\" else \"FALSE\";\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(bool_str);\n");
                },
                .datetime => {
                    try output.appendSlice(self.allocator, "            const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "            defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"{s} = to_timestamp(\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(val_str);\n");
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(\")\");\n");
                },
                else => {},
            }
            try output.appendSlice(self.allocator, "        }\n");
        }

        // Generate WHERE clause
        try output.appendSlice(self.allocator, "\n        // Build WHERE clause\n");
        try output.appendSlice(self.allocator, "        _ = try query_builder.sql(\" WHERE \");\n");
        try output.appendSlice(self.allocator, "        var first_condition = true;\n\n");

        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const column_name = field.getColumnName();
            const filter_prefix = if (field.isPrimaryKey() or field.isUnique()) "" else "";

            try output.writer(self.allocator).print("        if (options.where.{s}) |filter| {{\n", .{field.name});
            try output.appendSlice(self.allocator, "            if (filter.equals) |value| {\n");
            try output.appendSlice(self.allocator, "                if (!first_condition) {\n");
            try output.appendSlice(self.allocator, "                    _ = try query_builder.sql(\" AND \");\n");
            try output.appendSlice(self.allocator, "                }\n");
            try output.appendSlice(self.allocator, "                first_condition = false;\n");

            switch (field.type) {
                .string => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.appendSlice(self.allocator, "                const bool_str = if (value) \"TRUE\" else \"FALSE\";\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(bool_str);\n");
                },
                .datetime => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = to_timestamp(\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\")\");\n");
                },
                else => {},
            }

            try output.appendSlice(self.allocator, "            }\n");
            try output.appendSlice(self.allocator, "        }\n");
            _ = filter_prefix;
        }

        try output.appendSlice(self.allocator, "\n        const query = query_builder.build();\n");
        try output.appendSlice(self.allocator, "        _ = try self.connection.execSafe(query);\n");
        try output.appendSlice(self.allocator, "    }\n\n");
    }

    /// Generate DELETE operation
    fn generateDeleteOperation(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;
        const table_name = try model.getTableName(self.allocator);
        defer if (table_name.heap_allocated) self.allocator.free(table_name.value);

        try output.writer(self.allocator).print("    /// Delete a {s} record\n", .{model.name});
        try output.writer(self.allocator).print("    pub fn delete(self: *@This(), options: struct {{ where: {s}Where }}) !void {{\n", .{model.name});

        try output.appendSlice(self.allocator, "        var query_builder = QueryBuilder.init(self.allocator);\n");
        try output.appendSlice(self.allocator, "        defer query_builder.deinit();\n");
        try output.writer(self.allocator).print("        _ = try query_builder.sql(\"DELETE FROM \\\"{s}\\\" WHERE \");\n", .{table_name.value});
        try output.appendSlice(self.allocator, "        var first_condition = true;\n\n");

        // Generate WHERE clause for all fields
        try output.appendSlice(self.allocator, "        // Build WHERE clause\n");
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const column_name = field.getColumnName();

            try output.writer(self.allocator).print("        if (options.where.{s}) |filter| {{\n", .{field.name});
            try output.appendSlice(self.allocator, "            if (filter.equals) |value| {\n");
            try output.appendSlice(self.allocator, "                if (!first_condition) {\n");
            try output.appendSlice(self.allocator, "                    _ = try query_builder.sql(\" AND \");\n");
            try output.appendSlice(self.allocator, "                }\n");
            try output.appendSlice(self.allocator, "                first_condition = false;\n");

            switch (field.type) {
                .string => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(if (value) \"true\" else \"false\");\n");
                },
                .datetime => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"to_timestamp({d})\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"{s} = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                else => {},
            }

            try output.appendSlice(self.allocator, "            }\n");
            try output.appendSlice(self.allocator, "        }\n");
        }

        try output.appendSlice(self.allocator, "\n        const query = query_builder.build();\n");
        try output.appendSlice(self.allocator, "        _ = try self.connection.execSafe(query);\n");
        try output.appendSlice(self.allocator, "    }\n\n");
    }

    /// Helper function to convert string to lowercase
    fn toLowercase(self: *Generator, input: []const u8) ![]u8 {
        const result = try self.allocator.alloc(u8, input.len);
        for (input, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return result;
    }
};

// Tests
test "generate simple model struct" {
    const allocator = std.testing.allocator;

    // Create a simple schema for testing
    var schema = Schema.init(allocator);
    defer schema.deinit();

    var user_model = try PrismaModel.init(allocator, "User");

    var id_field = try Field.init(allocator, "id", .int);
    try id_field.attributes.append(allocator, .id);
    try user_model.addField(id_field);

    const name_field = try Field.init(allocator, "name", .string);
    try user_model.addField(name_field);

    try schema.addModel(user_model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Basic checks
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "pub const User = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "id: i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "name: []const u8") != null);
}
