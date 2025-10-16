const std = @import("std");

const libpq = @cImport({
    @cInclude("libpq-fe.h");
});

const PostgresError = error{
    BufferInsertFailed,
    ConnectionFailed,
    ConnectionLost,
    InvalidConnectionString,
    AuthenticationFailed,
    QueryFailed,
    InvalidQuery,
    NoSuchTable,
    NoSuchColumn,
    PermissionDenied,
    TransactionBeginFailed,
    TransactionCommitFailed,
    TransactionRollbackFailed,
    TypeMismatch,
    InvalidUTF8,
    NullValue,
    QueryTimeout,
    ConnectionTimeout,
    NetworkError,
    SSLHandshakeFailed,
    ProtocolViolation,
    InvalidMessage,
    OutOfMemory,
    InternalError,
    Cancelled,
    ParameterBindingFailed,
    PreparedStatementFailed,
    InvalidColumnIndex,
    ResultSetExhausted,
    PoolExhausted,
    InvalidSSLConfig,
};

pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,
};

pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32,
};

pub const DateTime = struct {
    date: Date,
    time: Time,
};

pub const DateTimeTz = struct {
    datetime: DateTime,
    timezone_offset: i32, // seconds from UTC
};

pub const PgType = union(enum) {
    // Numeric types
    smallint: i16,
    integer: i32,
    bigint: i64,
    real: f32,
    double: f64,
    numeric: []const u8, // For precision decimals

    // Text types
    char: u8,
    varchar: []const u8,
    text: []const u8,

    // Date/Time types
    date: Date,
    time: Time,
    timestamp: DateTime,
    timestamptz: DateTimeTz,

    // Boolean
    boolean: bool,

    // Binary
    bytea: []const u8,

    // JSON
    json: []const u8,
    jsonb: []const u8,

    // Arrays
    array: []PgType,

    // UUID
    uuid: [16]u8,

    // NULL
    null: void,

    // Legacy support
    string: []const u8,
    number: i64,
};

pub const PostgresErrorInfo = struct {
    message: []const u8,
    sqlstate: []const u8,
    severity: []const u8,
    detail: []const u8,
    hint: []const u8,
};

pub const SSLConfig = struct {
    mode: enum { disable, allow, prefer, require, verify_ca, verify_full },
    cert_file: ?[]const u8 = null,
    key_file: ?[]const u8 = null,
    ca_file: ?[]const u8 = null,
};

pub const Row = struct {
    result: *libpq.PGresult,
    row_index: i32,
    allocator: std.mem.Allocator,

    pub fn get(self: *@This(), column: []const u8, comptime T: type) !T {
        const col_index = libpq.PQfnumber(self.result, column.ptr);
        if (col_index == -1) return PostgresError.NoSuchColumn;

        if (libpq.PQgetisnull(self.result, self.row_index, col_index) == 1) {
            return PostgresError.NullValue;
        }

        const value = libpq.PQgetvalue(self.result, self.row_index, col_index);
        return parseValue(T, std.mem.span(value));
    }

    pub fn getOpt(self: *@This(), column: []const u8, comptime T: type) !?T {
        const col_index = libpq.PQfnumber(self.result, column.ptr);
        if (col_index == -1) return PostgresError.NoSuchColumn;

        if (libpq.PQgetisnull(self.result, self.row_index, col_index) == 1) {
            return null;
        }

        const value = libpq.PQgetvalue(self.result, self.row_index, col_index);
        return parseValue(T, std.mem.span(value));
    }
};

pub const ResultSet = struct {
    result: *libpq.PGresult,
    current_row: i32,
    total_rows: i32,
    allocator: std.mem.Allocator,

    pub fn init(result: *libpq.PGresult, allocator: std.mem.Allocator) ResultSet {
        return ResultSet{
            .result = result,
            .current_row = 0,
            .total_rows = libpq.PQntuples(result),
            .allocator = allocator,
        };
    }

    pub fn next(self: *@This()) ?Row {
        if (self.current_row >= self.total_rows) return null;
        defer self.current_row += 1;
        return Row{
            .result = self.result,
            .row_index = self.current_row,
            .allocator = self.allocator,
        };
    }

    pub fn rowCount(self: *@This()) i32 {
        return self.total_rows;
    }

    pub fn columnCount(self: *@This()) i32 {
        return libpq.PQnfields(self.result);
    }
};

