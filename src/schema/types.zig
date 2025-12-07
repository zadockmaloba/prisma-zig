const std = @import("std");

pub const String = struct {
    value: []const u8,
    heap_allocated: bool = false,
    allocator: ?std.mem.Allocator = null,
};

/// Represents a Prisma field type
pub const FieldType = union(enum) {
    // Primitive types
    string,
    int,
    boolean,
    datetime,

    // Model references
    model_ref: []const u8, // e.g., "User"
    model_array: []const u8, // e.g., "Post[]"

    /// Parse a field type from a string
    pub fn fromString(type_str: []const u8) ?FieldType {
        // Check for primitive types first
        if (std.mem.eql(u8, type_str, "String")) return .string;
        if (std.mem.eql(u8, type_str, "Int")) return .int;
        if (std.mem.eql(u8, type_str, "Boolean")) return .boolean;
        if (std.mem.eql(u8, type_str, "DateTime")) return .datetime;

        // Check for array type (ends with [])
        if (std.mem.endsWith(u8, type_str, "[]")) {
            const model_name = type_str[0 .. type_str.len - 2];
            return FieldType{ .model_array = model_name };
        }

        // Check if it's a valid model reference (starts with uppercase)
        if (type_str.len > 0 and std.ascii.isUpper(type_str[0])) {
            return FieldType{ .model_ref = type_str };
        }

        return null;
    }

    /// Convert field type to PostgreSQL column type
    pub fn toSqlType(self: FieldType) []const u8 {
        return switch (self) {
            .string => "TEXT",
            .int => "INTEGER",
            .boolean => "BOOLEAN",
            .datetime => "TIMESTAMP",
            .model_ref => "INTEGER", // Foreign key as integer
            .model_array => "", // Arrays don't have direct SQL representation (handled via relations)
        };
    }

    /// Convert field type to Zig type string for code generation
    pub fn toZigType(self: FieldType) []const u8 {
        return switch (self) {
            .string => "[]const u8",
            .int => "i32",
            .boolean => "bool",
            .datetime => "i64", // Unix timestamp
            .model_ref => |model_name| model_name, // Use the model name as type
            .model_array => |model_name| model_name, // Will be handled specially in codegen
        };
    }

    /// Check if this field type represents a relationship
    pub fn isRelation(self: FieldType) bool {
        return switch (self) {
            .model_ref, .model_array => true,
            else => false,
        };
    }

    /// Check if this field type represents an array/list relationship
    pub fn isArray(self: FieldType) bool {
        return switch (self) {
            .model_array => true,
            else => false,
        };
    }

    /// Get the referenced model name for relationship fields
    pub fn getModelName(self: FieldType) ?[]const u8 {
        return switch (self) {
            .model_ref => |name| name,
            .model_array => |name| name,
            else => null,
        };
    }
};

/// Represents a @relation attribute with fields and references
pub const RelationAttribute = struct {
    name: ?String = null, // Optional relation name
    fields: ?[]String = null, // [authorId, categoryId]
    references: ?[]String = null, // [id, id]

    pub fn init() RelationAttribute {
        return RelationAttribute{};
    }
};

