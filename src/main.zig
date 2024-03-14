const std = @import("std");

pub fn main() !void {
    const argv = std.os.argv;
    if (argv.len != 2) {
        const err = std.io.getStdErr().writer();
        try err.print("{s}: invalid number of arguments\n", .{argv[0]});
        std.os.exit(1);
    }
    const number = try std.fmt.parseInt(i64, std.mem.span(argv[1]), 10);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("  .globl main\n", .{});
    try stdout.print("main:\n", .{});
    try stdout.print("  li a0, {d}\n", .{number});
    try stdout.print("  ret\n", .{});

    try bw.flush();
}
