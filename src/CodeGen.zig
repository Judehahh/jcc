const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const CodeGen = @This();

Depth: usize = 0,
tree: Ast,
tmp_buf: [64]u8 = undefined,
asm_buf: std.ArrayList(u8),

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

/// Print asm code into the asm_buf.
fn print(cg: *CodeGen, comptime fmt: []const u8, args: anytype) void {
    const _str = std.fmt.bufPrint(&cg.tmp_buf, fmt, args) catch @panic("bufPrint error");
    cg.asm_buf.appendSlice(_str) catch @panic("appendSlice error");
}

pub fn genAsm(tree: Ast, gpa: std.mem.Allocator) !void {
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
        .asm_buf = std.ArrayList(u8).init(gpa),
    };
    defer cg.asm_buf.deinit();

    var stmt = cg.getData(0).stmt.next;
    while (stmt != 0) : (stmt = cg.getData(stmt).stmt.next) {
        cg.genStmt(stmt);
        std.debug.assert(cg.Depth == 0);
    }
    const owned_asm = try cg.asm_buf.toOwnedSlice();
    defer gpa.free(owned_asm);
    std.debug.print("{s}", .{owned_asm});

    // Epilogue
    std.debug.print("  mv sp, fp\n", .{});
    std.debug.print("  ld fp, 0(sp)\n", .{});
    std.debug.print("  addi sp, sp, 8\n", .{});
    std.debug.print("  ret\n", .{});
}

fn genStmt(cg: *CodeGen, node: Node.Index) void {
    if (cg.getTag(node) == .expr_stmt) {
        cg.genExpr(cg.getData(node).stmt.lhs);
        return;
    }
    @panic("invalid expression");
}

fn genExpr(cg: *CodeGen, node: Node.Index) void {
    switch (cg.getTag(node)) {
        .negation => {
            cg.genExpr(cg.getData(node).un);
            cg.print("  neg a0, a0\n", .{});
            return;
        },
        .number_literal => {
            const number = std.fmt.parseInt(u32, cg.getStr(node), 10) catch unreachable;
            cg.print("  li a0, {d}\n", .{number});
            return;
        },
        .@"var" => {
            cg.genAddr(node);
            cg.print("  ld a0, 0(a0)\n", .{});
            return;
        },
        .assign_expr => {
            cg.genAddr(cg.getData(node).bin.lhs);
            cg.push();
            cg.genExpr(cg.getData(node).bin.rhs);
            cg.pop("a1");
            cg.print("  sd a0, 0(a1)\n", .{});
            return;
        },
        else => {},
    }

    cg.genExpr(cg.getData(node).bin.rhs);
    cg.push();
    cg.genExpr(cg.getData(node).bin.lhs);
    cg.pop("a1");

    switch (cg.getTag(node)) {
        .add => cg.print("  add a0, a0, a1\n", .{}),
        .sub => cg.print("  sub a0, a0, a1\n", .{}),
        .mul => cg.print("  mul a0, a0, a1\n", .{}),
        .div => cg.print("  div a0, a0, a1\n", .{}),
        .equal_equal => {
            cg.print("  xor a0, a0, a1\n", .{});
            cg.print("  seqz a0, a0\n", .{});
        },
        .bang_equal => {
            cg.print("  xor a0, a0, a1\n", .{});
            cg.print("  snez a0, a0\n", .{});
        },
        .less_than => cg.print("  slt a0, a0, a1\n", .{}),
        .less_or_equal => {
            // a0<=a1 -> { a0=a1<a0, a0=a1^1 }
            cg.print("  slt a0, a1, a0\n", .{});
            cg.print("  xori a0, a0, 1\n", .{});
        },
        else => @panic("invalid expression"),
    }
}

/// generate an address for a variable node
fn genAddr(cg: *CodeGen, node: Node.Index) void {
    if (cg.getTag(node) != .@"var") @panic("not an lvalue");

    const offset = (cg.getStr(node)[0] - 'a' + 1) * 8;
    cg.print("  addi a0, fp, -{d}\n", .{offset});
}

fn push(cg: *CodeGen) void {
    cg.print("  addi sp, sp, -8\n", .{});
    cg.print("  sd a0, 0(sp)\n", .{});
    cg.Depth += 1;
}

fn pop(cg: *CodeGen, reg: []const u8) void {
    cg.print("  ld {s}, 0(sp)\n", .{reg});
    cg.print("  addi sp, sp, 8\n", .{});
    cg.Depth -= 1;
}