pub const QueryBuilder = struct {
    query: std.ArrayList(u8),
    params: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) QueryBuilder {
        return QueryBuilder{
            .query = std.ArrayList(u8).init(allocator),
            .params = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.query.deinit();
        for (self.params.items) |param| {
            self.allocator.free(param);
        }
        self.params.deinit();
    }

    pub fn sql(self: *@This(), text: []const u8) !*@This() {
        try self.query.appendSlice(text);
        return self;
    }

    pub fn bind(self: *@This(), value: anytype) !*@This() {
        const param_index = self.params.items.len + 1;
        try self.query.writer().print("${d}", .{param_index});

        const str_value = try valueToString(self.allocator, value);
        try self.params.append(str_value);
        return self;
    }

    pub fn build(self: *@This()) []const u8 {
        return self.query.items;
    }
};

fn parseValue(comptime T: type, value: []const u8) !T {
    switch (T) {
        i16 => return std.fmt.parseInt(i16, value, 10),
        i32 => return std.fmt.parseInt(i32, value, 10),
        i64 => return std.fmt.parseInt(i64, value, 10),
        f32 => return std.fmt.parseFloat(f32, value),
        f64 => return std.fmt.parseFloat(f64, value),
        bool => return std.mem.eql(u8, value, "t") or std.mem.eql(u8, value, "true"),
        []const u8 => return value,
        else => @compileError("Unsupported type for parseValue: " ++ @typeName(T)),
    }
}

fn valueToString(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    switch (T) {
        i16, i32, i64 => return std.fmt.allocPrint(allocator, "{d}", .{value}),
        f32, f64 => return std.fmt.allocPrint(allocator, "{d}", .{value}),
        bool => return allocator.dupe(u8, if (value) "true" else "false"),
        []const u8 => return allocator.dupe(u8, value),
        else => @compileError("Unsupported type for valueToString: " ++ @typeName(T)),
    }
}

pub const ConnectionPool = struct {
    connections: std.ArrayList(*Connection),
    available: std.ArrayList(*Connection),
    mutex: std.Thread.Mutex,
    max_connections: u32,
    min_connections: u32,
    allocator: std.mem.Allocator,
    connection_string: []const u8,

    pub fn init(allocator: std.mem.Allocator, connection_string: []const u8, min_connections: u32, max_connections: u32) !ConnectionPool {
        var pool = ConnectionPool{
            .connections = std.ArrayList(*Connection).init(allocator),
            .available = std.ArrayList(*Connection).init(allocator),
            .mutex = std.Thread.Mutex{},
            .max_connections = max_connections,
            .min_connections = min_connections,
            .allocator = allocator,
            .connection_string = try allocator.dupe(u8, connection_string),
        };

        // Create minimum connections
        for (0..min_connections) |_| {
            const conn = try allocator.create(Connection);
            conn.* = Connection.init(allocator);
            try conn.connect(connection_string);
            try pool.connections.append(conn);
            try pool.available.append(conn);
        }

        return pool;
    }

    pub fn deinit(self: *@This()) void {
        for (self.connections.items) |conn| {
            conn.deinit();
            self.allocator.destroy(conn);
        }
        self.connections.deinit();
        self.available.deinit();
        self.allocator.free(self.connection_string);
    }

    pub fn acquire(self: *@This()) !*Connection {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.items.len > 0) {
            return self.available.pop();
        }

        if (self.connections.items.len < self.max_connections) {
            const conn = try self.allocator.create(Connection);
            conn.* = Connection.init(self.allocator);
            try conn.connect(self.connection_string);
            try self.connections.append(conn);
            return conn;
        }

        return PostgresError.PoolExhausted;
    }

    pub fn release(self: *@This(), conn: *Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.available.append(conn) catch {};
    }
};

