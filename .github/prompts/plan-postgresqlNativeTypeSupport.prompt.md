# Implementation Plan: PostgreSQL Native Type Support

## Overview
Add support for PostgreSQL native types (UUID, VARCHAR, TIMESTAMPTZ, etc.) by storing and using `@db.*` attributes instead of treating all String fields as TEXT.

## Step 1: Update `FieldAttribute` in `src/schema/types.zig`

Add the `db_type` variant after the `relation` line (~line 107):

```zig
pub const FieldAttribute = union(enum) {
    id,
    unique,
    default: String,
    map: String, // @map("column_name")
    relation: RelationAttribute, // @relation(fields: [authorId], references: [id])
    db_type: String, // @db.Uuid, @db.VarChar(255), @db.Timestamptz(6), etc.
```

## Step 2: Add `initDbType` helper method in `src/schema/types.zig`

After `initRelation` (~line 125):

```zig
    pub fn initDbType(allocator: std.mem.Allocator, db_type: String) !FieldAttribute {
        _ = allocator;
        return .{
            .db_type = db_type,
        };
    }
```

## Step 3: Update `deinit` in `src/schema/types.zig`

Add db_type case after the default case (~line 135):

```zig
            .default => {
                if (self.default.heap_allocated) self.default.allocator.?.free(self.default.value);
            },
            .db_type => {
                if (self.db_type.heap_allocated) self.db_type.allocator.?.free(self.db_type.value);
            },
            .relation => |rel| {
```

## Step 4: Add helper methods to `Field` struct in `src/schema/types.zig`

After `getRelationAttribute` (~line 278):

```zig
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
```

## Step 5: Update parser in `src/schema/parser.zig`

Replace the `@db.*` handling (~line 417-434) from:

```zig
        // Handle @db.* attributes (skip them for now as they're database-specific)
        if (std.mem.eql(u8, attr_name, "db")) {
            if (self.match(.dot)) {
                _ = try self.consume(.identifier, "Expected db attribute name");
                // Skip parameters if present
                if (self.match(.left_paren)) {
                    var paren_depth: i32 = 1;
                    while (!self.isAtEnd() and paren_depth > 0) {
                        const token = self.current_token;
                        self.advance();
                        if (token.type == .left_paren) {
                            paren_depth += 1;
                        } else if (token.type == .right_paren) {
                            paren_depth -= 1;
                        }
                    }
                }
            }
            // Return a placeholder - these are database-specific hints
            return error.SkipAttribute;
        }
```

To:

```zig
        // Handle @db.* attributes (store them as db_type)
        if (std.mem.eql(u8, attr_name, "db")) {
            if (self.match(.dot)) {
                const db_type_token = try self.consume(.identifier, "Expected db attribute name");
                var db_type_str = db_type_token.lexeme;
                
                // Check for parameters like VarChar(255) or Timestamptz(6)
                if (self.match(.left_paren)) {
                    var type_with_params = std.ArrayList(u8).init(self.allocator);
                    defer type_with_params.deinit();
                    
                    try type_with_params.appendSlice(db_type_str);
                    try type_with_params.append('(');
                    
                    // Collect everything inside parentheses
                    var paren_depth: i32 = 1;
                    while (!self.isAtEnd() and paren_depth > 0) {
                        const token = self.current_token;
                        if (token.type == .left_paren) {
                            paren_depth += 1;
                            try type_with_params.append('(');
                        } else if (token.type == .right_paren) {
                            paren_depth -= 1;
                            if (paren_depth > 0) {
                                try type_with_params.append(')');
                            }
                        } else if (token.type == .number_literal) {
                            try type_with_params.appendSlice(token.lexeme);
                        } else if (token.type == .comma) {
                            try type_with_params.append(',');
                        }
                        self.advance();
                    }
                    
                    try type_with_params.append(')');
                    
                    const full_type = try self.allocator.dupe(u8, type_with_params.items);
                    return FieldAttribute.initDbType(self.allocator, .{ 
                        .value = full_type, 
                        .heap_allocated = true, 
                        .allocator = self.allocator 
                    });
                } else {
                    // No parameters, just the type name
                    return FieldAttribute.initDbType(self.allocator, .{ .value = db_type_str });
                }
            }
            return error.SkipAttribute;
        }
```

## Step 6: Update `generateMigrationSql` in `src/dbutil.zig`

Change the SQL type generation (~line 42) from:

```zig
                const sql_type = field.type.toSqlType();
```

To:

```zig
                const db_provider = if (schema.datasource) |ds| ds.provider else "postgresql";
                const sql_type = field.getSqlType(db_provider);
```

Do the same for the non-primary-key fields section (~line 59).

## Step 7: Update `generatePushSql` in `src/dbutil.zig`

Similarly update (~line 144) from:

```zig
                const sql_type = field.type.toSqlType();
```

To:

```zig
                const db_provider = if (schema.datasource) |ds| ds.provider else "postgresql";
                const sql_type = field.getSqlType(db_provider);
```

## Step 8: Fix SQL generation to uppercase PostgreSQL types

In both `generateMigrationSql` and `generatePushSql`, after getting the sql_type, add uppercase conversion for types with parameters:

```zig
                const db_provider = if (schema.datasource) |ds| ds.provider else "postgresql";
                var sql_type_buf: [64]u8 = undefined;
                const sql_type_raw = field.getSqlType(db_provider);
                
                // Convert to uppercase for PostgreSQL types
                const sql_type = blk: {
                    if (std.mem.indexOf(u8, sql_type_raw, "(")) |_| {
                        // Has parameters, need to uppercase the type part
                        var i: usize = 0;
                        for (sql_type_raw) |c| {
                            sql_type_buf[i] = std.ascii.toUpper(c);
                            i += 1;
                            if (i >= sql_type_buf.len) break;
                        }
                        break :blk sql_type_buf[0..sql_type_raw.len];
                    }
                    break :blk sql_type_raw;
                };
```

## Testing

After making these changes, rebuild and test:

```fish
cd /Users/zadock/Git-Repos/naisys/prisma-zig
zig build
./zig-out/bin/prisma_zig generate
```

Test with a schema like:

```prisma
model User {
  id        String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  email     String   @unique @db.VarChar(255)
  name      String?
  createdAt DateTime @default(now()) @db.Timestamptz(6)
}
```

Expected SQL output:
- `id UUID` instead of `id TEXT`
- `email VARCHAR(255)` instead of `email TEXT`
- `createdAt TIMESTAMPTZ(6)` instead of `createdAt TIMESTAMP`

## Further Considerations

1. **Validation**: Should we validate that `@db.*` attributes match the database provider? For example, warn if using `@db.Uuid` with a MySQL datasource.

2. **Size Parameters**: Currently storing full signature like "VarChar(255)". This works but could be enhanced to parse and validate parameter ranges.

3. **SERIAL Types**: Currently using `@default(autoincrement())` but PostgreSQL-specific `@db.Serial` could be clearer. Should we handle both?

4. **Other Database Providers**: This implementation focuses on PostgreSQL. Future work should extend to MySQL, SQLite, SQL Server, etc.

5. **Type Mapping Table**: Consider creating a comprehensive mapping table for all Prisma native types across different databases.
