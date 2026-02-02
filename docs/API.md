# Prisma Zig API Reference

Complete API documentation for Prisma Zig generated clients.

## Table of Contents

- [Client Initialization](#client-initialization)
- [Model Operations](#model-operations)
- [Relations](#relations)
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

## Relations

Prisma Zig provides multiple ways to work with related data through foreign keys and relation loader methods.

### Foreign Key Fields

Foreign key fields are included in model structs and can be used for manual queries:

**Schema:**
```prisma
model User {
  id           String      @id @default(uuid())
  restaurantId String?
  restaurant   Restaurant? @relation(fields: [restaurantId], references: [id])
}
```

**Generated Struct:**
```zig
pub const User = struct {
    id: []const u8,
    restaurantId: ?[]const u8,  // Foreign key included
    // restaurant field excluded (relation)
};
```

**Manual Query Pattern:**
```zig
const user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = user_id } },
});

if (user) |u| {
    if (u.restaurantId) |restaurant_id| {
        const restaurant = try client.restaurant.findUnique(.{
            .where = .{ .id = .{ .equals = restaurant_id } },
        });
    }
}
```

### Relation Loader Methods

Each relation generates convenient loader methods for lazy loading.

#### Singular Relations (One-to-One, Many-to-One)

**Non-Cached Loader:**
```zig
pub fn loadRestaurant(
    self: *const @This(),
    client: *PrismaClient,
    allocator: std.mem.Allocator
) !?Restaurant
```

**Example:**
```zig
const user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = user_id } },
});

if (user) |u| {
    // Load restaurant using foreign key
    const restaurant = try u.loadRestaurant(&client, allocator);
    
    if (restaurant) |r| {
        std.debug.print("Restaurant: {s}\n", .{r.name});
    } else {
        std.debug.print("No restaurant assigned\n", .{});
    }
}
```

**Behavior:**
- Returns `null` immediately if foreign key is `null`
- Executes query if foreign key has a value
- Caller owns returned memory (use provided allocator)
- Does not cache results

**Cached Loader:**
```zig
pub fn loadRestaurantCached(
    self: *@This(),
    client: *PrismaClient
) !?Restaurant
```

**Example:**
```zig
var user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = user_id } },
});

if (user) |*u| {
    // Set allocator for caching
    u.setAllocator(allocator);
    
    // First call queries database
    const restaurant1 = try u.loadRestaurantCached(&client);
    
    // Subsequent calls return cached result
    const restaurant2 = try u.loadRestaurantCached(&client);
    
    // restaurant1 and restaurant2 point to same cached data
}
```

**Behavior:**
- Checks cache first, returns if present
- Requires allocator to be set via `setAllocator()`
- Returns `error.AllocatorNotSet` if allocator not configured
- Caches result for subsequent calls
- Uses struct's internal allocator

#### Array Relations (One-to-Many)

**Non-Cached Loader:**
```zig
pub fn loadUserRoles(
    self: *const @This(),
    client: *PrismaClient,
    allocator: std.mem.Allocator
) ![]UserRole
```

**Cached Loader:**
```zig
pub fn loadUserRolesCached(
    self: *@This(),
    client: *PrismaClient
) ![]UserRole
```

**Current Status:** Array relation loaders detect the reverse foreign key (e.g., `userId` in `UserRole` table) but currently return `error.NotImplemented` pending WHERE clause support in `findMany`. The infrastructure is in place, with inverse relation metadata stored during schema parsing.

**Detected Foreign Keys:**
```zig
const user = try client.user.findUnique(.{...});
if (user) |u| {
    // Generator knows this should query: 
    // SELECT * FROM user_roles WHERE userId = u.id
    const roles = try u.loadUserRoles(&client, allocator);
    // Returns error.NotImplemented for now
}
```

**When Fully Implemented:**
- Will automatically query related records using detected foreign key
- Non-cached version returns caller-owned slice
- Cached version stores result in `_cached_userRoles` field
- Memory management follows same pattern as singular relations

### Cache Management

Models with relations include built-in caching support.
 and Cached Fields

Relations are not included directly in structs, but each model with relations includes:

```zig
pub const User = struct {
    // Scalar fields
    id: []const u8,
    restaurantId: ?[]const u8,
    
    // Cache management fields (internal use)
    _allocator: ?std.mem.Allocator = null,
    _cached_restaurant: ?Restaurant = null,
    _cached_userRoles: ?[]UserRole = null,
    
    // Relation loader methods (see Relations section)
    pub fn loadRestaurant(...) !?Restaurant { ... }
    pub fn loadRestaurantCached(...) !?Restaurant { ... }
    pub fn loadUserRoles(...) ![]UserRole { ... }
    pub fn loadUserRolesCached(...) ![]UserRole { ... }
};
```

See the [Relations](#relations) section for complete documentation
```

#### Clearing the Cache

Clear all cached relations:

```zig
user.clearCache();
```

**When to clear cache:**
- After updating related records
- When you need fresh data
- To free memory from cached relations

**What gets cleared:**
- All cached singular relations (set to `null`)
- All cached array relations (freed and set to `null`)

#### Cache Lifetime

```zig
var user = try client.user.findUnique(.{...});
if (user) |*u| {
    u.setAllocator(arena_allocator);
    
    // Load and cache multiple relations
    _ = try u.loadRestaurantCached(&client);
    _ = try u.loadProfileCached(&client);
    
    // All cached data freed when arena is freed
}
defer arena_allocator.deinit();
```

### Eager Loading with Include Options

Each model with relations has a generated Include type for eager loading relations in a single query using JOINs.

#### Include Types

```zig
pub const UserInclude = struct {
    restaurant: bool = false,
    userRoles: bool = false,
};

pub const RestaurantInclude = struct {
    country: bool = false,
    owner: bool = false,
    users: bool = false,
};
```

#### Basic Include Usage

**Load singular relation:**
```zig
const user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = user_id } },
    .include = .{ .restaurant = true },
});