pub const Connection = struct {
    pq: ?*libpq.PGconn,
    last_result: ?*libpq.PGresult,
    is_reading: bool,
    is_reffed: bool,
    result_buffer: std.StringArrayHashMap(PgType),
    allocator: std.mem.Allocator,
    format_buffer: [16 * 1024]u8 = [_]u8{0} ** (16 * 1024), //16KB buffer
    prepared_statements: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) Connection {
        return .{
            .pq = null,
            .last_result = null,
            .is_reading = false,
            .is_reffed = false,
            .result_buffer = std.StringArrayHashMap(PgType).init(allocator),
            .allocator = allocator,
            .prepared_statements = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.result_buffer.deinit();
        self.prepared_statements.deinit();
        if (self.last_result != null) {
            libpq.PQclear(self.last_result);
        }
        if (self.pq != null) {
            libpq.PQfinish(self.pq);
            self.pq = null;
        }
    }

    pub fn connect(self: *@This(), connString: []const u8) !void {
        std.log.info("DB Connection parameters: {s}\n", .{connString});
        self.pq = libpq.PQconnectdb(@ptrCast(connString));
        const conn_status = libpq.PQstatus(self.pq);

        if (conn_status != libpq.CONNECTION_OK) {
            std.log.err("Connection failed: {s}\n", .{libpq.PQerrorMessage(self.pq)});
            return PostgresError.ConnectionFailed;
        }

        std.log.info("DB Connection success\n", .{});
    }

    pub fn connectWithSSL(self: *@This(), connString: []const u8, ssl_config: SSLConfig) !void {
        var full_conn_string = try std.fmt.allocPrint(self.allocator, "{s} sslmode={s}", .{ connString, @tagName(ssl_config.mode) });
        defer self.allocator.free(full_conn_string);

        if (ssl_config.cert_file) |cert| {
            const temp = full_conn_string;
            full_conn_string = try std.fmt.allocPrint(self.allocator, "{s} sslcert={s}", .{ temp, cert });
            self.allocator.free(temp);
        }

        if (ssl_config.key_file) |key| {
            const temp = full_conn_string;
            full_conn_string = try std.fmt.allocPrint(self.allocator, "{s} sslkey={s}", .{ temp, key });
            self.allocator.free(temp);
        }

        if (ssl_config.ca_file) |ca| {
            const temp = full_conn_string;
            full_conn_string = try std.fmt.allocPrint(self.allocator, "{s} sslrootcert={s}", .{ temp, ca });
            self.allocator.free(temp);
        }

        try self.connect(full_conn_string);
    }

    pub fn exec(self: *@This(), comptime query: []const u8, argv: anytype) !void {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        @memset(self.format_buffer[0..], 0);
        const m_query = try std.fmt.bufPrint(&self.format_buffer, query, argv);

        const result = libpq.PQexec(self.pq, @ptrCast(m_query));
        if (result == null) {
            std.log.err("Exec failed: {s}\n", .{libpq.PQerrorMessage(self.pq)});
            return PostgresError.QueryFailed;
        }
        self.last_result = result;
    }

    pub fn execSafe(self: *@This(), query: []const u8) !ResultSet {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const result = libpq.PQexec(self.pq, @ptrCast(query));
        if (result == null) {
            std.log.err("Exec failed: {s}\n", .{libpq.PQerrorMessage(self.pq)});
            return PostgresError.QueryFailed;
        }

        const status = libpq.PQresultStatus(result);
        if (status != libpq.PGRES_TUPLES_OK and status != libpq.PGRES_COMMAND_OK) {
            const err = libpq.PQresultErrorMessage(result);
            std.log.err("Query failed: {s}\n", .{err});
            libpq.PQclear(result);
            return PostgresError.QueryFailed;
        }

        return ResultSet.init(result, self.allocator);
    }

    // Prepared statements
    pub fn prepare(self: *@This(), name: []const u8, query: []const u8, param_types: []const u32) !void {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const result = libpq.PQprepare(self.pq, name.ptr, query.ptr, @intCast(param_types.len), if (param_types.len > 0) param_types.ptr else null);

        if (result == null) {
            return PostgresError.PreparedStatementFailed;
        }

        const status = libpq.PQresultStatus(result);
        libpq.PQclear(result);

        if (status != libpq.PGRES_COMMAND_OK) {
            return PostgresError.PreparedStatementFailed;
        }

        try self.prepared_statements.put(try self.allocator.dupe(u8, name), {});
    }

    pub fn execPrepared(self: *@This(), stmt_name: []const u8, params: []const ?[]const u8) !ResultSet {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        // Convert params to the format libpq expects
        var param_values: []const [*c]const u8 = undefined;
        if (params.len > 0) {
            param_values = try self.allocator.alloc([*c]const u8, params.len);
            defer self.allocator.free(param_values);

            for (params, 0..) |param, i| {
                param_values[i] = if (param) |p| p.ptr else null;
            }
        }

        const result = libpq.PQexecPrepared(self.pq, stmt_name.ptr, @intCast(params.len), if (params.len > 0) param_values.ptr else null, null, // param lengths (null for text format)
            null, // param formats (null for text format)
            0 // result format (0 for text)
        );

        if (result == null) {
            return PostgresError.QueryFailed;
        }

        const status = libpq.PQresultStatus(result);
        if (status != libpq.PGRES_TUPLES_OK and status != libpq.PGRES_COMMAND_OK) {
            const err = libpq.PQresultErrorMessage(result);
            std.log.err("Prepared query failed: {s}\n", .{err});
            libpq.PQclear(result);
            return PostgresError.QueryFailed;
        }

        return ResultSet.init(result, self.allocator);
    }

    // Transaction management
    pub fn beginTransaction(self: *@This()) !void {
        try self.exec("BEGIN", .{});
        const status = libpq.PQresultStatus(self.last_result);
        if (status != libpq.PGRES_COMMAND_OK) {
            return PostgresError.TransactionBeginFailed;
        }
    }

    pub fn commit(self: *@This()) !void {
        try self.exec("COMMIT", .{});
        const status = libpq.PQresultStatus(self.last_result);
        if (status != libpq.PGRES_COMMAND_OK) {
            return PostgresError.TransactionCommitFailed;
        }
    }

    pub fn rollback(self: *@This()) !void {
        try self.exec("ROLLBACK", .{});
        const status = libpq.PQresultStatus(self.last_result);
        if (status != libpq.PGRES_COMMAND_OK) {
            return PostgresError.TransactionRollbackFailed;
        }
    }

    pub fn savepoint(self: *@This(), name: []const u8) !void {
        try self.exec("SAVEPOINT {s}", .{name});
        const status = libpq.PQresultStatus(self.last_result);
        if (status != libpq.PGRES_COMMAND_OK) {
            return PostgresError.QueryFailed;
        }
    }

    pub fn rollbackToSavepoint(self: *@This(), name: []const u8) !void {
        try self.exec("ROLLBACK TO SAVEPOINT {s}", .{name});
        const status = libpq.PQresultStatus(self.last_result);
        if (status != libpq.PGRES_COMMAND_OK) {
            return PostgresError.QueryFailed;
        }
    }

    // Async operations
    pub fn execAsync(self: *@This(), query: []const u8) !void {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const result = libpq.PQsendQuery(self.pq, query.ptr);
        if (result != 1) {
            return PostgresError.QueryFailed;
        }
    }

    pub fn getResult(self: *@This()) !?*libpq.PGresult {
        if (self.pq == null) return PostgresError.ConnectionFailed;
        return libpq.PQgetResult(self.pq);
    }

    pub fn isNonBlocking(self: *@This()) bool {
        if (self.pq == null) return false;
        return libpq.PQisnonblocking(self.pq) == 1;
    }

    pub fn setNonBlocking(self: *@This(), non_blocking: bool) !void {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const result = libpq.PQsetnonblocking(self.pq, if (non_blocking) 1 else 0);
        if (result != 0) {
            return PostgresError.QueryFailed;
        }
    }

    // Connection health
    pub fn ping(self: *@This()) bool {
        if (self.pq == null) return false;
        return libpq.PQstatus(self.pq) == libpq.CONNECTION_OK;
    }

    pub fn reconnect(self: *@This()) !void {
        if (self.pq != null) {
            libpq.PQreset(self.pq);
            if (libpq.PQstatus(self.pq) == libpq.CONNECTION_OK) {
                return;
            }
        }
        return PostgresError.ConnectionFailed;
    }

    // Enhanced error handling
    pub fn getDetailedError(self: *@This()) PostgresErrorInfo {
        if (self.last_result == null) return PostgresErrorInfo{
            .message = "No result available",
            .sqlstate = "",
            .severity = "",
            .detail = "",
            .hint = "",
        };

        return PostgresErrorInfo{
            .message = std.mem.span(libpq.PQresultErrorMessage(self.last_result) orelse "Unknown error"),
            .sqlstate = std.mem.span(libpq.PQresultErrorField(self.last_result, libpq.PG_DIAG_SQLSTATE) orelse ""),
            .severity = std.mem.span(libpq.PQresultErrorField(self.last_result, libpq.PG_DIAG_SEVERITY) orelse ""),
            .detail = std.mem.span(libpq.PQresultErrorField(self.last_result, libpq.PG_DIAG_MESSAGE_DETAIL) orelse ""),
            .hint = std.mem.span(libpq.PQresultErrorField(self.last_result, libpq.PG_DIAG_MESSAGE_HINT) orelse ""),
        };
    }

    // Bulk operations
    pub fn copyFrom(self: *@This(), table: []const u8, columns: []const []const u8, data: []const []const []const u8) !void {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const column_list = try std.mem.join(self.allocator, ",", columns);
        defer self.allocator.free(column_list);

        const copy_query = try std.fmt.allocPrint(self.allocator, "COPY {s} ({s}) FROM STDIN WITH CSV", .{ table, column_list });
        defer self.allocator.free(copy_query);

        const result = libpq.PQexec(self.pq, copy_query.ptr);
        if (result == null or libpq.PQresultStatus(result) != libpq.PGRES_COPY_IN) {
            if (result != null) libpq.PQclear(result);
            return PostgresError.QueryFailed;
        }
        libpq.PQclear(result);

        // Send data
        for (data) |row| {
            const row_data = try std.mem.join(self.allocator, ",", row);
            defer self.allocator.free(row_data);

            const line = try std.fmt.allocPrint(self.allocator, "{s}\n", .{row_data});
            defer self.allocator.free(line);

            if (libpq.PQputCopyData(self.pq, line.ptr, @intCast(line.len)) != 1) {
                _ = libpq.PQputCopyEnd(self.pq, "Error during COPY");
                return PostgresError.QueryFailed;
            }
        }

        // End copy
        if (libpq.PQputCopyEnd(self.pq, null) != 1) {
            return PostgresError.QueryFailed;
        }

        // Get final result
        const final_result = libpq.PQgetResult(self.pq);
        if (final_result == null or libpq.PQresultStatus(final_result) != libpq.PGRES_COMMAND_OK) {
            if (final_result != null) libpq.PQclear(final_result);
            return PostgresError.QueryFailed;
        }
        libpq.PQclear(final_result);
    }

    pub fn getLastResult(self: *@This()) !std.StringArrayHashMap(PgType).Iterator {
        const stat = libpq.PQresultStatus(self.last_result);

        switch (stat) {
            libpq.PGRES_COMMAND_OK => return self.result_buffer.iterator(),
            libpq.PGRES_TUPLES_OK => {
                const nrows: usize = @intCast(libpq.PQntuples(self.last_result));
                const ncols: usize = @intCast(libpq.PQnfields(self.last_result));

                // Clear the result buffer to store fresh data
                self.result_buffer.clearAndFree();

                for (0..nrows) |i| for (0..ncols) |j| {
                    const field_name = std.mem.span(libpq.PQfname(self.last_result, @intCast(j)));
                    const value = std.mem.span(libpq.PQgetvalue(self.last_result, @intCast(i), @intCast(j)));

                    const field_type = libpq.PQftype(self.last_result, @intCast(j));
                    var pg_value: PgType = undefined;

                    std.debug.print("OID: {}\n", .{field_type});

                    pg_value = switch (field_type) {
                        16 => PgType{ .boolean = std.mem.eql(u8, value, "t") }, // bool
                        20 => PgType{ .bigint = std.fmt.parseInt(i64, value, 10) catch 0 }, // int8
                        21 => PgType{ .smallint = std.fmt.parseInt(i16, value, 10) catch 0 }, // int2
                        23 => PgType{ .integer = std.fmt.parseInt(i32, value, 10) catch 0 }, // int4
                        700 => PgType{ .real = std.fmt.parseFloat(f32, value) catch 0.0 }, // float4
                        701 => PgType{ .double = std.fmt.parseFloat(f64, value) catch 0.0 }, // float8
                        1042, 1043 => PgType{ .varchar = value }, // char, varchar
                        25 => PgType{ .text = value }, // text
                        114, 3802 => PgType{ .json = value }, // json, jsonb
                        17 => PgType{ .bytea = value }, // bytea
                        2950 => blk: { // uuid
                            const uuid_bytes: [16]u8 = [_]u8{0} ** 16;
                            // TODO: Parse UUID string to bytes properly
                            break :blk PgType{ .uuid = uuid_bytes };
                        },
                        1700 => PgType{ .numeric = value }, // numeric
                        // Legacy support
                        20...23 => PgType{ .number = std.fmt.parseInt(i64, value, 10) catch {
                            std.debug.print("Error parsing number for column {s}\n", .{field_name});
                            continue;
                        } },
                        else => PgType{ .string = value },
                    };

                    self.result_buffer.put(field_name[0..], pg_value) catch {
                        return PostgresError.BufferInsertFailed;
                    };
                };

                std.debug.print("Rows: {}, Columns: {}\n", .{ nrows, ncols });
                return self.result_buffer.iterator();
            },
            else => {
                const err = libpq.PQresultErrorMessage(self.last_result);
                std.debug.print("Query Fatal Error: {s}\n", .{err});
                return PostgresError.QueryFailed;
            },
        }
    }

    pub fn getLastErrorMessage(self: *@This()) ?[]const u8 {
        if (self.pq != null) {
            return std.mem.span(libpq.PQerrorMessage(self.pq));
        }
        return null;
    }

    pub fn serverVersion(self: *@This()) i32 {
        return libpq.PQserverVersion(self.pq);
    }

    pub fn clientVersion(self: *@This()) i32 {
        _ = self;
        return libpq.PQlibVersion();
    }

    pub fn escapeLiteral(self: *@This(), str: []const u8) ![]u8 {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const escaped = libpq.PQescapeLiteral(self.pq, str.ptr, str.len);
        if (escaped == null) {
            return PostgresError.QueryFailed;
        }
        defer libpq.PQfreemem(escaped);

        return self.allocator.dupe(u8, std.mem.span(escaped));
    }

    pub fn escapeIdentifier(self: *@This(), str: []const u8) ![]u8 {
        if (self.pq == null) return PostgresError.ConnectionFailed;

        const escaped = libpq.PQescapeIdentifier(self.pq, str.ptr, str.len);
        if (escaped == null) {
            return PostgresError.QueryFailed;
        }
        defer libpq.PQfreemem(escaped);

        return self.allocator.dupe(u8, std.mem.span(escaped));
    }
};

