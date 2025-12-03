# Prisma Zig API Reference

Complete API documentation for Prisma Zig generated clients.

## Table of Contents

- [Client Initialization](#client-initialization)
- [Model Operations](#model-operations)
- [Filtering](#filtering)
- [Type System](#type-system)
- [Error Handling](#error-handling)

## Client Initialization

### Connection

```zig
const prisma = @import("prisma_client.zig");

var conn = prisma.Connection.init(allocator);
defer conn.deinit();

try conn.connect("postgresql://user:pass@host:5432/db");
```

#### Connection Methods

**`Connection.init(allocator: std.mem.Allocator) Connection`**

Initialize a new database connection.

**`connect(connString: []const u8) !void`**

Connect to the database using a PostgreSQL connection string.

**`deinit() void`**

Clean up and close the connection.

### PrismaClient

```zig
var client = prisma.PrismaClient.init(allocator, &conn);
```

#### PrismaClient Structure

```zig
pub const PrismaClient = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    
    // Model operations (generated for each model)
    user: UserOperations,
    post: PostOperations,
    profile: ProfileOperations,
    // ... more models
};
```

## Model Operations

Each model in your schema gets a set of CRUD operations.

### create

Create a new record and return it with all database-generated values.

**Signature:**
```zig
pub fn create(self: *@This(), data: ModelType) !ModelType
```

**Example:**
```zig
const user = try client.user.create(.init(
    1,
    "alice@example.com",
));
std.debug.print("Created user with ID: {}\n", .{user.id});
```

**Returns:** The created record with all fields populated, including database defaults.

**Errors:** `error.QueryFailed` if the insert fails.

### findMany

Find multiple records matching optional filter criteria.

**Signature:**
```zig
pub fn findMany(
    self: *@This(),
    options: struct { where: ?ModelWhere = null }
) ![]ModelType
```

**Example:**
```zig
// Find all records
const all_users = try client.user.findMany(.{});
defer allocator.free(all_users);

// Find with filters
const active_users = try client.user.findMany(.{
    .where = .{ 
        .email = .{ .contains = "@company.com" },
    },
});
defer allocator.free(active_users);
```

**Returns:** An owned slice of records. **Must be freed** by the caller.

**Errors:** `error.QueryFailed`, `error.OutOfMemory`

### findUnique

Find a single record by unique field(s).

**Signature:**
```zig
pub fn findUnique(
    self: *@This(),
    options: struct { where: ModelWhere }
) !?ModelType
```

**Example:**
```zig
const user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = 1 } },
});

if (user) |u| {
    std.debug.print("Found: {s}\n", .{u.email});
} else {
    std.debug.print("Not found\n", .{});
}
```

**Returns:** Optional model instance. `null` if not found.

**Errors:** `error.QueryFailed`

### update

Update a record and return the updated data.

**Signature:**
```zig
pub fn update(
    self: *@This(),
    options: struct { where: ModelWhere, data: ModelType }
) !ModelType
```

**Example:**
```zig
const updated = try client.user.update(.{
    .where = .{ .id = .{ .equals = 1 } },
    .data = .{
        .id = 1,
        .email = "alice@example.com",
        .name = "Alice Updated",
        .createdAt = original_timestamp,
        .updatedAt = std.time.timestamp(),
    },
});
```

**Returns:** The updated record data (currently returns the input data).

**Errors:** `error.QueryFailed`

**Note:** Non-primary-key fields in `data` are used for the UPDATE.

### delete

Delete record(s) matching the where clause.

**Signature:**
```zig
pub fn delete(
    self: *@This(),
    options: struct { where: ModelWhere }
) !void
```

**Example:**
```zig
try client.user.delete(.{
    .where = .{ .id = .{ .equals = 1 } },
});
```

**Returns:** `void`

**Errors:** `error.QueryFailed`

## Filtering

### ModelWhere Types

Each model gets a generated `Where` type for filtering.

**Example Structure:**
```zig
pub const UserWhere = struct {
    id: ?IntFilter = null,
    email: ?StringFilter = null,
    name: ?StringFilter = null,
    createdAt: ?DateTimeFilter = null,
    updatedAt: ?DateTimeFilter = null,
};
```

### Filter Types

#### StringFilter

```zig
pub const StringFilter = struct {
    equals: ?[]const u8 = null,
    contains: ?[]const u8 = null,
    startsWith: ?[]const u8 = null,
    endsWith: ?[]const u8 = null,
};
```

**Usage:**
```zig
.email = .{ .equals = "exact@match.com" }
.email = .{ .contains = "substring" }
.email = .{ .startsWith = "prefix" }
.email = .{ .endsWith = "@domain.com" }
```

#### IntFilter

```zig
pub const IntFilter = struct {
    equals: ?i32 = null,
    lt: ?i32 = null,      // Less than
    lte: ?i32 = null,     // Less than or equal
    gt: ?i32 = null,      // Greater than
    gte: ?i32 = null,     // Greater than or equal
};
```

**Usage:**
```zig
.id = .{ .equals = 42 }
.age = .{ .gt = 18 }
.age = .{ .lte = 65 }
```

#### BooleanFilter

```zig
pub const BooleanFilter = struct {
    equals: ?bool = null,
};
```

**Usage:**
```zig
.published = .{ .equals = true }
.active = .{ .equals = false }
```

#### DateTimeFilter

```zig
pub const DateTimeFilter = struct {
    equals: ?i64 = null,
    lt: ?i64 = null,
    lte: ?i64 = null,
    gt: ?i64 = null,
    gte: ?i64 = null,
};
```

**Usage:**
```zig
const now = std.time.timestamp();
const week_ago = now - (7 * 24 * 60 * 60);

.createdAt = .{ .gt = week_ago }
.updatedAt = .{ .lte = now }
```

### Combining Filters

Multiple filters in a where clause are combined with AND:

```zig
const results = try client.user.findMany(.{
    .where = .{
        .email = .{ .contains = "@company.com" },
        .name = .{ .startsWith = "A" },
    },
});
// Generates: WHERE email LIKE '%@company.com%' AND name LIKE 'A%'
```

## Type System

### Model Structs

Each Prisma model generates a Zig struct:

```zig
pub const User = struct {
    id: i32,
    email: []const u8,
    name: ?[]const u8,
    createdAt: i64,
    updatedAt: i64,
    
    pub fn init(id: i32, email: []const u8) User { ... }
    pub fn toSqlValues(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 { ... }
};
```

### Type Mappings

| Prisma Type | Zig Type | PostgreSQL Type |
|------------|----------|-----------------|
| `Int` | `i32` | `INTEGER` |
| `String` | `[]const u8` | `TEXT` |
| `Boolean` | `bool` | `BOOLEAN` |
| `DateTime` | `i64` | `TIMESTAMP` |

### Optional Fields

Fields marked with `?` in the schema become optional in Zig:

```prisma
model User {
  name String?
}
```

```zig
pub const User = struct {
    name: ?[]const u8,
};
```

### Relations

Relations are defined in the schema but not yet included in the generated struct:

```prisma
model User {
  posts Post[]
}
```

Currently, relations must be queried separately.

## Error Handling

### Error Set

Common errors you may encounter:

```zig
error {
    QueryFailed,
    OutOfMemory,
    ConnectionFailed,
    NoSuchColumn,
    InvalidCharacter,
}
```

### Error Handling Pattern

```zig
const user = client.user.create(.init(1, "test@example.com")) catch |err| {
    switch (err) {
        error.QueryFailed => {
            std.debug.print("Database query failed\n", .{});
            return err;
        },
        error.OutOfMemory => {
            std.debug.print("Out of memory\n", .{});
            return err;
        },
        else => return err,
    }
};
```

### Query Debugging

To see the generated SQL queries, you can examine the QueryBuilder output:

```zig
var query_builder = QueryBuilder.init(allocator);
defer query_builder.deinit();
_ = try query_builder.sql("SELECT * FROM users WHERE id = ");
_ = try query_builder.sql("1");
const query = query_builder.build();
std.debug.print("SQL: {s}\n", .{query});
```

## Memory Management

### Allocator Pattern

All operations require an allocator:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var client = prisma.PrismaClient.init(allocator, &conn);
```

### Cleanup Requirements

**Always free `findMany` results:**
```zig
const users = try client.user.findMany(.{});
defer allocator.free(users);
```

**Single records from `findUnique` don't need freeing** (they're stack-allocated).

**Connection cleanup:**
```zig
var conn = prisma.Connection.init(allocator);
defer conn.deinit();
```

## Advanced Usage

### Raw SQL (QueryBuilder)

For complex queries not covered by the generated API:

```zig
var query_builder = QueryBuilder.init(allocator);
defer query_builder.deinit();

_ = try query_builder.sql("SELECT * FROM users WHERE ");
_ = try query_builder.sql("email LIKE '%@company.com%' ");
_ = try query_builder.sql("AND created_at > NOW() - INTERVAL '7 days'");

const query = query_builder.build();
var result = try conn.execSafe(query);

// Parse results manually
while (result.next()) |row| {
    const email = try row.get("email", []const u8);
    std.debug.print("Email: {s}\n", .{email});
}
```

### Custom Initialization

Models provide an `init` function for required fields:

```zig
const user = User.init(1, "alice@example.com");
// Optional fields are set to null, defaults are computed
```

You can also construct directly:

```zig
const user = User{
    .id = 1,
    .email = "alice@example.com",
    .name = "Alice",
    .createdAt = std.time.timestamp(),
    .updatedAt = std.time.timestamp(),
};
```

## Best Practices

1. **Always use `defer` for cleanup**
   ```zig
   const users = try client.user.findMany(.{});
   defer allocator.free(users);
   ```

2. **Check for null on `findUnique`**
   ```zig
   const user = try client.user.findUnique(.{...});
   if (user) |u| {
       // Use u
   }
   ```

3. **Use specific filters**
   ```zig
   // Good: specific filter
   .id = .{ .equals = 1 }
   
   // Avoid: too broad
   .email = .{ .contains = "" }
   ```

4. **Handle errors explicitly**
   ```zig
   const user = try client.user.create(...);
   // Don't ignore potential errors
   ```

5. **Reuse connections**
   ```zig
   // Initialize once
   var conn = prisma.Connection.init(allocator);
   defer conn.deinit();
   
   // Use for multiple operations
   var client = prisma.PrismaClient.init(allocator, &conn);
   ```
