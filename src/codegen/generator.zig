const std = @import("std");
const schema_types = @import("../schema/types.zig");

const Schema = schema_types.Schema;
const PrismaModel = schema_types.PrismaModel;
const PrismaEnum = schema_types.PrismaEnum;
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

/// Check if a field is a true relation (not an enum)
fn isFieldRelation(field: *const Field, schema: *const Schema) bool {
    if (!field.type.isRelation()) return false;

    // If it's a model_ref, check if it's actually an enum
    if (field.type == .model_ref) {
        const type_name = field.type.model_ref;
        if (schema.getEnum(type_name)) |_| {
            // It's an enum, not a relation
            return false;
        }
    }

    return true;
}

/// Check if a name is a Zig keyword and needs escaping
// FIXME: This can be optimised
fn needsEscape(name: []const u8) bool {
    const keywords = [_][]const u8{
        "align",  "allowzero", "and",         "anyframe",       "anytype",     "asm",
        "async",  "await",     "break",       "callconv",       "catch",       "comptime",
        "const",  "continue",  "defer",       "else",           "enum",        "errdefer",
        "error",  "export",    "extern",      "fn",             "for",         "if",
        "inline", "noalias",   "nosuspend",   "noinline",       "opaque",      "or",
        "orelse", "packed",    "pub",         "resume",         "return",      "linksection",
        "struct", "suspend",   "switch",      "test",           "threadlocal", "try",
        "type",   "union",     "unreachable", "usingnamespace", "var",         "volatile",
        "while",
    };

    for (keywords) |keyword| {
        if (std.mem.eql(u8, name, keyword)) return true;
    }
    return false;
}

