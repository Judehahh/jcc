const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

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

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var tokenizer = Tokenizer.init(source);

    try stdout.print("  .globl main\n", .{});
    try stdout.print("main:\n", .{});

    while (true) {
        const tok = tokenizer.next();
        switch (tok.tag) {
            .number_literal => try stdout.print(
                "  li a0, {d}\n",
                .{try std.fmt.parseInt(
                    u32,
                    source[tok.loc.start..tok.loc.end],
                    10,
                )},
            ),
            .plus => {
                const tok_next = tokenizer.next();
                if (tok_next.tag != .number_literal) @panic("Parse error");
                try stdout.print(
                    "  addi a0, a0, {d}\n",
                    .{try std.fmt.parseInt(
                        u32,
                        source[tok_next.loc.start..tok_next.loc.end],
                        10,
                    )},
                );
            },
            .minus => {
                const tok_next = tokenizer.next();
                if (tok_next.tag != .number_literal) @panic("Parse error");
                try stdout.print(
                    "  addi a0, a0, -{d}\n",
                    .{try std.fmt.parseInt(
                        u32,
                        source[tok_next.loc.start..tok_next.loc.end],
                        10,
                    )},
                );
            },
            .eof => break,
            else => @panic("TODO: parse more tags"),
        }
    }

    try stdout.print("  ret\n", .{});
    try bw.flush();
}
