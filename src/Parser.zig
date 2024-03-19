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

/// Root -> compoundStmt -> compoundStmt -> ...
pub fn parseRoot(p: *Parser) !void {
    _ = try p.addNode(.{
        .tag = .root,
        .main_token = 0,
        .data = .{ .stmt = undefined },
    });

    // const first_stmt = try p.stmt();
    // var cur_stmt = first_stmt;
    // while (p.eatToken(.eof) == null) {
    //     const next_stmt = try p.stmt();
    //     p.nodes.items(.data)[cur_stmt].stmt.next = next_stmt;
    //     cur_stmt = next_stmt;
    // }
    const first_block = try p.compoundStmt();
    p.nodes.items(.data)[0].stmt.lhs = first_block;
}

/// compoundStmt
///  : '{' Stmt? '}'
fn compoundStmt(p: *Parser) Error!Node.Index {
    const l_brace = p.eatToken(.l_brace) orelse return Error.ParseError;

    const first_stmt = try p.stmt();
    var cur_stmt = first_stmt;
    while (p.eatToken(.r_brace) == null) {
        const next_stmt = try p.stmt();
        p.nodes.items(.data)[cur_stmt].setNext(next_stmt);
        cur_stmt = next_stmt;
    }

    return try p.addNode(.{
        .tag = .compound_stmt,
        .main_token = l_brace,
        .data = .{ .stmt = .{ .lhs = first_stmt } },
    });
}

/// Stmt
///  : exprStmt
///  | KEYWORD_if '(' Expr ')' stmt (KEYWORD_else stmt)?
///  | KEYWORD_for '(' exprStmt Expr? ';' Expr? ')' stmt
///  | KEYWORD_while '(' Expr ')' stmt
///  | KEYWORD_return Expr? ';'
///  | '{' compoundStmt
pub fn stmt(p: *Parser) Error!Node.Index {
    switch (p.tok_tags[p.tok_i]) {
        .keyword_return => {
            const result = p.addNode(.{
                .tag = .return_stmt,
                .main_token = p.nextToken(),
                .data = .{
                    .stmt = .{ .lhs = try p.expr() },
                },
            });
            _ = p.eatToken(.semicolon) orelse return Error.ParseError;
            return result;
        },
        .keyword_if => {
            const result = try p.addNode(.{
                .tag = .if_then_stmt,
                .main_token = p.nextToken(),
                .data = .{ .ifs = undefined },
            });

            _ = p.eatToken(.l_paren) orelse return Error.ParseError;
            const cond = try p.expr();
            p.nodes.items(.data)[result].ifs.cond = cond;
            _ = p.eatToken(.r_paren) orelse return Error.ParseError;

            const then = try p.stmt();
            p.nodes.items(.data)[result].ifs.then = then;

            if (p.eatToken(.keyword_else) != null) {
                p.nodes.items(.tag)[result] = .if_then_else_stmt;
                const els = try p.stmt();
                p.nodes.items(.data)[result].ifs.els = els;
            }

            return result;
        },
        .keyword_for => {
            const result = try p.addNode(.{
                .tag = .for_stmt,
                .main_token = p.nextToken(),
                .data = .{ .fors = undefined },
            });

            _ = p.eatToken(.l_paren) orelse return Error.ParseError;
            const init = try p.exprStmt();
            p.nodes.items(.data)[result].fors.init = init;
            // The first semicolon is eaten by exprStmt().
            if (p.eatToken(.semicolon) == null) {
                const cond = try p.expr();
                p.nodes.items(.data)[result].fors.cond = cond;
                _ = p.eatToken(.semicolon) orelse return Error.ParseError;
            }
            if (p.eatToken(.r_paren) == null) {
                const inc = try p.expr();
                p.nodes.items(.data)[result].fors.inc = inc;
                _ = p.eatToken(.r_paren) orelse return Error.ParseError;
            }

            const then = try p.stmt();
            p.nodes.items(.data)[result].fors.then = then;

            return result;
        },
        .keyword_while => {
            const result = try p.addNode(.{
                .tag = .while_stmt,
                .main_token = p.nextToken(),
                .data = .{ .ifs = undefined },
            });

            _ = p.eatToken(.l_paren) orelse return Error.ParseError;
            const cond = try p.expr();
            p.nodes.items(.data)[result].ifs.cond = cond;
            _ = p.eatToken(.r_paren) orelse return Error.ParseError;

            const then = try p.stmt();
            p.nodes.items(.data)[result].ifs.then = then;

            return result;
        },
        .l_brace => return p.compoundStmt(),
        else => {},
    }
    return p.exprStmt();
}

