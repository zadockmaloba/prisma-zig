# Prisma Zig

A modern database toolkit for Zig, inspired by Prisma. Generate type-safe database clients from declarative schema files.

## Features

- 🔒 **Type-safe database operations** - Compile-time type checking for all database queries
- 📝 **Declarative schema** - Define your data models using a simple, readable schema language
- 🔄 **Full CRUD operations** - Create, Read, Update, Delete with generated type-safe methods
- 🎯 **PostgreSQL support** - First-class support for PostgreSQL databases
- ⚡ **Code generation** - Automatically generate Zig client code from your schema
- 🔍 **Rich query API** - Filter, sort, and query your data with an intuitive API

## Quick Start

### Integration with your Zig projects

Add Prisma Zig to your `build.zig.zon`:

```zig
.dependencies = .{
    .prisma_zig = .{
        .url = "https://github.com/zadockmaloba/prisma-zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
}
```

Add the following to your `build.zig`:
```zig
const prisma_build = @import("prisma_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    prisma_build.addPrismaBuildSteps(b, target, optimize);
    ...
}
```

### Define Your Schema

Create a `schema.prisma` file:

```prisma
model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String?
  posts     Post[]
  createdAt DateTime @default(now())
  updatedAt DateTime @default(now())
}

model Post {
  id        Int      @id @default(autoincrement())
  title     String
  content   String?
  published Boolean  @default(false)
  author    User     @relation(fields: [authorId], references: [id])
  authorId  Int
  createdAt DateTime @default(now())
}
```

### Generate Client Code

```bash
# Initialize Prisma in your project
prisma-zig init

# Generate the Zig client code
prisma-zig generate
```

### Use in Your Application

```zig
const std = @import("std");
const prisma = @import("prisma_client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Connect to the database
    var conn = prisma.Connection.init(allocator);
    defer conn.deinit();
    try conn.connect("postgresql://user:password@localhost:5432/mydb");

    // Initialize the Prisma client
    var client = prisma.PrismaClient.init(allocator, &conn);

    // Create a new user
    const user = try client.user.create(.init(
        1,
        "alice@example.com",
    ));
    std.debug.print("Created user: {s}\n", .{user.email});

    // Find all users
    const users = try client.user.findMany(.{});
    defer allocator.free(users);
    for (users) |u| {
        std.debug.print("User: {s}\n", .{u.email});
    }

    // Find a specific user
    const alice = try client.user.findUnique(.{
        .where = .{ .email = .{ .equals = "alice@example.com" } },
    });
    if (alice) |u| {
        std.debug.print("Found: {s}\n", .{u.email});
    }

    // Update a user
    _ = try client.user.update(.{
        .where = .{ .id = .{ .equals = 1 } },
        .data = .{
            .id = 1,
            .email = "alice@example.com",
            .name = "Alice Wonderland",
            .createdAt = std.time.timestamp(),
            .updatedAt = std.time.timestamp(),
        },
    });

    // Delete a user
    try client.user.delete(.{
        .where = .{ .id = .{ .equals = 1 } },
    });
}
```

## Schema Language

### Models

Define your data models with the `model` keyword:

```prisma
model User {
  id    Int    @id @default(autoincrement())
  email String @unique
  name  String?
}
```

### Field Types

Supported field types:

- `Int` - 32-bit integer (maps to `i32` in Zig)
- `String` - Text/varchar (maps to `[]const u8` in Zig)
- `Boolean` - Boolean (maps to `bool` in Zig)
- `DateTime` - Timestamp (maps to `i64` Unix timestamp in Zig)

### Field Attributes

- `@id` - Primary key
- `@unique` - Unique constraint
- `@default(value)` - Default value
  - `@default(autoincrement())` - Auto-increment for Int fields
  - `@default(now())` - Current timestamp for DateTime fields
  - `@default(false)` - Literal values

### Optionality

Add `?` after the type to make a field optional:

```prisma
model User {
  name String?  // Optional field
  bio  String?  // Another optional field
}
```

### Relations

Define relationships between models:

```prisma
model User {
  id    Int    @id
  posts Post[]
}

model Post {
  id       Int  @id
  author   User @relation(fields: [authorId], references: [id])
  authorId Int
}
```

## Generated API

### Create Operations

```zig
const user = try client.user.create(.init(
    1,
    "alice@example.com",
));
```

The `create` method:
- Inserts a new record into the database
- Returns the created record with all database-generated values
- Uses PostgreSQL's `RETURNING` clause for efficiency

### Find Operations

#### findMany

