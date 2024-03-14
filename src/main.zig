const std = @import("std");
const Ast = @import("Ast.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    if (std.os.argv.len != 2) @panic("Usage: jcc file");

    const file = std.fs.cwd().openFile(std.mem.span(std.os.argv[1]), .{ .mode = .read_only }) catch {
        std.debug.panic("Can not open {s}\n", .{std.os.argv[1]});
    };
    defer file.close();

    // Use readToEndAllocOptions() to add an sentinel "0" at the end of the source.
    const source = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer allocator.free(source);

    var tree = try Ast.parse(allocator, source);
    defer tree.deinit(allocator);

    try tree.dump(tree.root);
    std.debug.print("\n", .{});
}