/// Escape a field name if it's a Zig keyword
fn escapeFieldName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (needsEscape(name)) {
        return std.fmt.allocPrint(allocator, "@\"{s}\"", .{name});
    }
    return name;
}

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

        // Generate enums
        for (self.schema.enums.items) |*prisma_enum| {
            try self.generateEnum(prisma_enum);
            try self.output.append(self.allocator, '\n');
        }

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
            \\pub const Json = []const u8;
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

    /// Generate a Zig enum from a Prisma enum
    fn generateEnum(self: *Generator, prisma_enum: *const schema_types.PrismaEnum) CodeGenError!void {
        // Generate enum comment
        try self.output.writer(self.allocator).print("/// {s} enum\n", .{prisma_enum.name});
        try self.output.writer(self.allocator).print("pub const {s} = enum {{\n", .{prisma_enum.name});

        // Generate enum values
        for (prisma_enum.values.items) |value| {
            try self.output.writer(self.allocator).print("    {s},\n", .{value});
        }

        try self.output.appendSlice(self.allocator, "};\n");
    }

    /// Generate a Zig struct for a Prisma model
    fn generateModelStruct(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        // Generate struct comment
        try self.output.writer(self.allocator).print("/// {s} model struct\n", .{model.name});
        try self.output.writer(self.allocator).print("pub const {s} = struct {{\n", .{model.name});

        // Generate fields
        for (model.fields.items) |*field| {
            // Skip relationship fields for now - they'll be handled separately
            // But keep enum fields (they're stored as values, not relations)
            if (isFieldRelation(field, self.schema)) {
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

            const escaped_name = try escapeFieldName(self.allocator, field.name);
            defer if (needsEscape(field.name)) self.allocator.free(escaped_name);
            try self.output.writer(self.allocator).print("    {s}: {s}{s},\n", .{ escaped_name, optional_marker, zig_type });
        }

        // Add allocator field for cached relation management
        try self.output.appendSlice(self.allocator, "\n    /// Allocator for cached relations (must be set to use cached loaders)\n");
        try self.output.appendSlice(self.allocator, "    _allocator: ?std.mem.Allocator = null,\n");

        // Add cached relation fields
        for (model.fields.items) |*field| {
            if (isFieldRelation(field, self.schema)) {
                const relation_type = field.type.toZigType();
                const optional_marker = if (field.optional or field.type.isArray()) "?" else "?";
                
                const escaped_name = try escapeFieldName(self.allocator, field.name);
                defer if (needsEscape(field.name)) self.allocator.free(escaped_name);
                
                try self.output.writer(self.allocator).print("    /// Cached {s} relation\n", .{field.name});
                if (field.type.isArray()) {
                    // For array relations, cache the slice
                    const model_name = field.type.getModelName().?;
                    try self.output.writer(self.allocator).print("    _cached_{s}: ?[]{s} = null,\n", .{ escaped_name, model_name });
                } else {
                    // For singular relations, cache the model instance
                    try self.output.writer(self.allocator).print("    _cached_{s}: {s}{s} = null,\n", .{ escaped_name, optional_marker, relation_type });
                }
            }
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
            if (isFieldRelation(field, self.schema) or field.optional or field.getDefaultValue() != null) {
                continue;
            }
            // Skip primary keys with autoincrement (they're database-generated)
            if (field.isPrimaryKey() and field.getDefaultValue() != null) {
                continue;
            }
            if (!first) try self.output.appendSlice(self.allocator, ", ");
            first = false;
            const escaped_name = try escapeFieldName(self.allocator, field.name);
            defer if (needsEscape(field.name)) self.allocator.free(escaped_name);
            try self.output.writer(self.allocator).print("{s}: {s}", .{ escaped_name, field.type.toZigType() });
        }

        try self.output.writer(self.allocator).print(") {s} {{\n", .{model.name});
        try self.output.writer(self.allocator).print("        return {s}{{\n", .{model.name});

        // Initialize all fields
        for (model.fields.items) |*field| {
            const escaped_name = try escapeFieldName(self.allocator, field.name);
            defer if (needsEscape(field.name)) self.allocator.free(escaped_name);

            if (isFieldRelation(field, self.schema)) {
                // Skip relationship fields - they'll be loaded separately
                continue;
            } else if (!field.optional and field.getDefaultValue() == null) {
                try self.output.writer(self.allocator).print("            .{s} = {s},\n", .{ escaped_name, escaped_name });
            } else if (field.getDefaultValue()) |default_val| {
                // Handle different default value types - skip autoincrement and dbgenerated as they're undefined
                if (std.mem.eql(u8, default_val, "autoincrement()")) {
                    try self.output.writer(self.allocator).print("            .{s} = undefined,\n", .{escaped_name});
                } else if (std.mem.startsWith(u8, default_val, "dbgenerated(")) {
                    // Database-generated values should be undefined in client-side init
                    try self.output.writer(self.allocator).print("            .{s} = undefined,\n", .{escaped_name});
                } else if (std.mem.eql(u8, default_val, "now()")) {
                    try self.output.writer(self.allocator).print("            .{s} = std.time.timestamp(),\n", .{escaped_name});
                } else if (field.type == .string) {
                    try self.output.writer(self.allocator).print("            .{s} = \"{s}\",\n", .{ escaped_name, default_val });
                } else if (field.type == .model_ref) {
                    // Check if it's an enum type - if so, qualify with enum name
                    const type_name = field.type.model_ref;
                    if (self.schema.getEnum(type_name)) |_| {
                        try self.output.writer(self.allocator).print("            .{s} = {s}.{s},\n", .{ escaped_name, type_name, default_val });
                    } else {
                        // It's a relation - shouldn't have a default
                        try self.output.writer(self.allocator).print("            .{s} = {s},\n", .{ escaped_name, default_val });
                    }
                } else {
                    try self.output.writer(self.allocator).print("            .{s} = {s},\n", .{ escaped_name, default_val });
                }
            } else {
                try self.output.writer(self.allocator).print("            .{s} = null,\n", .{escaped_name});
            }
        }

        try self.output.appendSlice(self.allocator, "        };\n    }\n");

        // Generate toSql method for CREATE operations
        try self.generateToSqlMethod(model);
        
        // Generate cache management methods
        try self.generateCacheManagementMethods(model);
        
        // Generate relation loader methods
        try self.generateRelationLoaderMethods(model);
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
                    .float => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"{{d}}\", .{{self.{s}}});\n", .{field.name}),
                    .boolean => try output.writer(self.allocator).print("            try values.appendSlice(allocator, if (self.{s}) \"true\" else \"false\");\n", .{field.name}),
                    .datetime => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"to_timestamp({{d}})\", .{{self.{s}}});\n", .{field.name}),
                    .decimal => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"{{d}}\", .{{self.{s}}});\n", .{field.name}),
                    .json => try output.writer(self.allocator).print("            try values.writer(allocator).print(\"'{{s}}'::jsonb\", .{{self.{s}}});\n", .{field.name}),
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
                .float => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"{d}\", .{val});\n"),
                .boolean => try output.appendSlice(self.allocator, "                try values.appendSlice(allocator, if (val) \"true\" else \"false\");\n"),
                .datetime => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"to_timestamp({d})\", .{val});\n"),
                .decimal => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"{d}\", .{val});\n"),
                .json => try output.appendSlice(self.allocator, "                try values.writer(allocator).print(\"'{s}'::jsonb\", .{val});\n"),
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

    /// Generate cache management methods (setAllocator, clearCache)
    fn generateCacheManagementMethods(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        var output = &self.output;
        
        // Generate setAllocator method
        try output.appendSlice(self.allocator, "\n    /// Set allocator for cached relation loading\n");
        try output.appendSlice(self.allocator, "    pub fn setAllocator(self: *@This(), allocator: std.mem.Allocator) void {\n");
        try output.appendSlice(self.allocator, "        self._allocator = allocator;\n");
        try output.appendSlice(self.allocator, "    }\n");
        
        // Generate clearCache method
        try output.appendSlice(self.allocator, "\n    /// Clear all cached relations\n");
        try output.appendSlice(self.allocator, "    pub fn clearCache(self: *@This()) void {\n");
        try output.appendSlice(self.allocator, "        if (self._allocator) |alloc| {\n");

        var arr_count: u32 = 0;
        
        // Free each cached relation
        for (model.fields.items) |*field| {
            if (isFieldRelation(field, self.schema)) {
                const escaped_name = try escapeFieldName(self.allocator, field.name);
                defer if (needsEscape(field.name)) self.allocator.free(escaped_name);
                
                if (field.type.isArray()) {
                    // Free array slice
                    try output.writer(self.allocator).print("            if (self._cached_{s}) |cached| {{\n", .{escaped_name});
                    try output.appendSlice(self.allocator, "                alloc.free(cached);\n");
                    try output.writer(self.allocator).print("                self._cached_{s} = null;\n", .{escaped_name});
                    try output.appendSlice(self.allocator, "            }\n");
                    arr_count += 1;
                } else {
                    // For singular relations, just set to null (they're values, not pointers)
                    try output.writer(self.allocator).print("            self._cached_{s} = null;\n", .{escaped_name});
                }
            }
        }

        if (arr_count == 0) try output.appendSlice(self.allocator, "        _ = alloc;\n");
        
        try output.appendSlice(self.allocator, "        }\n");
        try output.appendSlice(self.allocator, "    }\n");
    }

    /// Generate relation loader methods
    fn generateRelationLoaderMethods(self: *Generator, model: *const PrismaModel) CodeGenError!void {
        for (model.fields.items) |*field| {
            if (isFieldRelation(field, self.schema)) {
                if (field.type.isArray()) {
                    try self.generateArrayRelationLoader(model, field);
                } else {
                    try self.generateSingularRelationLoader(model, field);
                }
            }
        }
    }

    /// Generate loader for singular relations (e.g., loadRestaurant)
    fn generateSingularRelationLoader(self: *Generator, model: *const PrismaModel, field: *const Field) CodeGenError!void {
        _ = model; // will be used for finding foreign key fields
        var output = &self.output;
        const relation_model_name = field.type.getModelName().?;
        const escaped_field_name = try escapeFieldName(self.allocator, field.name);
        defer if (needsEscape(field.name)) self.allocator.free(escaped_field_name);
        
        // Get the foreign key field name from @relation attribute
        const relation_attr = field.getRelationAttribute();
        if (relation_attr == null) {
            // No @relation attribute, skip this relation
            return;
        }
        
        const fields_array = relation_attr.?.fields orelse return;
        if (fields_array.len == 0) return;
        const fk_field_name = fields_array[0].value;
        
        // Generate non-cached loader
        try output.writer(self.allocator).print("\n    /// Load {s} relation (non-cached)\n", .{field.name});
        
        const capitalized_name = try self.capitalizeFirst(field.name);
        defer self.allocator.free(capitalized_name);
        
        try output.writer(self.allocator).print("    pub fn load{s}(self: *const @This(), client: *PrismaClient, allocator: std.mem.Allocator) !?{s} {{\n", .{
            capitalized_name,
            relation_model_name,
        });
        
        // Check if foreign key is null
        try output.writer(self.allocator).print("        if (self.{s}) |fk| {{\n", .{fk_field_name});
        try output.writer(self.allocator).print("            return try {s}.findUnique(client, allocator, fk, .{{}});\n", .{relation_model_name});
        try output.appendSlice(self.allocator, "        }\n");
        try output.appendSlice(self.allocator, "        return null;\n");
        try output.appendSlice(self.allocator, "    }\n");
        
        // Generate cached loader
        try output.writer(self.allocator).print("\n    /// Load {s} relation (cached)\n", .{field.name});
        try output.writer(self.allocator).print("    pub fn load{s}Cached(self: *@This(), client: *PrismaClient) !?{s} {{\n", .{
            capitalized_name,
            relation_model_name,
        });
        
        // Check if already cached
        try output.writer(self.allocator).print("        if (self._cached_{s}) |cached| {{\n", .{escaped_field_name});
        try output.appendSlice(self.allocator, "            return cached;\n");
        try output.appendSlice(self.allocator, "        }\n");
        
        // Check if allocator is set
        try output.appendSlice(self.allocator, "        const alloc = self._allocator orelse return error.AllocatorNotSet;\n");
        
        // Load and cache
        try output.writer(self.allocator).print("        const result = try self.load{s}(client, alloc);\n", .{capitalized_name});
        try output.writer(self.allocator).print("        self._cached_{s} = result;\n", .{escaped_field_name});
        try output.appendSlice(self.allocator, "        return result;\n");
        try output.appendSlice(self.allocator, "    }\n");
    }

    /// Generate loader for array relations (e.g., loadUserRoles)
    fn generateArrayRelationLoader(self: *Generator, model: *const PrismaModel, field: *const Field) CodeGenError!void {
        _ = model; // will be used for reverse foreign key lookup
        var output = &self.output;
        const relation_model_name = field.type.getModelName().?;
        const escaped_field_name = try escapeFieldName(self.allocator, field.name);
        defer if (needsEscape(field.name)) self.allocator.free(escaped_field_name);
        
        // For array relations, we need to find the reverse foreign key
        // This will be implemented in step 10 (inverse relation metadata)
        // For now, generate a placeholder
        
        const capitalized_name = try self.capitalizeFirst(field.name);
        defer self.allocator.free(capitalized_name);
        
        try output.writer(self.allocator).print("\n    /// Load {s} relation (non-cached)\n", .{field.name});
        try output.writer(self.allocator).print("    pub fn load{s}(self: *const @This(), client: *PrismaClient, allocator: std.mem.Allocator) ![] {s} {{\n", .{
            capitalized_name,
            relation_model_name,
        });
        try output.appendSlice(self.allocator, "        // TODO: Implement array relation loading with reverse foreign key\n");
        try output.appendSlice(self.allocator, "        _ = client;\n");
        try output.appendSlice(self.allocator, "        _ = allocator;\n");
        try output.appendSlice(self.allocator, "        _ = self;\n");
        try output.appendSlice(self.allocator, "        return error.NotImplemented;\n");
        try output.appendSlice(self.allocator, "    }\n");
        
        // Generate cached loader
        try output.writer(self.allocator).print("\n    /// Load {s} relation (cached)\n", .{field.name});
        try output.writer(self.allocator).print("    pub fn load{s}Cached(self: *@This(), client: *PrismaClient) ![] {s} {{\n", .{
            capitalized_name,
            relation_model_name,
        });
        
        // Check if already cached
        try output.writer(self.allocator).print("        if (self._cached_{s}) |cached| {{\n", .{escaped_field_name});
        try output.appendSlice(self.allocator, "            return cached;\n");
        try output.appendSlice(self.allocator, "        }\n");
        
        // Check if allocator is set
        try output.appendSlice(self.allocator, "        const alloc = self._allocator orelse return error.AllocatorNotSet;\n");
        
        // Load and cache
        try output.writer(self.allocator).print("        const result = try self.load{s}(client, alloc);\n", .{capitalized_name});
        try output.writer(self.allocator).print("        self._cached_{s} = result;\n", .{escaped_field_name});
        try output.appendSlice(self.allocator, "        return result;\n");
        try output.appendSlice(self.allocator, "    }\n");
    }

    /// Helper to capitalize first letter of a string
    fn capitalizeFirst(self: *Generator, name: []const u8) ![]const u8 {
        if (name.len == 0) return name;
        var result = try self.allocator.alloc(u8, name.len);
        result[0] = std.ascii.toUpper(name[0]);
        @memcpy(result[1..], name[1..]);
        return result;
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

        try output.appendSlice(self.allocator, "/// Float filter options\n");
        try output.appendSlice(self.allocator, "pub const FloatFilter = struct {\n");
        try output.appendSlice(self.allocator, "    equals: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    lt: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    lte: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    gt: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    gte: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "};\n\n");

        try output.appendSlice(self.allocator, "/// Decimal filter options\n");
        try output.appendSlice(self.allocator, "pub const DecimalFilter = struct {\n");
        try output.appendSlice(self.allocator, "    equals: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    lt: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    lte: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    gt: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "    gte: ?f64 = null,\n");
        try output.appendSlice(self.allocator, "};\n\n");
    }

    /// Generate Include types for each model for eager loading
    fn generateIncludeTypes(self: *Generator) CodeGenError!void {
        var output = &self.output;
        
        // Generate Include type for each model
        for (self.schema.models.items) |*model| {
            // Count relations
            var has_relations = false;
            for (model.fields.items) |*field| {
                if (isFieldRelation(field, self.schema)) {
                    has_relations = true;
                    break;
                }
            }
            
            if (!has_relations) continue;
            
            try output.writer(self.allocator).print("/// Include options for {s} model\n", .{model.name});
            try output.writer(self.allocator).print("pub const {s}Include = struct {{\n", .{model.name});
            
            // Add a field for each relation
            for (model.fields.items) |*field| {
                if (isFieldRelation(field, self.schema)) {
                    const escaped_name = try escapeFieldName(self.allocator, field.name);
                    defer if (needsEscape(field.name)) self.allocator.free(escaped_name);
                    
                    const relation_model_name = field.type.getModelName().?;
                    
                    // Add bool flag for the relation
                    try output.writer(self.allocator).print("    {s}: bool = false,\n", .{escaped_name});
                    
                    // Add nested include option for singular relations
                    if (!field.type.isArray()) {
                        try output.writer(self.allocator).print("    {s}_include: ?{s}Include = null,\n", .{
                            escaped_name,
                            relation_model_name,
                        });
                    } else {
                        // For array relations, also support nested includes
                        try output.writer(self.allocator).print("    {s}_include: ?{s}Include = null,\n", .{
                            escaped_name,
                            relation_model_name,
                        });
                    }
                }
            }
            
            try output.appendSlice(self.allocator, "};\n\n");
        }
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
                .float => "FloatFilter",
                .boolean => "BooleanFilter",
                .datetime => "DateTimeFilter",
                .decimal => "DecimalFilter",
                .json => "StringFilter", // JSON fields use string filters
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

        // Build INSERT query - columns array with unquoted names for toSqlValues
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

        // Build quoted column list at compile time - no heap allocation needed
        try output.writer(self.allocator).print("        const quoted_cols = [_][]const u8{{", .{});
        first = true;
        for (model.fields.items) |*field| {
            if (field.isPrimaryKey() and field.getDefaultValue() != null) continue;
            if (field.type.isRelation()) continue; // Skip relationship fields
            if (!first) try output.appendSlice(self.allocator, ", ");
            first = false;
            try output.writer(self.allocator).print("\"\\\"{s}\\\"\"", .{field.getColumnName()});
        }
        try output.appendSlice(self.allocator, "};\n");
        try output.appendSlice(self.allocator, "        const columns_joined = try std.mem.join(self.allocator, \", \", &quoted_cols);\n");
        try output.appendSlice(self.allocator, "        defer self.allocator.free(columns_joined);\n");

        try output.writer(self.allocator).print("        const query = try std.fmt.allocPrint(self.allocator, \n", .{});
        try output.writer(self.allocator).print("            \"INSERT INTO \\\"{s}\\\" ({{s}}) VALUES ({{s}}) RETURNING *;\",\n", .{table_name.value});
        try output.appendSlice(self.allocator, "            .{ columns_joined, values }\n");
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
                    .string, .json => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            record.{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                // Non-optional field handling
                switch (field.type) {
                    .string, .json => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            record.{s} = try dt.unixTimeFromISO8601(try row.get(\"\\\"{s}\\\"\", []const u8));\n", .{ field.name, column_name });
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
                    .string, .json => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.getOpt(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.getOpt(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            records[idx].{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                // Non-optional field handling
                switch (field.type) {
                    .string, .json => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.get(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.get(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try row.get(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            records[idx].{s} = try dt.unixTimeFromISO8601( try row.get(\"\\\"{s}\\\"\", []const u8) );\n", .{ field.name, column_name });
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
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.writer(self.allocator).print("                const val_str = try std.fmt.allocPrint(self.allocator, \"{{d}}\", .{{value}});\n", .{});
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(if (value) \"true\" else \"false\");\n");
                },
                .datetime => {
                    try output.writer(self.allocator).print("                const val_str = try std.fmt.allocPrint(self.allocator, \"to_timestamp({{d}})\", .{{value}});\n", .{});
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .float, .decimal => {
                    try output.writer(self.allocator).print("                const val_str = try std.fmt.allocPrint(self.allocator, \"{{d}}\", .{{value}});\n", .{});
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
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
                    .string, .json => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            record.{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                switch (field.type) {
                    .string, .json => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            record.{s} = try dt.unixTimeFromISO8601(try row.get(\"\\\"{s}\\\"\", []const u8));\n", .{ field.name, column_name });
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
        try output.writer(self.allocator).print("    pub fn update(self: *@This(), options: struct {{ where: {s}Where, data: {s}UpdateData }}) !?{s} {{\n", .{ model.name, model.name, model.name });

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
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"\\\"{s}\\\" = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.appendSlice(self.allocator, "            const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "            defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.appendSlice(self.allocator, "            const bool_str = if (value) \"TRUE\" else \"FALSE\";\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(bool_str);\n");
                },
                .datetime => {
                    try output.appendSlice(self.allocator, "            const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "            defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"\\\"{s}\\\" = to_timestamp(\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(val_str);\n");
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(\")\");\n");
                },
                .float, .decimal => {
                    try output.appendSlice(self.allocator, "            const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "            defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("            _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "            _ = try query_builder.sql(val_str);\n");
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
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.appendSlice(self.allocator, "                const bool_str = if (value) \"TRUE\" else \"FALSE\";\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(bool_str);\n");
                },
                .datetime => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = to_timestamp(\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\")\");\n");
                },
                .float, .decimal => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                else => {},
            }

            try output.appendSlice(self.allocator, "            }\n");
            try output.appendSlice(self.allocator, "        }\n");
            _ = filter_prefix;
        }

        try output.appendSlice(self.allocator, "\n        _ = try query_builder.sql(\" RETURNING *\");\n");
        try output.appendSlice(self.allocator, "        const query = query_builder.build();\n");
        try output.appendSlice(self.allocator, "        var result = try self.connection.execSafe(query);\n");
        try output.appendSlice(self.allocator, "        \n");
        try output.appendSlice(self.allocator, "        if (result.rowCount() == 0) {\n");
        try output.appendSlice(self.allocator, "            return null;\n");
        try output.appendSlice(self.allocator, "        }\n");
        try output.appendSlice(self.allocator, "        \n");
        try output.appendSlice(self.allocator, "        if (result.next()) |row| {\n");
        try output.appendSlice(self.allocator, "            var record: ");
        try output.writer(self.allocator).print("{s} = undefined;\n", .{model.name});

        // Generate field parsing for the returned record (same as CREATE operation)
        for (model.fields.items) |*field| {
            if (field.type.isRelation()) continue;

            const column_name = field.getColumnName();

            if (field.optional) {
                // Optional field handling
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.getOpt(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            const {s}_str = try row.getOpt(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                        try output.writer(self.allocator).print("            record.{s} = if ({s}_str) |str| try dt.unixTimeFromISO8601(str) else null;\n", .{ field.name, field.name });
                    },
                    else => {},
                }
            } else {
                // Non-optional field handling
                switch (field.type) {
                    .string => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", []const u8);\n", .{ field.name, column_name });
                    },
                    .int => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", i32);\n", .{ field.name, column_name });
                    },
                    .boolean => {
                        try output.writer(self.allocator).print("            record.{s} = try row.get(\"\\\"{s}\\\"\", bool);\n", .{ field.name, column_name });
                    },
                    .datetime => {
                        try output.writer(self.allocator).print("            record.{s} = try dt.unixTimeFromISO8601(try row.get(\"\\\"{s}\\\"\", []const u8));\n", .{ field.name, column_name });
                    },
                    else => {},
                }
            }
        }

        try output.appendSlice(self.allocator, "            return record;\n");
        try output.appendSlice(self.allocator, "        }\n");
        try output.appendSlice(self.allocator, "        \n");
        try output.appendSlice(self.allocator, "        return null;\n");
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
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = '\");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(value);\n");
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(\"'\");\n");
                },
                .int => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .boolean => {
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(if (value) \"true\" else \"false\");\n");
                },
                .datetime => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"to_timestamp({d})\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
                    try output.appendSlice(self.allocator, "                _ = try query_builder.sql(val_str);\n");
                },
                .float, .decimal => {
                    try output.appendSlice(self.allocator, "                const val_str = try std.fmt.allocPrint(self.allocator, \"{d}\", .{value});\n");
                    try output.appendSlice(self.allocator, "                defer self.allocator.free(val_str);\n");
                    try output.writer(self.allocator).print("                _ = try query_builder.sql(\"\\\"{s}\\\" = \");\n", .{column_name});
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

test "column name casing in toSqlValues" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "TestModel");

    // Add fields with various casing patterns
    var id_field = try Field.init(allocator, "id", .int);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const camel_case_field = try Field.init(allocator, "firstName", .string);
    try model.addField(camel_case_field);

    const another_camel_field = try Field.init(allocator, "createdAt", .datetime);
    try model.addField(another_camel_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify toSqlValues uses unquoted column names for comparison
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "hasColumn(columns, \"firstName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "hasColumn(columns, \"createdAt\")") != null);

    // Verify the columns array is created with unquoted names
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "const columns = [_][]const u8{\"id\", \"firstName\", \"createdAt\"}") != null);
}

test "column name quoting in INSERT statement" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Restaurant");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    // This field name needs case-sensitive quoting in PostgreSQL
    const owner_id_field = try Field.init(allocator, "ownerId", .string);
    try model.addField(owner_id_field);

    const is_active_field = try Field.init(allocator, "isActive", .boolean);
    try model.addField(is_active_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify quoted columns are generated at compile time (no runtime heap allocation)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "const quoted_cols = [_][]const u8{") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "\\\"id\\\"") != null);

    // Verify INSERT uses quoted table name (with escaped quotes in generated code)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "INSERT INTO \\\"restaurant\\\"") != null);
}

test "toSqlValues with mixed case columns" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Order");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const customer_id_field = try Field.init(allocator, "customerId", .string);
    try model.addField(customer_id_field);

    const total_amount_field = try Field.init(allocator, "totalAmount", .float);
    try model.addField(total_amount_field);

    const payment_method_field = try Field.init(allocator, "paymentMethod", .string);
    try model.addField(payment_method_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify each camelCase field is checked with unquoted name in toSqlValues
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "hasColumn(columns, \"customerId\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "hasColumn(columns, \"totalAmount\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "hasColumn(columns, \"paymentMethod\")") != null);

    // Verify unquoted names are in the columns array
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "\"customerId\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "\"totalAmount\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "\"paymentMethod\"") != null);
}

