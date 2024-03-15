const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const Node = Ast.Node;
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Tokenizer.zig").Token;

const Parser = @This();

pub const Error = error{ParseError} || Allocator.Error;

gpa: Allocator,
source: [:0]const u8,
tok_tags: []const Token.Tag,
tok_i: Token.Index,
nodes: Ast.NodeList,

fn addNode(p: *Parser, elem: Ast.Node) Allocator.Error!Node.Index {
    const result = @as(Node.Index, @intCast(p.nodes.len));
    try p.nodes.append(p.gpa, elem);
    return result;
}

/// Expr
///  : Mul
///  | Mul '+' Mul
///  | Mul '-' Mul
pub fn expr(p: *Parser) Error!Node.Index {
    var result = try p.mul();

    while (true) {
        switch (p.tok_tags[p.tok_i]) {
            .plus => {
                result = try p.addNode(.{
                    .tag = .add,
                    .main_token = p.nextToken(),
                    .data = .{
                        .lhs = result,
                        .rhs = try p.mul(),
                    },
                });
            },
            .minus => {
                result = try p.addNode(.{
                    .tag = .sub,
                    .main_token = p.nextToken(),
                    .data = .{
                        .lhs = result,
                        .rhs = try p.mul(),
                    },
                });
            },
            .r_paren, .eof => return result,
            else => unreachable,
        }
    }
}

/// Mul
///  : Unary
///  | Unary '*' Unary
///  | Unary '/' Unary
fn mul(p: *Parser) !Node.Index {
    var result = try p.unary();

    while (true) {
        switch (p.tok_tags[p.tok_i]) {
            .asterisk => {
                result = try p.addNode(.{
                    .tag = .mul,
                    .main_token = p.nextToken(),
                    .data = .{
                        .lhs = result,
                        .rhs = try p.unary(),
                    },
                });
            },
            .slash => {
                result = try p.addNode(.{
                    .tag = .div,
                    .main_token = p.nextToken(),
                    .data = .{
                        .lhs = result,
                        .rhs = try p.unary(),
                    },
                });
            },
            else => return result,
        }
    }
}

fn unary(p: *Parser) Error!Node.Index {
    switch (p.tok_tags[p.tok_i]) {
        .plus => {
            _ = p.eatToken(.plus);
            return p.unary();
        },
        .minus => return p.addNode(.{
            .tag = .negation,
            .main_token = p.nextToken(),
            .data = .{
                .lhs = try p.unary(),
                .rhs = undefined,
            },
        }),
        else => return p.primary(),
    }
}

/// Primary
///  : '(' Expr ')'
///  | NUM_LIT
fn primary(p: *Parser) Error!Node.Index {
    switch (p.tok_tags[p.tok_i]) {
        .number_literal => return p.addNode(.{
            .tag = .number_literal,
            .main_token = p.nextToken(),
            .data = .{
                .lhs = undefined,
                .rhs = undefined,
            },
        }),
        .l_paren => {
            _ = p.eatToken(.l_paren);
            const result = try p.expr(); // There is another expr in parentheses
            _ = p.eatToken(.r_paren) orelse return Error.ParseError;
            return result;
        },
        else => return Error.ParseError,
    }
}

fn eatToken(p: *Parser, tag: Token.Tag) ?Token.Index {
    return if (p.tok_tags[p.tok_i] == tag) p.nextToken() else null;
}

fn nextToken(p: *Parser) Token.Index {
    const result = p.tok_i;
    p.tok_i += 1;
    return result;
}
