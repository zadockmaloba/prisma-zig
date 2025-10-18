const std = @import("std");
const types = @import("types.zig");

const Schema = types.Schema;
const PrismaModel = types.PrismaModel;
const Field = types.Field;
const FieldType = types.FieldType;
const FieldAttribute = types.FieldAttribute;
const ParseError = types.ParseError;
const GeneratorConfig = types.GeneratorConfig;
const DatasourceConfig = types.DatasourceConfig;

/// Token types for the lexer
const TokenType = enum {
    // Literals
    identifier,
    string_literal,
    number_literal,

    // Keywords
    model,
    generator,
    datasource,

    // Symbols
    left_brace, // {
    right_brace, // }
    left_paren, // (
    right_paren, // )
    question_mark, // ?
    at_symbol, // @
    equals, // =
    newline,

    // Special
    eof,
    invalid,
};

/// A token in the source code
const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

/// Lexer for tokenizing Prisma schema files
const Lexer = struct {
    source: []const u8,
    current: usize = 0,
    line: usize = 1,
    column: usize = 1,

    pub fn init(source: []const u8) Lexer {
        return Lexer{
            .source = source,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();

        if (self.isAtEnd()) {
            return self.makeToken(.eof);
        }

        const start_column = self.column;
        const c = self.advance();

        return switch (c) {
            '{' => self.makeToken(.left_brace),
            '}' => self.makeToken(.right_brace),
            '(' => self.makeToken(.left_paren),
            ')' => self.makeToken(.right_paren),
            '?' => self.makeToken(.question_mark),
            '@' => self.makeToken(.at_symbol),
            '=' => self.makeToken(.equals),
            '\n' => self.makeTokenWithColumn(.newline, start_column),
            '"' => self.string(),
            else => {
                if (std.ascii.isAlphabetic(c) or c == '_') {
                    return self.identifier();
                } else if (std.ascii.isDigit(c)) {
                    return self.number();
                } else {
                    return self.makeTokenWithColumn(.invalid, start_column);
                }
            },
        };
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.current];
        self.current += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    fn peek(self: *const Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *const Lexer) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn makeToken(self: *Lexer, token_type: TokenType) Token {
        return Token{
            .type = token_type,
            .lexeme = self.source[self.current - 1 .. self.current],
            .line = self.line,
            .column = self.column - 1,
        };
    }

    fn makeTokenWithColumn(self: *Lexer, token_type: TokenType, column: usize) Token {
        return Token{
            .type = token_type,
            .lexeme = self.source[self.current - 1 .. self.current],
            .line = self.line,
            .column = column,
        };
    }

    fn makeTokenFromRange(self: *Lexer, token_type: TokenType, start: usize) Token {
        return Token{
            .type = token_type,
            .lexeme = self.source[start..self.current],
            .line = self.line,
            .column = self.column - (self.current - start),
        };
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        // Line comment
                        while (!self.isAtEnd() and self.peek() != '\n') {
                            _ = self.advance();
                        }
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }
    }

    fn string(self: *Lexer) Token {
        const start = self.current - 1;

        while (!self.isAtEnd() and self.peek() != '"') {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            return self.makeTokenFromRange(.invalid, start);
        }

        // Closing quote
        _ = self.advance();

        return self.makeTokenFromRange(.string_literal, start);
    }

    fn identifier(self: *Lexer) Token {
        const start = self.current - 1;

        while (!self.isAtEnd() and (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_')) {
            _ = self.advance();
        }

        const lexeme = self.source[start..self.current];
        const token_type = self.getIdentifierType(lexeme);

        return self.makeTokenFromRange(token_type, start);
    }

    fn number(self: *Lexer) Token {
        const start = self.current - 1;

        while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
            _ = self.advance();
        }

        return self.makeTokenFromRange(.number_literal, start);
    }

    fn getIdentifierType(self: *Lexer, text: []const u8) TokenType {
        _ = self;
        if (std.mem.eql(u8, text, "model")) return .model;
        if (std.mem.eql(u8, text, "generator")) return .generator;
        if (std.mem.eql(u8, text, "datasource")) return .datasource;
        return .identifier;
    }
};

