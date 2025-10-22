const std = @import("std");

pub const String = struct {
    value: []const u8,
    heap_allocated: bool = false,
    allocator: ?std.mem.Allocator = null,
};

/// Represents a Prisma field type
pub const FieldType = enum {
    string,
    int,
    boolean,
    datetime,

    /// Parse a field type from a string
    pub fn fromString(type_str: []const u8) ?FieldType {
        if (std.mem.eql(u8, type_str, "String")) return .string;
        if (std.mem.eql(u8, type_str, "Int")) return .int;
        if (std.mem.eql(u8, type_str, "Boolean")) return .boolean;
        if (std.mem.eql(u8, type_str, "DateTime")) return .datetime;
        return null;
    }

    /// Convert field type to PostgreSQL column type
    pub fn toSqlType(self: FieldType) []const u8 {
        return switch (self) {
            .string => "TEXT",
            .int => "INTEGER",
            .boolean => "BOOLEAN",
            .datetime => "TIMESTAMP",
        };
    }

    /// Convert field type to Zig type string for code generation
    pub fn toZigType(self: FieldType) []const u8 {
        return switch (self) {
            .string => "[]const u8",
            .int => "i32",
            .boolean => "bool",
            .datetime => "i64", // Unix timestamp
        };
    }
};

/// Represents field attributes like @id, @unique, @default
pub const FieldAttribute = union(enum) {
    id,
    unique,
    default: String,
    map: String, // @map("column_name") 
    
    pub fn initDefault(allocator: std.mem.Allocator, val: String) !FieldAttribute {
        _ = allocator;
        return .{
            .default = val,
        };
    }
    
    pub fn initMap(allocator: std.mem.Allocator, map_name: String) !FieldAttribute {
        _ = allocator;
        return .{
            .map = map_name,
        };
    }

    pub fn deinit(self: FieldAttribute, allocator: std.mem.Allocator) void {
        _ = allocator;
        switch (self) {
            .map => {
                if (self.map.heap_allocated) self.map.allocator.?.free(self.map.value);
            },
            .default => {
                if (self.default.heap_allocated) self.default.allocator.?.free(self.default.value);
            },
            else => {},
        }
    }

    pub fn fromString(attr_str: []const u8) ?FieldAttribute {
        if (std.mem.eql(u8, attr_str, "@id")) return .id;
        if (std.mem.eql(u8, attr_str, "@unique")) return .unique;
        if (std.mem.startsWith(u8, attr_str, "@default(")) {
            // Extract default value from @default("value") or @default(value)
            const start = std.mem.indexOf(u8, attr_str, "(").? + 1;
            const end = std.mem.lastIndexOf(u8, attr_str, ")").?;
            const value = attr_str[start..end];
            // Remove quotes if present
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                return FieldAttribute{ .default = .{.value = value[1 .. value.len - 1]}};
            }
            return FieldAttribute{ .default = .{.value = value} };
        }
        if (std.mem.startsWith(u8, attr_str, "@map(")) {
            const start = std.mem.indexOf(u8, attr_str, "(").? + 1;
            const end = std.mem.lastIndexOf(u8, attr_str, ")").?;
            const value = attr_str[start..end];
            // Remove quotes
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                return FieldAttribute{ .map = .{.value = value[1 .. value.len - 1] }};
            }
            return FieldAttribute{ .map = .{.value = value } };
        }
        return null;
    }
};

/// Represents a field in a Prisma model
pub const Field = struct {
    name: []const u8,
    type: FieldType,
    optional: bool,
    attributes: std.ArrayList(FieldAttribute),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, field_type: FieldType) !Field {
        return Field{
            .name = name,
            .type = field_type,
            .optional = false,
            .allocator = allocator,
            .attributes = .empty,
        };
    }

    pub fn deinit(self: *Field) void {
        // Free the field name (allocated by allocator.dupe)
        for (self.attributes.items) |attribute| {
            attribute.deinit(self.allocator);
        }

        self.attributes.deinit(self.allocator);
    }

    /// Check if field has a specific attribute
    pub fn hasAttribute(self: *const Field, attr_type: std.meta.Tag(FieldAttribute)) bool {
        for (self.attributes.items) |attr| {
            if (std.meta.activeTag(attr) == attr_type) return true;
        }
        return false;
    }

    /// Get attribute value if it exists
    pub fn getAttribute(self: *const Field, attr_type: std.meta.Tag(FieldAttribute)) ?FieldAttribute {
        for (self.attributes.items) |attr| {
            if (std.meta.activeTag(attr) == attr_type) return attr;
        }
        return null;
    }

    /// Get the database column name (using @map if present, otherwise field name)
    pub fn getColumnName(self: *const Field) []const u8 {
        if (self.getAttribute(.map)) |map_attr| {
            return map_attr.map.value;
        }
        return self.name;
    }

    /// Check if this field is the primary key
    pub fn isPrimaryKey(self: *const Field) bool {
        return self.hasAttribute(.id);
    }

    /// Check if this field is unique
    pub fn isUnique(self: *const Field) bool {
        return self.hasAttribute(.unique) or self.hasAttribute(.id);
    }

    /// Get default value if present
    pub fn getDefaultValue(self: *const Field) ?[]const u8 {
        if (self.getAttribute(.default)) |default_attr| {
            return default_attr.default.value;
        }
        return null;
    }
};

