const std = @import("std");
const Ast = @import("Ast.zig");
const Node = Ast.Node;

var Depth: usize = 0;

pub fn genAsm(tree: Ast) void {
    std.debug.print("  .globl main\n", .{});
    std.debug.print("main:\n", .{});
    genExpr(tree, tree.root);
    std.debug.print("  ret\n", .{});
    std.debug.assert(Depth == 0);
}

fn genExpr(tree: Ast, node: Node.Index) void {
    switch (tree.nodes.items(.tag)[node]) {
        .negation => {
            genExpr(tree, tree.nodes.items(.data)[node].lhs);
            std.debug.print("  neg a0, a0\n", .{});
            return;
        },
        .number_literal => {
            const num_token = tree.nodes.items(.main_token)[node];
            const start = tree.tokens.items(.start)[num_token];
            const end = tree.tokens.items(.end)[num_token];
            const number = std.fmt.parseInt(u32, tree.souce[start..end], 10) catch unreachable;
            std.debug.print("  li a0, {d}\n", .{number});
            return;
        },
        else => {},
    }

    genExpr(tree, tree.nodes.items(.data)[node].rhs);
    push();
    genExpr(tree, tree.nodes.items(.data)[node].lhs);
    pop("a1");

    switch (tree.nodes.items(.tag)[node]) {
        .add => std.debug.print("  add a0, a0, a1\n", .{}),
        .sub => std.debug.print("  sub a0, a0, a1\n", .{}),
        .mul => std.debug.print("  mul a0, a0, a1\n", .{}),
        .div => std.debug.print("  div a0, a0, a1\n", .{}),
        else => @panic("invalid expression"),
    }
}

fn push() void {
    std.debug.print("  addi sp, sp, -8\n", .{});
    std.debug.print("  sw a0, 0(sp)\n", .{});
    Depth += 1;
}

fn pop(reg: []const u8) void {
    std.debug.print("  lw {s}, 0(sp)\n", .{reg});
    std.debug.print("  addi sp, sp, 8\n", .{});
    Depth -= 1;
}