/// Parser for Prisma schema files
pub const Parser = struct {
    lexer: Lexer,
    current_token: Token,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        var parser = Parser{
            .lexer = Lexer.init(source),
            .current_token = undefined,
            .allocator = allocator,
        };
        parser.advance();
        return parser;
    }

    pub fn parse(self: *Parser) ParseError!Schema {
        var schema = Schema.init(self.allocator);

        while (!self.isAtEnd()) {
            if (self.match(.newline)) {
                continue;
            }

            switch (self.current_token.type) {
                .model => {
                    const model = try self.parseModel();
                    try schema.addModel(model);
                },
                .generator => {
                    schema.generator = try self.parseGenerator();
                },
                .datasource => {
                    schema.datasource = try self.parseDatasource();
                },
                .eof => break,
                else => {
                    std.log.err("Unexpected token: {s} at line {d}", .{ self.current_token.lexeme, self.current_token.line });
                    return ParseError.InvalidSyntax;
                },
            }
        }

        return schema;
    }

    fn advance(self: *Parser) void {
        self.current_token = self.lexer.nextToken();
    }

    fn isAtEnd(self: *const Parser) bool {
        return self.current_token.type == .eof;
    }

    fn match(self: *Parser, token_type: TokenType) bool {
        if (self.current_token.type == token_type) {
            self.advance();
            return true;
        }
        return false;
    }

    fn consume(self: *Parser, token_type: TokenType, message: []const u8) ParseError!Token {
        if (self.current_token.type == token_type) {
            const token = self.current_token;
            self.advance();
            return token;
        }

        std.log.err("{s} at line {d}, got: {s}", .{ message, self.current_token.line, self.current_token.lexeme });
        return ParseError.InvalidSyntax;
    }

    fn parseModel(self: *Parser) ParseError!PrismaModel {
        _ = try self.consume(.model, "Expected 'model'");

        const name_token = try self.consume(.identifier, "Expected model name");
        const model_name = name_token.lexeme;
        _ = try self.consume(.left_brace, "Expected '{'");

        var model = try PrismaModel.init(self.allocator, model_name);

        while (!self.match(.right_brace)) {
            if (self.match(.newline)) {
                continue;
            }

            if (self.current_token.type == .eof) {
                std.log.err("Unexpected end of file in model definition", .{});
                return ParseError.InvalidSyntax;
            }

            // Parse model attributes (@@map, etc.) or fields
            if (self.current_token.type == .at_symbol and self.lexer.peek() == '@') {
                // Model attribute (@@something)
                self.advance(); // consume first @
                self.advance(); // consume second @

                const attr_name = try self.consume(.identifier, "Expected attribute name");

                if (std.mem.eql(u8, attr_name.lexeme, "map")) {
                    _ = try self.consume(.left_paren, "Expected '('");
                    const table_name_token = try self.consume(.string_literal, "Expected table name");
                    _ = try self.consume(.right_paren, "Expected ')'");

                    // Remove quotes from string literal
                    const table_name = table_name_token.lexeme[1 .. table_name_token.lexeme.len - 1];
                    model.table_name = table_name; 
                }

                // Skip to next line
                while (!self.isAtEnd() and !self.match(.newline)) {
                    self.advance();
                }
            } else {
                // Field definition
                const field = try self.parseField();
                try model.addField(field);
            }
        }

        return model;
    }

    fn parseField(self: *Parser) ParseError!Field {
        const field_name_token = try self.consume(.identifier, "Expected field name");
        const field_name = field_name_token.lexeme; 

        const type_token = try self.consume(.identifier, "Expected field type");
        const field_type = FieldType.fromString(type_token.lexeme) orelse {
            std.log.err("Unknown field type: {s} at line {d}", .{ type_token.lexeme, type_token.line });
            return ParseError.UnknownFieldType;
        };

        var field = try Field.init(self.allocator, field_name, field_type);

        // Check for optional marker
        if (self.match(.question_mark)) {
            field.optional = true;
        }

        // Parse attributes
        while (self.current_token.type == .at_symbol) {
            const attr = try self.parseAttribute();
            try field.attributes.append(self.allocator, attr);
        }

        // Skip to next line or end of model
        while (!self.isAtEnd() and self.current_token.type != .newline and self.current_token.type != .right_brace) {
            self.advance();
        }
        if (self.current_token.type == .newline) {
            self.advance();
        }

        return field;
    }

    fn parseAttribute(self: *Parser) ParseError!FieldAttribute {
        _ = try self.consume(.at_symbol, "Expected '@'");

        const attr_name_token = try self.consume(.identifier, "Expected attribute name");
        const attr_name = attr_name_token.lexeme;

        if (std.mem.eql(u8, attr_name, "id")) {
            return .id;
        } else if (std.mem.eql(u8, attr_name, "unique")) {
            return .unique;
        } else if (std.mem.eql(u8, attr_name, "default")) {
            _ = try self.consume(.left_paren, "Expected '('");

            var value: []const u8 = undefined;
            if (self.current_token.type == .string_literal) {
                const token = self.current_token;
                self.advance();
                // Remove quotes
                value = token.lexeme[1 .. token.lexeme.len - 1];
            } else if (self.current_token.type == .number_literal) {
                const token = self.current_token;
                self.advance();
                value = token.lexeme;
            } else if (self.current_token.type == .identifier) {
                // Function call like autoincrement(), now(), etc.
                const token = self.current_token;
                self.advance();
                if (self.match(.left_paren)) {
                    _ = try self.consume(.right_paren, "Expected ')'");
                    value = try std.fmt.allocPrint(self.allocator, "{s}()", .{token.lexeme});
                } else {
                    value = token.lexeme;
                }
            } else {
                return ParseError.InvalidDefaultValue;
            }

            _ = try self.consume(.right_paren, "Expected ')'");
            return FieldAttribute.initDefault(self.allocator, value);
        } else if (std.mem.eql(u8, attr_name, "map")) {
            _ = try self.consume(.left_paren, "Expected '('");
            const map_name_token = try self.consume(.string_literal, "Expected column name");
            _ = try self.consume(.right_paren, "Expected ')'");

            // Remove quotes
            const map_name = map_name_token.lexeme[1 .. map_name_token.lexeme.len - 1];
            return FieldAttribute.initMap(self.allocator, map_name);
        } else {
            std.log.err("Unknown attribute: {s} at line {d}", .{ attr_name, attr_name_token.line });
            return ParseError.UnknownAttribute;
        }
    }

    fn parseGenerator(self: *Parser) ParseError!GeneratorConfig {
        _ = try self.consume(.generator, "Expected 'generator'");
        _ = try self.consume(.identifier, "Expected generator name");
        _ = try self.consume(.left_brace, "Expected '{'");

        var config = GeneratorConfig{
            .provider = "",
            .output = "",
            .allocator = self.allocator,
        };

        while (!self.match(.right_brace)) {
            if (self.match(.newline)) {
                continue;
            }

            const key_token = try self.consume(.identifier, "Expected configuration key");
            _ = try self.consume(.equals, "Expected '='");
            const value_token = try self.consume(.string_literal, "Expected configuration value");

            const key = key_token.lexeme;
            const value = value_token.lexeme[1 .. value_token.lexeme.len - 1]; // Remove quotes

            if (std.mem.eql(u8, key, "provider")) {
                config.provider = value;
            } else if (std.mem.eql(u8, key, "output")) {
                config.output = value;
            }

            // Skip to next line
            while (!self.isAtEnd() and !self.match(.newline) and self.current_token.type != .right_brace) {
                self.advance();
            }
        }

        return GeneratorConfig.init(self.allocator, config.provider, config.output);
    }

    fn parseDatasource(self: *Parser) ParseError!DatasourceConfig {
        _ = try self.consume(.datasource, "Expected 'datasource'");
        _ = try self.consume(.identifier, "Expected datasource name");
        _ = try self.consume(.left_brace, "Expected '{'");

        var config = DatasourceConfig{
            .provider = "",
            .url = "",
            .allocator = self.allocator,
        };

        while (!self.match(.right_brace)) {
            if (self.match(.newline)) {
                continue;
            }

            const key_token = try self.consume(.identifier, "Expected configuration key");
            _ = try self.consume(.equals, "Expected '='");
            const value_token = try self.consume(.string_literal, "Expected configuration value");

            const key = key_token.lexeme;
            const value = value_token.lexeme[1 .. value_token.lexeme.len - 1]; // Remove quotes

            if (std.mem.eql(u8, key, "provider")) {
                config.provider = value;
            } else if (std.mem.eql(u8, key, "url")) {
                config.url = value;
            }

            // Skip to next line
            while (!self.isAtEnd() and !self.match(.newline) and self.current_token.type != .right_brace) {
                self.advance();
            }
        }

        return DatasourceConfig.init(self.allocator, config.provider, config.url);
    }
};