/// Represents a Prisma model
pub const PrismaModel = struct {
    name: []const u8,
    fields: std.ArrayList(Field),
    table_name: ?[]const u8, // From @@map attribute
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !PrismaModel {
        return PrismaModel{
            .name = name,
            .allocator = allocator,
            .fields = .empty,
            .table_name = null,
        };
    }

    pub fn deinit(self: *PrismaModel) void {
        // Free the model name (allocated by allocator.dupe)
        //self.allocator.free(self.name);

        for (self.fields.items) |*field| {
            field.deinit();
        }

        self.fields.deinit(self.allocator);
    }

    /// Add a field to the model
    pub fn addField(self: *PrismaModel, field: Field) !void {
        try self.fields.append(self.allocator, field);
    }

    /// Get the database table name (using @@map if present, otherwise lowercase model name)
    pub fn getTableName(self: *const PrismaModel, allocator: std.mem.Allocator) ![]const u8 {
        if (self.table_name) |table_name| {
            return table_name;
        }
        // Convert to lowercase
        const lowercase = try allocator.alloc(u8, self.name.len);
        for (self.name, 0..) |c, i| {
            lowercase[i] = std.ascii.toLower(c);
        }
        return lowercase;
    }

    /// Find a field by name
    pub fn getField(self: *const PrismaModel, field_name: []const u8) ?*const Field {
        for (self.fields.items) |*field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                return field;
            }
        }
        return null;
    }

    /// Get the primary key field
    pub fn getPrimaryKey(self: *const PrismaModel) ?*const Field {
        for (self.fields.items) |*field| {
            if (field.isPrimaryKey()) {
                return field;
            }
        }
        return null;
    }

    // Get all unique fields
    // pub fn getUniqueFields(self: *const PrismaModel, allocator: std.mem.Allocator) !std.ArrayList(*const Field) {
    //     var unique_fields = std.ArrayList(*const Field).initCapacity(allocator, 20) catch .empty;
    //     for (self.fields.items) |*field| {
    //         if (field.isUnique()) {
    //             try unique_fields.append(self.allocator, field);
    //         }
    //     }
    //     return unique_fields;
    // }
};

/// Represents the entire Prisma schema
pub const Schema = struct {
    allocator: std.mem.Allocator,
    models: std.ArrayList(PrismaModel),
    generator: ?GeneratorConfig,
    datasource: ?DatasourceConfig,

    pub fn init(allocator: std.mem.Allocator) Schema {
        return Schema{
            .allocator = allocator,
            .models = .empty,
            .generator = null,
            .datasource = null,
        };
    }

    pub fn deinit(self: *Schema) void {
        // Free generator config if present
        if (self.generator) |*gen| {
            gen.deinit();
        }

        // Free datasource config if present
        if (self.datasource) |*ds| {
            ds.deinit();
        }

        // Free all models
        for (self.models.items) |*model| {
            model.deinit();
        }
        self.models.deinit(self.allocator);
    }

    /// Add a model to the schema
    pub fn addModel(self: *Schema, model: PrismaModel) !void {
        try self.models.append(self.allocator, model);
    }

    /// Find a model by name
    pub fn getModel(self: *const Schema, model_name: []const u8) ?*const PrismaModel {
        for (self.models.items) |*model| {
            if (std.mem.eql(u8, model.name, model_name)) {
                return model;
            }
        }
        return null;
    }
};