// Utility functions for working with PostgreSQL
pub fn createConnectionString(allocator: std.mem.Allocator, host: []const u8, port: u16, database: []const u8, username: []const u8, password: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "host={s} port={d} dbname={s} user={s} password={s}", .{ host, port, database, username, password });
}

pub fn parseUUID(uuid_str: []const u8) ![16]u8 {
    if (uuid_str.len != 36) return PostgresError.TypeMismatch;

    var uuid_bytes: [16]u8 = undefined;
    var byte_index: usize = 0;
    var i: usize = 0;

    while (i < uuid_str.len and byte_index < 16) : (i += 1) {
        if (uuid_str[i] == '-') continue;

        if (i + 1 >= uuid_str.len) return PostgresError.TypeMismatch;

        const hex_byte = std.fmt.parseInt(u8, uuid_str[i .. i + 2], 16) catch return PostgresError.TypeMismatch;
        uuid_bytes[byte_index] = hex_byte;
        byte_index += 1;
        i += 1; // Skip the second hex character
    }

    return uuid_bytes;
}

pub fn formatUUID(uuid_bytes: [16]u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ uuid_bytes[0], uuid_bytes[1], uuid_bytes[2], uuid_bytes[3], uuid_bytes[4], uuid_bytes[5], uuid_bytes[6], uuid_bytes[7], uuid_bytes[8], uuid_bytes[9], uuid_bytes[10], uuid_bytes[11], uuid_bytes[12], uuid_bytes[13], uuid_bytes[14], uuid_bytes[15] });
}