test "column array does not contain pre-quoted names" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Product");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const product_name_field = try Field.init(allocator, "productName", .string);
    try model.addField(product_name_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Ensure the columns array does NOT contain pre-quoted names like "\"productName\""
    // This would break toSqlValues comparison
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "const columns = [_][]const u8{\"\\\"id\\\"\", \"\\\"productName\\\"\"}") == null);

    // Instead it should have unquoted names
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "const columns = [_][]const u8{\"id\", \"productName\"}") != null);
}

test "row.get uses quoted column names" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Employee");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const first_name_field = try Field.init(allocator, "firstName", .string);
    try model.addField(first_name_field);

    const restaurant_id_field = try Field.init(allocator, "restaurantId", .string);
    try model.addField(restaurant_id_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify row.get() calls use quoted column names for PostgreSQL case-sensitivity
    // The generated code should contain patterns like: row.get("\"firstName\"", []const u8)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "row.get(\"\\\"id\\\"\", []const u8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "row.get(\"\\\"firstName\\\"\", []const u8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "row.get(\"\\\"restaurantId\\\"\", []const u8)") != null);
}

test "row.getOpt uses quoted column names" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Customer");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    var email_field = try Field.init(allocator, "email", .string);
    email_field.optional = true;
    try model.addField(email_field);

    var phone_number_field = try Field.init(allocator, "phoneNumber", .string);
    phone_number_field.optional = true;
    try model.addField(phone_number_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify row.getOpt() calls use quoted column names for optional fields
    // The generated code should contain patterns like: row.getOpt("\"email\"", []const u8)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "row.getOpt(\"\\\"email\\\"\", []const u8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "row.getOpt(\"\\\"phoneNumber\\\"\", []const u8)") != null);
}