/// Generator configuration block
pub const GeneratorConfig = struct {
    provider: []const u8,
    output: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, provider: []const u8, output: []const u8) !GeneratorConfig {
        return .{
            .allocator = allocator,
            .provider = provider, //try allocator.dupe(u8, provider),
            .output = output, //try allocator.dupe(u8, output),
        };
    }

    pub fn deinit(self: *GeneratorConfig) void {
        _ = self;
        //self.allocator.free(self.provider);
        //self.allocator.free(self.output);
    }
};

/// Datasource configuration block
pub const DatasourceConfig = struct {
    provider: []const u8,
    url: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, provider: []const u8, url: []const u8) !DatasourceConfig {
        return .{
            .allocator = allocator,
            .provider = provider, //try allocator.dupe(u8, provider),
            .url = url, //try allocator.dupe(u8, url),
        };
    }

    pub fn deinit(self: *DatasourceConfig) void {
        _ = self;
        //self.allocator.free(self.provider);
        //self.allocator.free(self.url);
    }
};

/// Parse errors that can occur during schema parsing
pub const ParseError = error{
    InvalidSyntax,
    UnknownFieldType,
    UnknownAttribute,
    MissingRequiredField,
    DuplicateModel,
    DuplicateField,
    InvalidDefaultValue,
    OutOfMemory,
};

// Tests
test "FieldType.fromString" {
    try std.testing.expect(FieldType.fromString("String") == .string);
    try std.testing.expect(FieldType.fromString("Int") == .int);
    try std.testing.expect(FieldType.fromString("Boolean") == .boolean);
    try std.testing.expect(FieldType.fromString("DateTime") == .datetime);
    try std.testing.expect(FieldType.fromString("Unknown") == null);
}

test "FieldType.toSqlType" {
    try std.testing.expectEqualStrings("TEXT", FieldType.string.toSqlType());
    try std.testing.expectEqualStrings("INTEGER", FieldType.int.toSqlType());
    try std.testing.expectEqualStrings("BOOLEAN", FieldType.boolean.toSqlType());
    try std.testing.expectEqualStrings("TIMESTAMP", FieldType.datetime.toSqlType());
}

test "FieldType.toZigType" {
    try std.testing.expectEqualStrings("[]const u8", FieldType.string.toZigType());
    try std.testing.expectEqualStrings("i32", FieldType.int.toZigType());
    try std.testing.expectEqualStrings("bool", FieldType.boolean.toZigType());
    try std.testing.expectEqualStrings("i64", FieldType.datetime.toZigType());
}

test "FieldAttribute.fromString" {
    try std.testing.expect(std.meta.activeTag(FieldAttribute.fromString("@id").?) == .id);
    try std.testing.expect(std.meta.activeTag(FieldAttribute.fromString("@unique").?) == .unique);

    const default_attr = FieldAttribute.fromString("@default(\"test\")").?;
    try std.testing.expect(std.meta.activeTag(default_attr) == .default);
    try std.testing.expectEqualStrings("test", default_attr.default.value);

    const map_attr = FieldAttribute.fromString("@map(\"user_id\")").?;
    try std.testing.expect(std.meta.activeTag(map_attr) == .map);
    try std.testing.expectEqualStrings("user_id", map_attr.map.value);
}

test "Field basic operations" {
    const allocator = std.testing.allocator;

    var field = try Field.init(allocator, "name", .string);
    defer field.deinit();

    try field.attributes.append(allocator, .unique);
    try field.attributes.append(allocator, FieldAttribute{ .default = .{ .value = "test" } });

    try std.testing.expect(field.hasAttribute(.unique));
    try std.testing.expect(field.hasAttribute(.default));
    try std.testing.expect(!field.hasAttribute(.id));

    try std.testing.expect(field.isUnique());
    try std.testing.expect(!field.isPrimaryKey());

    const default_val = field.getDefaultValue().?;
    try std.testing.expectEqualStrings("test", default_val);
}

test "PrismaModel basic operations" {
    const allocator = std.testing.allocator;

    var model = try PrismaModel.init(allocator, "User");
    defer model.deinit();

    var id_field = try Field.init(allocator, "id", .int);
    try id_field.attributes.append(allocator, .id);
    try model.addField(id_field);

    const name_field = try Field.init(allocator, "name", .string);
    try model.addField(name_field);

    try std.testing.expect(model.fields.items.len == 2);

    const found_field = model.getField("name");
    try std.testing.expect(found_field != null);
    try std.testing.expectEqualStrings("name", found_field.?.name);

    const pk_field = model.getPrimaryKey();
    try std.testing.expect(pk_field != null);
    try std.testing.expectEqualStrings("id", pk_field.?.name);
}
