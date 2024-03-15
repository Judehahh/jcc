const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Tokenizer.zig").Token;
const Parser = @import("Parser.zig");

const Ast = @This();

souce: [:0]const u8,
tokens: TokenList.Slice,
nodes: NodeList.Slice,
root: Node.Index,

pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: Token.Index,
    end: Token.Index,
});
pub const NodeList = std.MultiArrayList(Node);

pub fn deinit(tree: *Ast, gpa: Allocator) void {
    tree.nodes.deinit(gpa);
    tree.tokens.deinit(gpa);
    tree.* = undefined;
}

pub fn parse(gpa: std.mem.Allocator, source: [:0]const u8) !Ast {
    var tokens = Ast.TokenList{};
    defer tokens.deinit(gpa);

    const estimated_token_count = source.len / 8;
    try tokens.ensureTotalCapacity(gpa, estimated_token_count);

    var tokenizer = Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, .{
            .tag = token.tag,
            .start = token.loc.start,
            .end = token.loc.end,
        });
        if (token.tag == .eof) break;
    }

    var parser: Parser = .{
        .gpa = gpa,
        .source = source,
        .tok_tags = tokens.items(.tag),
        .tok_i = 0,
        .nodes = .{},
    };
    defer parser.nodes.deinit(gpa);

    const root = try parser.expr();

    return Ast{
        .souce = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .root = root,
    };
}

pub const Node = struct {
    /// node type
    tag: Tag,
    main_token: Token.Index,
    /// index of lhs and rhs
    data: Data,

    pub const Index = usize;

    pub const Tag = enum {
        /// lhs + rhs
        add,
        /// lhs - rhs,
        sub,
        /// lhs * rhs
        mul,
        /// lhs / rhs,
        div,
        /// -un
        negation,
        /// lhs and rhs both unused
        number_literal,
        /// lhs == rhs
        equal_equal,
        /// lhs != rhs
        bang_equal,
        /// lhs < rhs, rhs > lhs
        less_than,
        /// lhs <= rhs, rhs >= lhs
        less_or_equal,
    };

    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };
};

pub fn dump(tree: *Ast, node: Node.Index) !void {
    if (tree.nodes.items(.tag)[node] == .number_literal) {
        const num_token = tree.nodes.items(.main_token)[node];
        const start = tree.tokens.items(.start)[num_token];
        const end = tree.tokens.items(.end)[num_token];
        const number = try std.fmt.parseInt(u32, tree.souce[start..end], 10);
        std.debug.print("{d} ", .{number});
        return;
    }
    try tree.dump(tree.nodes.items(.data)[node].rhs);
    std.debug.print("{s} ", .{@tagName(tree.nodes.items(.tag)[node])});
    try tree.dump(tree.nodes.items(.data)[node].lhs);
}
