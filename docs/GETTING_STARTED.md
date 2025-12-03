# Getting Started with Prisma Zig

This guide will walk you through setting up and using Prisma Zig in your project.

## Prerequisites

- Zig 0.13.0 or later
- PostgreSQL 12 or later
- Basic understanding of Zig and databases

## Installation

### 1. Add Prisma Zig to Your Project

Create or update your `build.zig.zon`:

```zig
.{
    .name = "my-app",
    .version = "0.1.0",
    .dependencies = .{
        .prisma_zig = .{
            .url = "https://github.com/zadockmaloba/prisma-zig/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "1220...", // Run zig build to get the correct hash
        },
        .libpq_zig = .{
            .url = "https://github.com/karlseguin/pg.zig/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "1220...",
        },
    },
}
```

### 2. Update Your build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add dependencies
    const prisma_zig = b.dependency("prisma_zig", .{
        .target = target,
        .optimize = optimize,
    });
    
    const libpq_zig = b.dependency("libpq_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("prisma_zig", prisma_zig.module("prisma_zig"));
    exe.root_module.addImport("libpq_zig", libpq_zig.module("libpq_zig"));
    
    b.installArtifact(exe);
}
```

## Setting Up Your Database

### 1. Create a PostgreSQL Database

```bash
createdb myapp_dev
```

Or using psql:

```sql
CREATE DATABASE myapp_dev;
```

### 2. Set Up Connection String

Create a `.env` file or export an environment variable:

```bash
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/myapp_dev"
```

## Creating Your First Schema

### 1. Create schema.prisma

Create a file named `schema.prisma` in your project root:

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

### 2. Generate Client Code

```bash
# Build the prisma-zig generator
cd path/to/prisma-zig
zig build

# Generate your client
./zig-out/bin/prisma_zig generate --cwd /path/to/your/project
```

This creates `src/prisma_client.zig` with type-safe database operations.

### 3. Create Migration

Create a `migrations` directory and add your first migration:

```bash
mkdir -p migrations
```

Create `migrations/001_init.sql`:

```sql
-- CreateTable
CREATE TABLE "user" (
    "id" INTEGER PRIMARY KEY,
    "email" TEXT NOT NULL UNIQUE,
    "name" TEXT,
    "createdAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "posts" (
    "id" INTEGER PRIMARY KEY,
    "title" TEXT NOT NULL,
    "content" TEXT,
    "published" BOOLEAN NOT NULL DEFAULT FALSE,
    "authorId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateIndex
CREATE UNIQUE INDEX "user_email_key" ON "user"("email");
```

### 4. Run Migration

```bash
psql $DATABASE_URL < migrations/001_init.sql
```

## Writing Your First Application

Create `src/main.zig`:

```zig
const std = @import("std");
const prisma = @import("prisma_client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Connect to database
    var conn = prisma.Connection.init(allocator);
    defer conn.deinit();
    
    try conn.connect("postgresql://postgres:postgres@localhost:5432/myapp_dev");
    
    // Initialize Prisma client
    var client = prisma.PrismaClient.init(allocator, &conn);
    
    // Create a user
    std.debug.print("Creating user...\n", .{});
    const user = try client.user.create(.init(
        1,
        "alice@example.com",
    ));
    std.debug.print("Created user: {s}\n", .{user.email});
    
    // Find all users
    std.debug.print("\nFinding all users...\n", .{});
    const users = try client.user.findMany(.{});
    defer allocator.free(users);
    
    for (users) |u| {
        std.debug.print("  - {s} (ID: {})\n", .{ u.email, u.id });
    }
    
    // Update the user
    std.debug.print("\nUpdating user...\n", .{});
    _ = try client.user.update(.{
        .where = .{ .id = .{ .equals = 1 } },
        .data = .{
            .id = 1,
            .email = "alice@example.com",
            .name = "Alice Wonderland",
            .createdAt = user.createdAt,
            .updatedAt = std.time.timestamp(),
        },
    });
    
    // Find the updated user
    const updated = try client.user.findUnique(.{
        .where = .{ .id = .{ .equals = 1 } },
    });
    
    if (updated) |u| {
        std.debug.print("Updated user: {s}, name: {?s}\n", .{ u.email, u.name });
    }
}
```

## Running Your Application

```bash
zig build run
```

You should see output like:

```
Creating user...
Created user: alice@example.com

Finding all users...
  - alice@example.com (ID: 1)

Updating user...
Updated user: alice@example.com, name: Alice Wonderland
```

## Common Patterns

### Environment-Based Configuration

```zig
const connection_string = std.process.getEnvVarOwned(
    allocator,
    "DATABASE_URL"
) catch "postgresql://postgres:postgres@localhost:5432/myapp_dev";
defer allocator.free(connection_string);

try conn.connect(connection_string);
```

### Error Handling

```zig
const user = client.user.create(.init(1, "test@example.com")) catch |err| {
    std.debug.print("Failed to create user: {}\n", .{err});
    return err;
};
```

### Working with Optional Fields

```zig
const user = try client.user.findUnique(.{
    .where = .{ .id = .{ .equals = 1 } },
});

if (user) |u| {
    if (u.name) |name| {
        std.debug.print("User name: {s}\n", .{name});
    } else {
        std.debug.print("User has no name\n", .{});
    }
}
```

### Filtering Results

```zig
// Find users with specific email domain
const company_users = try client.user.findMany(.{
    .where = .{
        .email = .{ .endsWith = "@company.com" },
    },
});
defer allocator.free(company_users);

// Find recently created users
const week_ago = std.time.timestamp() - (7 * 24 * 60 * 60);
const recent_users = try client.user.findMany(.{
    .where = .{
        .createdAt = .{ .gt = week_ago },
    },
});
defer allocator.free(recent_users);
```

## Next Steps

- Read the [API Reference](API.md) for detailed documentation
- Check out the [examples](../example/demo-1) for more complex use cases
- Learn about [schema design](SCHEMA.md) best practices
- Explore [advanced features](ADVANCED.md)

## Troubleshooting

### Connection Errors

If you get connection errors, verify:

1. PostgreSQL is running: `pg_isready`
2. Database exists: `psql -l | grep myapp_dev`
3. Connection string is correct
4. User has proper permissions

### Generation Errors

If code generation fails:

1. Check schema syntax with `prisma-zig validate`
2. Ensure all field types are supported
3. Verify relation definitions are correct

### Runtime Errors

Common runtime issues:

**NoSuchColumn**: Column name case mismatch. PostgreSQL lowercases unquoted identifiers.

**QueryFailed**: Check your SQL migration matches the schema.

**OutOfMemory**: Ensure you're freeing `findMany` results.

## Getting Help

- Check the [FAQ](FAQ.md)
- Open an issue on [GitHub](https://github.com/zadockmaloba/prisma-zig/issues)
- Join the discussion in [Discussions](https://github.com/zadockmaloba/prisma-zig/discussions)