// Database migration utilities
pub const Migration = struct {
    version: u32,
    name: []const u8,
    up_sql: []const u8,
    down_sql: []const u8,
};

pub const MigrationRunner = struct {
    connection: *Connection,
    allocator: std.mem.Allocator,

    pub fn init(connection: *Connection, allocator: std.mem.Allocator) MigrationRunner {
        return MigrationRunner{
            .connection = connection,
            .allocator = allocator,
        };
    }

    pub fn ensureMigrationTable(self: *@This()) !void {
        const create_table_sql =
            \\CREATE TABLE IF NOT EXISTS schema_migrations (
            \\    version INTEGER PRIMARY KEY,
            \\    name TEXT NOT NULL,
            \\    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            \\)
        ;

        _ = try self.connection.execSafe(create_table_sql);
    }

    pub fn applyMigration(self: *@This(), migration: Migration) !void {
        try self.connection.beginTransaction();
        errdefer self.connection.rollback() catch {};

        // Check if migration already applied
        const check_sql = "SELECT version FROM schema_migrations WHERE version = $1";
        try self.connection.prepare("check_migration", check_sql, &[_]u32{23}); // int4

        const version_str = try std.fmt.allocPrint(self.allocator, "{d}", .{migration.version});
        defer self.allocator.free(version_str);

        var result = try self.connection.execPrepared("check_migration", &[_]?[]const u8{version_str});
        if (result.rowCount() > 0) {
            try self.connection.rollback();
            std.log.info("Migration {d} already applied\n", .{migration.version});
            return;
        }

        // Apply migration
        _ = try self.connection.execSafe(migration.up_sql);

        // Record migration
        const insert_sql = "INSERT INTO schema_migrations (version, name) VALUES ($1, $2)";
        try self.connection.prepare("insert_migration", insert_sql, &[_]u32{ 23, 25 }); // int4, text
        _ = try self.connection.execPrepared("insert_migration", &[_]?[]const u8{ version_str, migration.name });

        try self.connection.commit();
        std.log.info("Applied migration {d}: {s}\n", .{ migration.version, migration.name });
    }

    pub fn rollbackMigration(self: *@This(), migration: Migration) !void {
        try self.connection.beginTransaction();
        errdefer self.connection.rollback() catch {};

        // Apply rollback
        _ = try self.connection.execSafe(migration.down_sql);

        // Remove migration record
        const delete_sql = "DELETE FROM schema_migrations WHERE version = $1";
        try self.connection.prepare("delete_migration", delete_sql, &[_]u32{23}); // int4

        const version_str = try std.fmt.allocPrint(self.allocator, "{d}", .{migration.version});
        defer self.allocator.free(version_str);

        _ = try self.connection.execPrepared("delete_migration", &[_]?[]const u8{version_str});

        try self.connection.commit();
        std.log.info("Rolled back migration {d}: {s}\n", .{ migration.version, migration.name });
    }
};

// Connection monitoring and metrics
pub const ConnectionMetrics = struct {
    total_queries: u64,
    successful_queries: u64,
    failed_queries: u64,
    total_connection_time: u64, // milliseconds
    last_activity: i64, // timestamp

    pub fn init() ConnectionMetrics {
        return ConnectionMetrics{
            .total_queries = 0,
            .successful_queries = 0,
            .failed_queries = 0,
            .total_connection_time = 0,
            .last_activity = std.time.timestamp(),
        };
    }

    pub fn recordQuery(self: *@This(), success: bool, duration_ms: u64) void {
        self.total_queries += 1;
        if (success) {
            self.successful_queries += 1;
        } else {
            self.failed_queries += 1;
        }
        self.total_connection_time += duration_ms;
        self.last_activity = std.time.timestamp();
    }

    pub fn getSuccessRate(self: *@This()) f64 {
        if (self.total_queries == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successful_queries)) / @as(f64, @floatFromInt(self.total_queries));
    }

    pub fn getAverageQueryTime(self: *@This()) f64 {
        if (self.total_queries == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_connection_time)) / @as(f64, @floatFromInt(self.total_queries));
    }
};