test "compile-time quoted_cols array optimization" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Account");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const account_number_field = try Field.init(allocator, "accountNumber", .string);
    try model.addField(account_number_field);

    const balance_field = try Field.init(allocator, "balance", .float);
    try model.addField(balance_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify compile-time const array (no heap allocation for quoting)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "const quoted_cols = [_][]const u8{") != null);

    // Should NOT have runtime heap allocation for quoted_cols
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "var quoted_cols = try allocator.alloc") == null);

    // Should NOT have runtime loop to quote columns
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "for (columns, 0..) |col, i|") == null);

    // Verify pre-quoted column names in the const array
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "\\\"accountNumber\\\"") != null);
}

test "findMany uses quoted column names in row.get" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Department");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const dept_name_field = try Field.init(allocator, "deptName", .string);
    try model.addField(dept_name_field);

    const manager_id_field = try Field.init(allocator, "managerId", .string);
    try model.addField(manager_id_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify findMany function exists
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "pub fn findMany") != null);

    // Verify it uses quoted column names when populating records array
    // The generated code should contain patterns like: records[idx].deptName = try row.get("\"deptName\"", ...)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "records[idx].deptName = try row.get(\"\\\"deptName\\\"\",") != null or
        std.mem.indexOf(u8, generated_code, "records[idx].managerId = try row.get(\"\\\"managerId\\\"\",") != null);
}