if (user) |u| {
    // Restaurant is automatically loaded and cached
    if (u._cached_restaurant) |restaurant| {
        std.debug.print("User works at: {s}\n", .{restaurant.name});
    }
}
```

**Load multiple relations:**
```zig
const user = try client.user.findMany(.{
    .where = null,
    .include = .{
        .restaurant = true,
        .profile = true,
        .userRoles = true,
    },
});

for (user) |u| {
    if (u._cached_restaurant) |restaurant| {
        std.debug.print("{s} at {s}\n", .{u.email, restaurant.name});
    }
    
    if (u._cached_userRoles) |roles| {
        for (roles) |role| {
            std.debug.print("  - {s}\n", .{role.name});
        }
    }
}
```

#### SQL Implementation Details

**Singular Relations (LEFT JOIN):**
When you include a singular relation, the generator produces a `LEFT JOIN` query:

```sql
SELECT 
    "users".*, 
    restaurant_restaurants."id" AS restaurant_id,
    restaurant_restaurants."name" AS restaurant_name,
    restaurant_restaurants."countryId" AS restaurant_countryId
    -- ... more aliased columns
FROM "users"
LEFT JOIN "restaurants" AS restaurant_restaurants 
    ON "users"."restaurantId" = restaurant_restaurants."id"
WHERE "users"."id" = $1
```

- Columns are prefixed to avoid conflicts (`restaurant_id`, `restaurant_name`)
- `LEFT JOIN` handles nullable relations gracefully
- Related model is parsed from aliased columns and stored in cache

**Array Relations (json_agg subquery):**
When you include an array relation, a JSON aggregation subquery is used:

```sql
SELECT 
    "restaurants".*, 
    (SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) 
     FROM "users" t 
     WHERE t."restaurantId" = "restaurants"."id") AS users_json
FROM "restaurants"
WHERE "restaurants"."id" = $1
```

- Uses PostgreSQL's `json_agg()` to aggregate related rows
- `COALESCE` ensures empty array for no matches
- Keeps result as single row (avoids cartesian product)
- JSON is parsed and cached as `[]User` slice

#### Performance Characteristics

**Benefits:**
- Single database round-trip for complex queries
- Reduced network latency vs N+1 queries
- Automatic caching of loaded relations
- Type-safe at compile time

**Considerations:**
- JOINs can be expensive for large result sets
- Array relation JSON parsing adds overhead
- Deep nesting increases query complexity
- Consider pagination for large datasets

**Best Practices:**
```zig
// Good: Load only what you need
const users = try client.user.findMany(.{
    .include = .{ .restaurant = true },
});

// Avoid: Loading too many relations
const users = try client.user.findMany(.{
    .include = .{
        .restaurant = true,
        .profile = true,
        .userRoles = true,
        .permissions = true,
        // ... too many relations
    },
});

// Better: Multiple targeted queries
const users = try client.user.findMany(.{
    .include = .{ .restaurant = true },
});

