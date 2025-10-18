# Prisma Zig - MVP Development Plan

## Project Overview
A Zig PostgreSQL client library inspired by Prisma that generates type-safe database code at compile time from a Prisma schema file.

## MVP Requirements

### Core Components

#### 1. Schema Parser
- Parse Prisma schema files (`.prisma` format)
- Extract model definitions, field types, constraints, and relationships
- Support basic field types: String, Int, Boolean, DateTime
- Handle optional fields, unique constraints, and default values

#### 2. Code Generator (Compile-time)
- Generate Zig structs from Prisma models
- Create type-safe query builders for each model
- Generate CRUD operations (Create, Read, Update, Delete)
- Integrate with Zig's build system for compile-time generation

#### 3. Enhanced Query Builder
- Extend existing `QueryBuilder` in `src/db/psql.zig`
- Type-safe query construction
- Basic filtering with WHERE clauses
- Support for simple conditions and operators

#### 4. Client API
- High-level, type-safe database interface
- Generated model-specific methods
- Connection management using existing infrastructure

## Implementation Phases

### Phase 1: Schema Parser Foundation
**Files to create:**
- `src/schema/parser.zig` - Core schema parsing logic
- `src/schema/types.zig` - Schema type definitions

**Key structures:**
```zig
pub const PrismaModel = struct {
    name: []const u8,
    fields: []Field,
};

pub const Field = struct {
    name: []const u8,
    type: FieldType,
    optional: bool,
    unique: bool,
    default_value: ?[]const u8,
};

pub const FieldType = enum {
    string,
    int,
    boolean,
    datetime,
};

pub const Schema = struct {
    models: []PrismaModel,
    
    pub fn parse(allocator: std.mem.Allocator, schema_content: []const u8) !Schema;
};
```

### Phase 2: Code Generation
**Files to create:**
- `src/codegen/generator.zig` - Main code generation logic
- `src/codegen/templates.zig` - Code templates for generated structs/methods

**Functionality:**
- Generate struct definitions from models
- Create CRUD operation methods
- Generate type-safe query builders
- Output valid Zig code as strings

### Phase 3: Build System Integration
**Files to modify:**
- `build.zig` - Add code generation build step

**Integration points:**
- Add schema file processing step
- Generate client code before compilation
- Integrate generated code with module system

### Phase 4: Enhanced Query Builder
**Files to modify:**
- `src/db/psql.zig` - Extend existing QueryBuilder

**Enhancements:**
- Type-safe WHERE clause construction
- Support for basic operators (=, !=, <, >, LIKE, etc.)
- Method chaining for query building

### Phase 5: Client API
**Files to create:**
- `src/client/base.zig` - Base client functionality
- Generated files (at build time)

**Files to modify:**
- `src/root.zig` - Export generated client

## MVP Feature Set

### Supported Operations
1. **Create** - Insert new records
2. **FindMany** - Query multiple records with filtering
3. **FindUnique** - Query single record by unique field
4. **Update** - Modify existing records
5. **Delete** - Remove records

### Supported Field Types (Initial)
- `String` - Text fields
- `Int` - Integer fields
- `Boolean` - Boolean fields
- `DateTime` - Timestamp fields

### Supported Query Features
- Basic WHERE conditions
- Simple operators (=, !=, <, >, contains)
- Single table queries (no joins initially)

## Example Usage Goal
```zig
const Client = @import("prisma_client");

var client = Client.init(allocator, connection_string);
defer client.deinit();

// Create operation
const user = try client.user.create(.{
    .name = "John Doe",
    .email = "john@example.com",
});

// Query operations
const users = try client.user.findMany(.{
    .where = .{ .email = .{ .contains = "example.com" } },
});

const user = try client.user.findUnique(.{
    .where = .{ .id = 1 },
});

// Update operation
const updated_user = try client.user.update(.{
    .where = .{ .id = 1 },
    .data = .{ .name = "Jane Doe" },
});

// Delete operation
try client.user.delete(.{
    .where = .{ .id = 1 },
});
```

## Current Infrastructure Leverage

### Existing Components (in `src/db/psql.zig`)
- ✅ `Connection` - Database connection management
- ✅ `ConnectionPool` - Connection pooling
- ✅ `QueryBuilder` - Basic query construction
- ✅ `ResultSet` - Query result handling
- ✅ `MigrationRunner` - Database migration support

### Integration Points
- Use existing connection infrastructure
- Extend QueryBuilder for type-safe operations
- Leverage ResultSet for parsing query results
- Build upon MigrationRunner for schema migrations

## Success Criteria for MVP

1. **Parse basic Prisma schema** - Successfully parse `.prisma` files with simple models
2. **Generate working Zig code** - Produce compilable Zig structs and methods
3. **Execute basic CRUD operations** - Create, read, update, delete records
4. **Type safety** - Compile-time type checking for database operations
5. **Integration** - Works with existing PostgreSQL infrastructure

## Future Enhancements (Post-MVP)

- Relationship support (one-to-many, many-to-many)
- JOIN operations
- Advanced filtering and sorting
- Transactions
- Connection string parsing from schema
- Migration generation from schema changes
- More field types (JSON, Arrays, etc.)
- Validation and constraints
- Indexes and performance optimization

## Development Timeline

1. **Week 1-2**: Schema parser implementation
2. **Week 3**: Code generation foundation
3. **Week 4**: Build system integration
4. **Week 5**: Query builder enhancements
5. **Week 6**: Client API and testing
6. **Week 7**: Documentation and polish

## Testing Strategy

- Unit tests for schema parser
- Integration tests with PostgreSQL database
- Generated code compilation tests
- End-to-end workflow tests
- Performance benchmarks against raw SQL

---

**Status**: Planning Phase  
**Last Updated**: October 16, 2025