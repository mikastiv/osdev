const std = @import("std");

pub const Console = struct {
    putChar: *const fn (u8) anyerror!void,
    writer: std.Io.Writer,

    pub fn init(putChar: *const fn (u8) anyerror!void) Console {
        return .{
            .putChar = putChar,
            .writer = .{
                .buffer = &.{},
                .vtable = &.{ .drain = drain },
            },
        };
    }
};

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    const console: *Console = @fieldParentPtr("writer", w);
    var n: usize = 0;
    if (w.end > 0) {
        for (w.buffer[0..w.end]) |char| {
            console.putChar(char) catch return error.WriteFailed;
        }
        n += w.end;
        w.end = 0;
    }

    for (data, 0..) |row, i| {
        if (i == data.len - 1) break;

        for (row) |char| {
            console.putChar(char) catch return error.WriteFailed;
        }
        n += row.len;
    }

    const pattern = data[data.len - 1];
    for (0..splat) |_| {
        for (pattern) |char| {
            console.putChar(char) catch return error.WriteFailed;
        }
        n += pattern.len;
    }

    return n;
}