/// exprStmt
///  : Expr? ';'
fn exprStmt(p: *Parser) Error!Node.Index {
    if (p.eatToken(.semicolon)) |token| {
        return p.addNode(.{
            .tag = .compound_stmt,
            .main_token = token,
            .data = .{ .stmt = undefined },
        });
    }

    const result = p.addNode(.{
        .tag = .expr_stmt,
        .main_token = 0,
        .data = .{ .stmt = .{ .lhs = try p.expr() } },
    });
    _ = p.eatToken(.semicolon) orelse return Error.ParseError;
    return result;
}

/// Expr : Assign
fn expr(p: *Parser) Error!Node.Index {
    return p.assign();
}

/// Assign
///  : Equation ('=' Assign)?
fn assign(p: *Parser) Error!Node.Index {
    var result = try p.equation();

    if (p.tok_tags[p.tok_i] == .equal) {
        result = try p.addNode(.{
            .tag = .assign_expr,
            .main_token = p.nextToken(),
            .data = .{ .bin = .{
                .lhs = result,
                .rhs = try p.assign(),
            } },
        });
    }

    return result;
}

/// Equation
///  : Relation
///  | Relation '==' Relation
///  | Relation '!=' Relation
fn equation(p: *Parser) Error!Node.Index {
    var result = try p.relation();

    while (true) {
        switch (p.tok_tags[p.tok_i]) {
            .equal_equal => result = try p.addNode(.{
                .tag = .equal_equal,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.relation(),
                } },
            }),
            .bang_equal => result = try p.addNode(.{
                .tag = .bang_equal,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.relation(),
                } },
            }),
            else => return result,
        }
    }
}

/// Relation
///  : Add
///  | Add '<' Add
///  | Add '<=' Add
///  | Add '>' Add
///  | Add '>=' Add
fn relation(p: *Parser) Error!Node.Index {
    var result = try p.add();

    while (true) {
        switch (p.tok_tags[p.tok_i]) {
            .angle_bracket_left => result = try p.addNode(.{
                .tag = .less_than,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.add(),
                } },
            }),
            .angle_bracket_left_equal => result = try p.addNode(.{
                .tag = .less_or_equal,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.add(),
                } },
            }),
            // Also set tag as less_than for '>' but swap lhs and rhs.
            .angle_bracket_right => result = try p.addNode(.{
                .tag = .less_than,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = try p.add(),
                    .rhs = result,
                } },
            }),
            .angle_bracket_right_equal => result = try p.addNode(.{
                .tag = .less_or_equal,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = try p.add(),
                    .rhs = result,
                } },
            }),
            else => return result,
        }
    }
}

/// Add
///  : Mul
///  | Mul '+' Mul
///  | Mul '-' Mul
fn add(p: *Parser) Error!Node.Index {
    var result = try p.mul();

    while (true) {
        switch (p.tok_tags[p.tok_i]) {
            .plus => result = try p.addNode(.{
                .tag = .add,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.mul(),
                } },
            }),
            .minus => result = try p.addNode(.{
                .tag = .sub,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.mul(),
                } },
            }),
            else => return result,
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
            .asterisk => result = try p.addNode(.{
                .tag = .mul,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.unary(),
                } },
            }),
            .slash => result = try p.addNode(.{
                .tag = .div,
                .main_token = p.nextToken(),
                .data = .{ .bin = .{
                    .lhs = result,
                    .rhs = try p.unary(),
                } },
            }),
            else => return result,
        }
    }
}

/// Unary
///  : Primary
///  | '+' Unary
///  | '-' Unary
fn unary(p: *Parser) Error!Node.Index {
    switch (p.tok_tags[p.tok_i]) {
        .plus => {
            _ = p.eatToken(.plus);
            return p.unary();
        },
        .minus => return p.addNode(.{
            .tag = .negation,
            .main_token = p.nextToken(),
            .data = .{ .un = try p.unary() },
        }),
        else => return p.primary(),
    }
}

/// Primary
///  : NUM_LIT
///  | IDENT
///  | '(' Expr ')'
fn primary(p: *Parser) Error!Node.Index {
    switch (p.tok_tags[p.tok_i]) {
        .number_literal => return p.addNode(.{
            .tag = .number_literal,
            .main_token = p.nextToken(),
            .data = undefined,
        }),
        .identifier => return p.addNode(.{
            .tag = .@"var",
            .main_token = p.nextToken(),
            .data = undefined,
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
