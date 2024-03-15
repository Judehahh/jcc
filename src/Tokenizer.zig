const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Index = usize;

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.ComptimeStringMap(Tag, .{
        .{ "int", .keyword_int },
        .{ "return", .keyword_return },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        invalid,
        identifier,
        eof,
        bang,
        equal,
        equal_equal,
        bang_equal,
        plus,
        minus,
        asterisk,
        slash,
        l_paren,
        r_paren,
        semicolon,
        l_brace,
        r_brace,
        number_literal,
        angle_bracket_left,
        angle_bracket_left_equal,
        angle_bracket_right,
        angle_bracket_right_equal,

        keyword_int,
        keyword_return,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .identifier,
                .eof,
                .number_literal,
                => null,

                .bang => "!",
                .equal => "=",
                .equal_equal => "==",
                .bang_equal => "!=",
                .plus => "+",
                .minus => "-",
                .asterisk => "*",
                .slash => "/",
                .l_paren => "(",
                .r_paren => ")",
                .semicolon => ";",
                .l_brace => "{",
                .r_brace => "}",
                .angle_bracket_left => "<",
                .angle_bracket_left_equal => "<=",
                .angle_bracket_right => ">",
                .angle_bracket_right_equal => ">=",

                .keyword_int => "int",
                .keyword_return => "return",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid bytes",
                .identifier => "an identifier",
                .eof => "EOF",
                .number_literal => "a number literal",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = @This();

buffer: [:0]const u8,
index: usize,

/// For debugging purposes
pub fn dump(self: *Tokenizer, token: *const Token) void {
    std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
}

pub fn init(buffer: [:0]const u8) Tokenizer {
    // Skip the UTF-8 BOM if present
    const src_start: usize = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0;
    return Tokenizer{
        .buffer = buffer,
        .index = src_start,
    };
}

pub fn next(self: *Tokenizer) Token {
    var state: enum {
        start,
        identifier,
        equal,
        bang,
        int,
        angle_bracket_left,
        angle_bracket_right,
    } = .start;

    var result = Token{
        .tag = .eof,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    while (true) : (self.index += 1) {
        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                0 => {
                    if (self.index != self.buffer.len) {
                        result.tag = .invalid;
                        result.loc.start = self.index;
                        self.index += 1;
                        result.loc.end = self.index;
                        return result;
                    }
                    break;
                },
                ' ', '\n', '\t', '\r' => {
                    result.loc.start = self.index + 1;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    state = .identifier;
                    result.tag = .identifier;
                },
                '=' => {
                    state = .equal;
                },
                '!' => {
                    state = .bang;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                    break;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                    break;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                    break;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                    break;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                    break;
                },
                '0'...'9' => {
                    state = .int;
                    result.tag = .number_literal;
                },
                '+' => {
                    result.tag = .plus;
                    self.index += 1;
                    break;
                },
                '-' => {
                    result.tag = .minus;
                    self.index += 1;
                    break;
                },
                '*' => {
                    result.tag = .asterisk;
                    self.index += 1;
                    break;
                },
                '/' => {
                    result.tag = .slash;
                    self.index += 1;
                    break;
                },
                '<' => {
                    state = .angle_bracket_left;
                },
                '>' => {
                    state = .angle_bracket_right;
                },
                else => {
                    result.tag = .invalid;
                    result.loc.end = self.index;
                    self.index += 1;
                    return result;
                },
            },
            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => {
                    if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                        result.tag = tag;
                    }
                    break;
                },
            },
            .equal => switch (c) {
                '=' => {
                    result.tag = .equal_equal;
                    self.index += 1;
                    break;
                },
                else => {
                    result.tag = .equal;
                    break;
                },
            },
            .bang => switch (c) {
                '=' => {
                    result.tag = .bang_equal;
                    self.index += 1;
                    break;
                },
                else => {
                    result.tag = .bang;
                    break;
                },
            },
            .angle_bracket_left => switch (c) {
                '=' => {
                    result.tag = .angle_bracket_left_equal;
                    self.index += 1;
                    break;
                },
                else => {
                    result.tag = .angle_bracket_left;
                    break;
                },
            },
            .angle_bracket_right => switch (c) {
                '=' => {
                    result.tag = .angle_bracket_right_equal;
                    self.index += 1;
                    break;
                },
                else => {
                    result.tag = .angle_bracket_right;
                    break;
                },
            },
            .int => switch (c) {
                '0'...'9' => {},
                else => break,
            },
        }
    }

    if (result.tag == .eof) {
        result.loc.start = self.index;
    }

    result.loc.end = self.index;
    return result;
}