// Later, load roles only for users that need them
for (users) |*user| {
    if (needsRoles(user)) {
        _ = try user.loadUserRolesCached(&client);
    }
}
```

#### Empty Include Types

Models without relations still get an empty Include type for API consistency:

```zig
pub const AuditLogArchiveInclude = struct {};

const archive = try client.auditLogArchive.findUnique(.{
    .where = .{ .id = .{ .equals = archive_id } },
    .include = .{}, // Empty but type-safe
});
```

This ensures all `findUnique` and `findMany` operations have a uniform signature.

### Relation Loading Patterns

#### Pattern 1: Manual Foreign Keys (Current Best Practice)

```zig
const user = try client.user.findUnique(.{...});
if (user) |u| {
    if (u.restaurantId) |rid| {
        const restaurant = try client.restaurant.findUnique(.{
            .where = .{ .id = .{ .equals = rid } },
        });
        // Use restaurant...
    }
}
```

**Pros:**
- Full control over queries
- Explicit and clear
- Works with all backends

**Cons:**
- Verbose for multiple relations
- Multiple database round-trips
- Manual null checking

#### Pattern 2: Lazy Loading with Loaders

```zig
const user = try client.user.findUnique(.{...});
if (user) |u| {
    const restaurant = try u.loadRestaurant(&client, allocator);
    // Use restaurant...
}
```

**Pros:**
- Cleaner syntax
- Automatic null handling
- Reusable across codebase

**Cons:**
- Still multiple queries
- Needs allocator management

#### Pattern 3: Cached Lazy Loading

```zig
var user = try client.user.findUnique(.{...});
if (user) |*u| {
    u.setAllocator(allocator);
    
    // First access - queries DB
    const restaurant = try u.loadRestaurantCached(&client);
    
    // Second access - from cache
    const same_restaurant = try u.loadRestaurantCached(&client);
}
```

**Pros:**
- Avoids duplicate queries
- Automatic caching
- Good for repeated access

**Cons:**
- Must manage cache lifetime
- Memory overhead
- Potential stale data

#### Pattern 4: Arena Allocator for Relations

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer 

6. **Use arena allocators for relations**
   ```zig
   var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
   defer arena.deinit();
   
   var user = try client.user.findUnique(.{...});
   if (user) |*u| {
       u.setAllocator(arena.allocator());
       // All cached relations freed with arena
   }
   ```

7. **Clear cache after updates**
   ```zig
   try client.restaurant.update(.{...});
   user.clearCache(); // Ensure fresh data on next load
   ```

8. **Prefer cached loaders for repeated access**
   ```zig
   // Good: cache for repeated use
   u.setAllocator(allocator);
   const r1 = try u.loadRestaurantCached(&client);
   const r2 = try u.loadRestaurantCached(&client); // from cache
   
   // Avoid: repeated queries
   const r1 = try u.loadRestaurant(&client, allocator);
   const r2 = try u.loadRestaurant(&client, allocator); // queries again
   ```

9. **Check foreign keys before loading**
   ```zig
   if (user.restaurantId != null) {
       const restaurant = try user.loadRestaurant(&client, allocator);
       // restaurant will not be null here
   }
   ```

10. **Use manual queries for complex relations**
    ```zig
    // When you need specific filters on related data
    const roles = try client.userRole.findMany(.{
        .where = .{
            .userId = .{ .equals = user.id },
            .isActive = .{ .equals = true },
        },
    });
    defer allocator.free(roles);
    ```arena.deinit();
const arena_alloc = arena.allocator();

var user = try client.user.findUnique(.{...});
if (user) |*u| {
    u.setAllocator(arena_alloc);
    
    // Load multiple relations - all use arena
    const restaurant = try u.loadRestaurantCached(&client);
    const profile = try u.loadProfileCached(&client);
    
    // Use relations...
    
    // All relation memory freed with arena.deinit()
}
```

**Pros:**
- Simplified memory management
- Perfect for request/response cycles
- No manual cleanup needed

**Cons:**
- All-or-nothing memory release
- Not suitable for long-lived objects

### Error Handling for Relations

```zig
const restaurant = u.loadRestaurant(&client, allocator) catch |err| {
    switch (err) {
        error.QueryFailed => {
            std.debug.print("Failed to load restaurant\n", .{});
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

**Cached Loaders:**
```zig
const restaurant = u.loadRestaurantCached(&client) catch |err| {
    switch (err) {
        error.AllocatorNotSet => {
            std.debug.print("Call setAllocator() first\n", .{});
            return err;
        },
        error.QueryFailed => {
            std.debug.print("Query failed\n", .{});
            return err;
        },
        else => return err,
    }
};
```

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
