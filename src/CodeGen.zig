const std = @import("std");
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const CodeGen = @This();

Depth: usize = 0,
tree: Ast,

fn getTag(cg: *CodeGen, node: Node.Index) Node.Tag {
    return cg.tree.nodes.items(.tag)[node];
}

fn getData(cg: *CodeGen, node: Node.Index) Node.Data {
    return cg.tree.nodes.items(.data)[node];
}

pub fn genAsm(tree: Ast) void {
    std.debug.print("  .globl main\n", .{});
    std.debug.print("main:\n", .{});

    var cg: CodeGen = .{
        .Depth = 0,
        .tree = tree,
    };

    var stmt = cg.getData(0).next;
    while (stmt != 0) : (stmt = cg.getData(stmt).next) {
        cg.genStmt(stmt);
        std.debug.assert(cg.Depth == 0);
    }

    std.debug.print("  ret\n", .{});
}

fn genStmt(cg: *CodeGen, node: Node.Index) void {
    if (cg.getTag(node) == .expr_stmt) {
        cg.genExpr(cg.getData(node).lhs);
        return;
    }
    @panic("invalid expression");
}

fn genExpr(cg: *CodeGen, node: Node.Index) void {
    switch (cg.getTag(node)) {
        .negation => {
            cg.genExpr(cg.getData(node).lhs);
            std.debug.print("  neg a0, a0\n", .{});
            return;
        },
        .number_literal => {
            const num_token = cg.tree.nodes.items(.main_token)[node];
            const start = cg.tree.tokens.items(.start)[num_token];
            const end = cg.tree.tokens.items(.end)[num_token];
            const number = std.fmt.parseInt(u32, cg.tree.souce[start..end], 10) catch unreachable;
            std.debug.print("  li a0, {d}\n", .{number});
            return;
        },
        else => {},
    }

    cg.genExpr(cg.getData(node).rhs);
    cg.push();
    cg.genExpr(cg.getData(node).lhs);
    cg.pop("a1");

    switch (cg.getTag(node)) {
        .add => std.debug.print("  add a0, a0, a1\n", .{}),
        .sub => std.debug.print("  sub a0, a0, a1\n", .{}),
        .mul => std.debug.print("  mul a0, a0, a1\n", .{}),
        .div => std.debug.print("  div a0, a0, a1\n", .{}),
        .equal_equal => {
            std.debug.print("  xor a0, a0, a1\n", .{});
            std.debug.print("  seqz a0, a0\n", .{});
        },
        .bang_equal => {
            std.debug.print("  xor a0, a0, a1\n", .{});
            std.debug.print("  snez a0, a0\n", .{});
        },
        .less_than => std.debug.print("  slt a0, a0, a1\n", .{}),
        .less_or_equal => {
            // a0<=a1 -> { a0=a1<a0, a0=a1^1 }
            std.debug.print("  slt a0, a1, a0\n", .{});
            std.debug.print("  xori a0, a0, 1\n", .{});
        },
        else => @panic("invalid expression"),
    }
}

fn push(cg: *CodeGen) void {
    std.debug.print("  addi sp, sp, -8\n", .{});
    std.debug.print("  sw a0, 0(sp)\n", .{});
    cg.Depth += 1;
}

fn pop(cg: *CodeGen, reg: []const u8) void {
    std.debug.print("  lw {s}, 0(sp)\n", .{reg});
    std.debug.print("  addi sp, sp, 8\n", .{});
    cg.Depth -= 1;
}
