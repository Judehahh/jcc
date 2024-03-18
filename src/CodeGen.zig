const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const CodeGen = @This();

const Error = Allocator.Error;

Depth: usize = 0,
tree: Ast,
tmp_buf: [64]u8 = undefined,
asm_buf: std.ArrayList(u8),
vars: std.ArrayList([]const u8), // store local variables within a block

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

/// Align "N" to integer multiple of "Align".
fn alignTo(T: type, N: T, Align: T) T {
    return (N + Align - 1) / Align * Align;
}

// Generate risc-v asm code.
pub fn genAsm(tree: Ast, gpa: std.mem.Allocator) Error!void {
    std.debug.print("  .globl main\n", .{});
    std.debug.print("main:\n", .{});

    // Stack Layout
    //-------------------------------// sp
    //              fp
    //-------------------------------// fp = sp - 8
    //             Variable
    //-------------------------------// sp = sp - 8 - StackSize
    //             Expr
    //-------------------------------//

    // Prologue
    std.debug.print("  addi sp, sp, -8\n", .{});
    std.debug.print("  sd fp, 0(sp)\n", .{});
    std.debug.print("  mv fp, sp\n", .{});

    var cg: CodeGen = .{
        .Depth = 0,
        .tree = tree,
        .asm_buf = std.ArrayList(u8).init(gpa),
        .vars = std.ArrayList([]const u8).init(gpa),
    };
    defer cg.asm_buf.deinit();
    defer cg.vars.deinit();

    // Generate asm code for stmts into asm_buf, but write to stdout later.
    cg.genStmt(cg.getData(0).stmt.lhs);
    std.debug.assert(cg.Depth == 0);

    // Prepare stack size for local variables.
    const stackSize = alignTo(Node.Index, cg.vars.items.len * 8, 16);
    std.debug.print("  addi sp, sp, -{d}\n", .{stackSize});

    // Write asm code for stmts to stdout now.
    const owned_asm = try cg.asm_buf.toOwnedSlice();
    defer gpa.free(owned_asm);
    std.debug.print("{s}", .{owned_asm});

    // Epilogue
    std.debug.print(".L.return:\n", .{});
    std.debug.print("  mv sp, fp\n", .{});
    std.debug.print("  ld fp, 0(sp)\n", .{});
    std.debug.print("  addi sp, sp, 8\n", .{});
    std.debug.print("  ret\n", .{});
}

fn genStmt(cg: *CodeGen, node: Node.Index) void {
    switch (cg.getTag(node)) {
        .compound_stmt => {
            var stmt = cg.getData(node).stmt.lhs; // get the first stmt in the block
            while (stmt != 0) : (stmt = cg.getData(stmt).stmt.next) {
                cg.genStmt(stmt);
            }
            return;
        },
        .expr_stmt => {
            cg.genExpr(cg.getData(node).stmt.lhs);
            return;
        },
        .return_stmt => {
            cg.genExpr(cg.getData(node).stmt.lhs);
            cg.print("  j .L.return\n", .{}); // unconditional jump to return lable
            return;
        },
        else => {},
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

/// Generate an address for a variable node into "a0".
fn genAddr(cg: *CodeGen, node: Node.Index) void {
    if (cg.getTag(node) != .@"var") @panic("not an lvalue");

    const name = cg.getStr(node);

    // Allocate 8 bytes per variable.
    const offset = 8 * for (cg.vars.items, 0..) |item, index| {
        if (std.mem.eql(u8, item, name)) break index + 1;
    } else blk: {
        cg.vars.append(name) catch @panic("append vars failed");
        break :blk cg.vars.items.len;
    };

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
