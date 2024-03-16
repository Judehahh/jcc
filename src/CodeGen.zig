const std = @import("std");
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const CodeGen = @This();

Depth: usize = 0,
tree: Ast,

/// Get the nodekind of a node.
fn getTag(cg: *CodeGen, node: Node.Index) Node.Tag {
    return cg.tree.nodes.items(.tag)[node];
}

/// Get the data of a node,
/// which contains the index of lhs, rhs and the next node.
fn getData(cg: *CodeGen, node: Node.Index) Node.Data {
    return cg.tree.nodes.items(.data)[node];
}

/// Get the original string of a node.
fn getStr(cg: *CodeGen, node: Node.Index) []const u8 {
    const main_token = cg.tree.nodes.items(.main_token)[node];
    const start = cg.tree.tokens.items(.start)[main_token];
    const end = cg.tree.tokens.items(.end)[main_token];
    return cg.tree.souce[start..end];
}

pub fn genAsm(tree: Ast) void {
    std.debug.print("  .globl main\n", .{});
    std.debug.print("main:\n", .{});

    // Stack Layout
    //-------------------------------// sp
    //              fp                  fp = sp-8
    //-------------------------------// fp
    //              'a'                 fp-8
    //              'b'                 fp-16
    //              ...
    //              'z'                 fp-208
    //-------------------------------// sp=sp-8-208
    //             Expr
    //-------------------------------//

    // Prologue
    std.debug.print("  addi sp, sp, -8\n", .{});
    std.debug.print("  sd fp, 0(sp)\n", .{});
    std.debug.print("  mv fp, sp\n", .{});
    std.debug.print("  addi sp, sp, -208\n", .{});

    var cg: CodeGen = .{
        .Depth = 0,
        .tree = tree,
    };

    var stmt = cg.getData(0).next;
    while (stmt != 0) : (stmt = cg.getData(stmt).next) {
        cg.genStmt(stmt);
        std.debug.assert(cg.Depth == 0);
    }

    // Epilogue
    std.debug.print("  mv sp, fp\n", .{});
    std.debug.print("  ld fp, 0(sp)\n", .{});
    std.debug.print("  addi sp, sp, 8\n", .{});
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
            const number = std.fmt.parseInt(u32, cg.getStr(node), 10) catch unreachable;
            std.debug.print("  li a0, {d}\n", .{number});
            return;
        },
        .@"var" => {
            cg.genAddr(node);
            std.debug.print("  ld a0, 0(a0)\n", .{});
            return;
        },
        .assign_expr => {
            cg.genAddr(cg.getData(node).lhs);
            cg.push();
            cg.genExpr(cg.getData(node).rhs);
            cg.pop("a1");
            std.debug.print("  sd a0, 0(a1)\n", .{});
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

/// generate an address for a variable node
fn genAddr(cg: *CodeGen, node: Node.Index) void {
    if (cg.getTag(node) != .@"var") @panic("not an lvalue");

    const offset = (cg.getStr(node)[0] - 'a' + 1) * 8;
    std.debug.print("  addi a0, fp, -{d}\n", .{offset});
}

fn push(cg: *CodeGen) void {
    std.debug.print("  addi sp, sp, -8\n", .{});
    std.debug.print("  sd a0, 0(sp)\n", .{});
    cg.Depth += 1;
}

fn pop(cg: *CodeGen, reg: []const u8) void {
    std.debug.print("  ld {s}, 0(sp)\n", .{reg});
    std.debug.print("  addi sp, sp, 8\n", .{});
    cg.Depth -= 1;
}