test "findUnique uses quoted column names in row.get" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Position");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const title_field = try Field.init(allocator, "title", .string);
    try model.addField(title_field);

    const salary_range_field = try Field.init(allocator, "salaryRange", .string);
    try model.addField(salary_range_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify findUnique function exists
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "pub fn findUnique") != null);

    // Verify it uses quoted column names when retrieving single record
    // The generated code should contain patterns like: record.salaryRange = try row.get("\"salaryRange\"", ...)
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "record.salaryRange = try row.get(\"\\\"salaryRange\\\"\",") != null or
        std.mem.indexOf(u8, generated_code, "record.title = try row.get(\"\\\"title\\\"\",") != null);
}

test "update returns ResultSet" {
    const allocator = std.testing.allocator;

    var schema = Schema.init(allocator);
    defer schema.deinit();

    var model = try PrismaModel.init(allocator, "Product");

    var id_field = try Field.init(allocator, "id", .string);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const name_field = try Field.init(allocator, "name", .string);
    try model.addField(name_field);

    const price_field = try Field.init(allocator, "price", .float);
    try model.addField(price_field);

    try schema.addModel(model);

    var generator = Generator.init(allocator, &schema);
    defer generator.deinit();
    const generated_code = try generator.generateClient();
    defer allocator.free(generated_code);

    // Verify update function exists with optional model return type
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "pub fn update") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "!?Product {") != null);

    // Verify it uses RETURNING * clause
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "RETURNING *") != null);

    // Verify it parses and returns the result
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "return record;") != null);
}