/// Main parsing function - parses a Prisma schema file
pub fn parseSchema(allocator: std.mem.Allocator, source: []const u8) ParseError!Schema {
    var parser = Parser.init(allocator, source);
    return parser.parse();
}

// Tests
test "lexer tokenization" {
    const source =
        \\model User {
        \\  id   Int    @id
        \\  name String?
        \\}
    ;

    var lexer = Lexer.init(source);

    var token = lexer.nextToken();
    try std.testing.expect(token.type == .model);

    token = lexer.nextToken();
    try std.testing.expect(token.type == .identifier);
    try std.testing.expectEqualStrings("User", token.lexeme);

    token = lexer.nextToken();
    try std.testing.expect(token.type == .left_brace);
}

test "parse simple model" {
    const allocator = std.testing.allocator;

    const source =
        \\model User {
        \\  id   Int    @id
        \\  name String
        \\  email String @unique
        \\}
    ;

    var schema = try parseSchema(allocator, source);
    defer schema.deinit();

    try std.testing.expect(schema.models.items.len == 1);

    const user_model = &schema.models.items[0];
    try std.testing.expectEqualStrings("User", user_model.name);
    try std.testing.expect(user_model.fields.items.len == 3);

    const id_field = &user_model.fields.items[0];
    try std.testing.expectEqualStrings("id", id_field.name);
    try std.testing.expect(id_field.type == .int);
    try std.testing.expect(id_field.hasAttribute(.id));

    const email_field = &user_model.fields.items[2];
    try std.testing.expectEqualStrings("email", email_field.name);
    try std.testing.expect(email_field.hasAttribute(.unique));
}

test "parse model with optional fields and defaults" {
    const allocator = std.testing.allocator;

    const source =
        \\model Post {
        \\  id        Int      @id
        \\  title     String
        \\  content   String?
        \\  published Boolean  @default(false)
        \\  createdAt DateTime @default(now())
        \\}
    ;

    var schema = try parseSchema(allocator, source);
    defer schema.deinit();

    const post_model = &schema.models.items[0];

    const content_field = &post_model.fields.items[2];
    try std.testing.expect(content_field.optional);

    const published_field = &post_model.fields.items[3];
    try std.testing.expect(published_field.hasAttribute(.default));
    const default_val = published_field.getDefaultValue().?;
    try std.testing.expectEqualStrings("false", default_val);

    const created_field = &post_model.fields.items[4];
    const created_default = created_field.getDefaultValue().?;
    try std.testing.expectEqualStrings("now()", created_default);
}