Find multiple records with optional filtering:

```zig
// Find all users
const all_users = try client.user.findMany(.{});

// Find with filter
const filtered = try client.user.findMany(.{
    .where = .{ .email = .{ .contains = "example.com" } },
});
```

#### findUnique

Find a single record by unique field:

```zig
const user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = 1 } },
});

if (user) |u| {
    // User found
} else {
    // User not found
}
```

### Update Operations

```zig
const updated = try client.user.update(.{
    .where = .{ .id = .{ .equals = 1 } },
    .data = .{
        .id = 1,
        .email = "newemail@example.com",
        .name = "New Name",
        .createdAt = std.time.timestamp(),
        .updatedAt = std.time.timestamp(),
    },
});
```

### Delete Operations

```zig
try client.user.delete(.{
    .where = .{ .id = .{ .equals = 1 } },
});
```

## Filter Options

### String Filters

```zig
.email = .{ .equals = "exact@match.com" }
.email = .{ .contains = "substring" }
.email = .{ .startsWith = "prefix" }
.email = .{ .endsWith = "suffix" }
```

### Integer Filters

```zig
.id = .{ .equals = 42 }
.id = .{ .lt = 100 }      // Less than
.id = .{ .lte = 100 }     // Less than or equal
.id = .{ .gt = 0 }        // Greater than
.id = .{ .gte = 0 }       // Greater than or equal
```

### Boolean Filters

```zig
.published = .{ .equals = true }
```

### DateTime Filters

```zig
.createdAt = .{ .equals = timestamp }
.createdAt = .{ .lt = timestamp }
.createdAt = .{ .lte = timestamp }
.createdAt = .{ .gt = timestamp }
.createdAt = .{ .gte = timestamp }
```

## CLI Commands

### Initialize a Project

```bash
prisma-zig init
```

Creates a new Prisma schema file in your project.

### Generate Client Code

```bash
prisma-zig generate
```

Generates type-safe Zig client code from your schema.

### Database Migrations

```bash
# Create and apply migrations
prisma-zig migrate-dev

# Apply pending migrations
prisma-zig migrate

# View migration status
prisma-zig migrate-status
```

### Database Operations

```bash
# Pull schema from existing database
prisma-zig db-pull

# Push schema changes to database
prisma-zig db-push
```

### Utility Commands

```bash
# Validate schema
prisma-zig validate

# Format schema file
prisma-zig format

# Show version
prisma-zig version
```

## Project Structure

```
my-project/
├── schema.prisma          # Your database schema
├── src/
│   ├── main.zig          # Your application code
│   └── prisma_client.zig # Generated Prisma client
├── migrations/           # Database migrations
│   └── TIMESTAMP_init.sql
├── build.zig
└── build.zig.zon
```

## Configuration

### Database Connection

Connection strings follow the PostgreSQL format:

```
postgresql://username:password@host:port/database
```

Example:
```
postgresql://postgres:postgres@localhost:5432/mydb
```

### Environment Variables

You can use environment variables for sensitive data:

```zig
const connection_string = try std.process.getEnvVarOwned(
    allocator,
    "DATABASE_URL"
);
defer allocator.free(connection_string);
```

## Architecture

### Code Generation

Prisma Zig uses a three-phase approach:

1. **Schema Parsing** - Parse the `.prisma` schema file into an AST
2. **Code Generation** - Generate type-safe Zig code from the AST
3. **SQL Generation** - Create SQL migration files

### Type Safety

All database operations are type-checked at compile time:

- Field names must match the schema
- Filter operators must match field types
- Relations are properly typed

### Memory Management

The generated client uses Zig's allocator pattern:

- Pass an allocator to the client on initialization
- Use `defer` to clean up allocated memory
- `findMany` returns owned slices that must be freed

## Examples

See the `example/demo-1` directory for a complete working example.

## Dependencies

- Zig 0.13.0 or later
- PostgreSQL 12 or later
- [libpq_zig](https://github.com/karlseguin/pg.zig) - PostgreSQL client library

## Roadmap

- [ ] More database backends (MySQL, SQLite)
- [ ] Advanced query features (joins, aggregations)
- [ ] Transaction support
- [ ] Connection pooling
- [ ] Soft deletes
- [ ] Cascading operations
- [ ] Custom validation
- [ ] Middleware/hooks

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Inspired by [Prisma](https://www.prisma.io/)
- Built with [Zig](https://ziglang.org/)
- PostgreSQL support via [libpq_zig](https://github.com/karlseguin/pg.zig)
