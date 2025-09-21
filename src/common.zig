const std = @import("std");
const sbi = @import("sbi.zig");

pub const Console = struct {
    writer: std.Io.Writer,

    pub const init: Console = .{
        .writer = .{
            .buffer = &.{},
            .vtable = &.{ .drain = drain },
        },
    };
};

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var n: usize = 0;
    if (w.end > 0) {
        for (w.buffer[0..w.end]) |char| {
            putChar(char) catch return error.WriteFailed;
        }
        n += w.end;
        w.end = 0;
    }

    for (data, 0..) |row, i| {
        if (i == data.len - 1) break;

        for (row) |char| {
            putChar(char) catch return error.WriteFailed;
        }
        n += row.len;
    }

    const pattern = data[data.len - 1];
    for (0..splat) |_| {
        for (pattern) |char| {
            putChar(char) catch return error.WriteFailed;
        }
        n += pattern.len;
    }

    return n;
}

fn putChar(char: u8) !void {
    _ = try sbi.call(char, 0, 0, 0, 0, 0, 0, 1);
}