/// Represents field attributes like @id, @unique, @default, @relation
pub const FieldAttribute = union(enum) {
    id,
    unique,
    default: String,
    map: String, // @map("column_name")
    relation: RelationAttribute, // @relation(fields: [authorId], references: [id])
    db_type: String, // @db.Uuid, @db.VarChar(255), @db.Timestamptz(6), etc.

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

    pub fn initRelation(allocator: std.mem.Allocator, relation: RelationAttribute) !FieldAttribute {
        _ = allocator;
        return .{
            .relation = relation,
        };
    }

    pub fn initDbType(allocator: std.mem.Allocator, db_type: String) !FieldAttribute {
        _ = allocator;
        return .{
            .db_type = db_type,
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
            .db_type => {
                if (self.db_type.heap_allocated) self.db_type.allocator.?.free(self.db_type.value);
            },
            .relation => |rel| {
                // Free relation fields if they were allocated
                if (rel.fields) |fields| {
                    for (fields) |field| {
                        if (field.heap_allocated) field.allocator.?.free(field.value);
                    }
                    // Note: We'd need to store the allocator in RelationAttribute to free the array itself
                }
                if (rel.references) |references| {
                    for (references) |ref| {
                        if (ref.heap_allocated) ref.allocator.?.free(ref.value);
                    }
                }
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
                return FieldAttribute{ .default = .{ .value = value[1 .. value.len - 1] } };
            }
            return FieldAttribute{ .default = .{ .value = value } };
        }
        if (std.mem.startsWith(u8, attr_str, "@map(")) {
            const start = std.mem.indexOf(u8, attr_str, "(").? + 1;
            const end = std.mem.lastIndexOf(u8, attr_str, ")").?;
            const value = attr_str[start..end];
            // Remove quotes
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                return FieldAttribute{ .map = .{ .value = value[1 .. value.len - 1] } };
            }
            return FieldAttribute{ .map = .{ .value = value } };
        }
        if (std.mem.startsWith(u8, attr_str, "@relation(")) {
            // For now, return a basic relation attribute
            // Full parsing of fields and references would be more complex
            return FieldAttribute{ .relation = RelationAttribute.init() };
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

    /// Check if this field represents a relationship
    pub fn isRelation(self: *const Field) bool {
        return self.type.isRelation() or self.hasAttribute(.relation);
    }

    /// Check if this field represents an array relationship (one-to-many)
    pub fn isArrayRelation(self: *const Field) bool {
        return self.type.isArray();
    }

    /// Get the related model name for relationship fields
    pub fn getRelatedModel(self: *const Field) ?[]const u8 {
        return self.type.getModelName();
    }

    /// Get the relation attribute if present
    pub fn getRelationAttribute(self: *const Field) ?RelationAttribute {
        if (self.getAttribute(.relation)) |rel_attr| {
            return rel_attr.relation;
        }
        return null;
    }

    /// Get the database-specific type if present (e.g., "Uuid", "VarChar(255)", "Timestamptz(6)")
    pub fn getDbType(self: *const Field) ?[]const u8 {
        if (self.getAttribute(.db_type)) |db_attr| {
            return db_attr.db_type.value;
        }
        return null;
    }

    /// Get SQL type considering both the field type and database-specific attributes
    pub fn getSqlType(self: *const Field, db_provider: []const u8) []const u8 {
        // Check for database-specific type hints
        if (self.getDbType()) |db_type| {
            // For PostgreSQL, use native types
            if (std.mem.eql(u8, db_provider, "postgresql")) {
                // Handle UUID type
                if (std.mem.eql(u8, db_type, "Uuid")) return "UUID";

                // Handle VARCHAR with size parameter
                if (std.mem.startsWith(u8, db_type, "VarChar")) {
                    // Extract size if present: VarChar(255) -> VARCHAR(255)
                    if (std.mem.indexOf(u8, db_type, "(")) |_| {
                        return db_type; // Return full "VarChar(255)" - will be uppercased in SQL
                    }
                    return "VARCHAR";
                }

                // Handle TIMESTAMPTZ with precision
                if (std.mem.startsWith(u8, db_type, "Timestamptz")) {
                    if (std.mem.indexOf(u8, db_type, "(")) |_| {
                        return db_type; // Return full "Timestamptz(6)"
                    }
                    return "TIMESTAMPTZ";
                }

                // Handle other common PostgreSQL types
                if (std.mem.eql(u8, db_type, "Text")) return "TEXT";
                if (std.mem.eql(u8, db_type, "Serial")) return "SERIAL";
                if (std.mem.eql(u8, db_type, "BigSerial")) return "BIGSERIAL";
            }
        }

        // Fall back to standard SQL types based on Prisma type
        return self.type.toSqlType();
    }
};

/// Represents a Prisma model
pub const PrismaModel = struct {
    name: []const u8,
    fields: std.ArrayList(Field),
    indexes: std.ArrayList(String),
    table_name: ?[]const u8, // From @@map attribute
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !PrismaModel {
        return PrismaModel{
            .name = name,
            .allocator = allocator,
            .fields = .empty,
            .indexes = .empty,
            .table_name = null,
        };
    }

    pub fn deinit(self: *PrismaModel) void {
        // Free the model name (allocated by allocator.dupe)
        //self.allocator.free(self.name);

        for (self.fields.items) |*field| {
            field.deinit();
        }

        // free model-level indexes
        for (self.indexes.items) |idx| {
            if (idx.heap_allocated) idx.allocator.?.free(idx.value);
        }
        self.indexes.deinit(self.allocator);

        self.fields.deinit(self.allocator);
    }

    /// Add a field to the model
    pub fn addField(self: *PrismaModel, field: Field) !void {
        try self.fields.append(self.allocator, field);
    }

    /// Add a model-level index raw attribute string (content inside parentheses)
    pub fn addIndex(self: *PrismaModel, idx: String) !void {
        try self.indexes.append(self.allocator, idx);
    }

    /// Get the database table name (using @@map if present, otherwise lowercase model name)
    pub fn getTableName(self: *const PrismaModel, allocator: std.mem.Allocator) !String {
        if (self.table_name) |table_name| {
            return .{ .value = table_name };
        }
        // Convert to lowercase
        const lowercase = try allocator.alloc(u8, self.name.len);
        for (self.name, 0..) |c, i| {
            lowercase[i] = std.ascii.toLower(c);
        }
        return .{ .value = lowercase, .heap_allocated = true, .allocator = allocator };
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
    provider_heap_allocated: bool = false,
    url_heap_allocated: bool = false,

    pub fn init(allocator: std.mem.Allocator, provider: []const u8, url: []const u8) !DatasourceConfig {
        return .{
            .allocator = allocator,
            .provider = provider, //try allocator.dupe(u8, provider),
            .url = url, //try allocator.dupe(u8, url),
        };
    }

    pub fn deinit(self: *DatasourceConfig) void {
        if (self.provider_heap_allocated) {
            self.allocator.free(self.provider);
        }
        if (self.url_heap_allocated) {
            self.allocator.free(self.url);
        }
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
    SkipAttribute,
};

// Tests
test "FieldType.fromString" {
    try std.testing.expect(FieldType.fromString("String").? == .string);
    try std.testing.expect(FieldType.fromString("Int").? == .int);
    try std.testing.expect(FieldType.fromString("Boolean").? == .boolean);
    try std.testing.expect(FieldType.fromString("DateTime").? == .datetime);
    try std.testing.expect(FieldType.fromString("Unknown") == null);

    // Test model references
    const user_ref = FieldType.fromString("User").?;
    try std.testing.expect(std.meta.activeTag(user_ref) == .model_ref);
    try std.testing.expectEqualStrings("User", user_ref.model_ref);

    // Test array types
    const post_array = FieldType.fromString("Post[]").?;
    try std.testing.expect(std.meta.activeTag(post_array) == .model_array);
    try std.testing.expectEqualStrings("Post", post_array.model_array);
}

test "FieldType.toSqlType" {
    try std.testing.expectEqualStrings("TEXT", FieldType.toSqlType(.string));
    try std.testing.expectEqualStrings("INTEGER", FieldType.toSqlType(.int));
    try std.testing.expectEqualStrings("BOOLEAN", FieldType.toSqlType(.boolean));
    try std.testing.expectEqualStrings("TIMESTAMP", FieldType.toSqlType(.datetime));

    const user_ref = FieldType{ .model_ref = "User" };
    try std.testing.expectEqualStrings("INTEGER", user_ref.toSqlType());
}

test "FieldType.toZigType" {
    try std.testing.expectEqualStrings("[]const u8", FieldType.toZigType(.string));
    try std.testing.expectEqualStrings("i32", FieldType.toZigType(.int));
    try std.testing.expectEqualStrings("bool", FieldType.toZigType(.boolean));
    try std.testing.expectEqualStrings("i64", FieldType.toZigType(.datetime));

    const user_ref = FieldType{ .model_ref = "User" };
    try std.testing.expectEqualStrings("User", user_ref.toZigType());
}

test "FieldType relationship methods" {
    const user_ref = FieldType{ .model_ref = "User" };
    const post_array = FieldType{ .model_array = "Post" };
    const string_type = FieldType.string;

    try std.testing.expect(user_ref.isRelation());
    try std.testing.expect(post_array.isRelation());
    try std.testing.expect(!FieldType.isRelation(string_type));

    try std.testing.expect(!user_ref.isArray());
    try std.testing.expect(post_array.isArray());
    try std.testing.expect(!FieldType.isArray(string_type));

    try std.testing.expectEqualStrings("User", user_ref.getModelName().?);
    try std.testing.expectEqualStrings("Post", post_array.getModelName().?);
    try std.testing.expect(FieldType.getModelName(string_type) == null);
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
