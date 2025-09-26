const std = @import("std");

pub const Console = struct {
    putChar: *const fn (u8) anyerror!void,
    getChar: *const fn () anyerror!u8,
    writer: std.Io.Writer,
    reader: std.Io.Reader,

    pub fn init(putChar: *const fn (u8) anyerror!void, getChar: *const fn () anyerror!u8, read_buffer: []u8) Console {
        return .{
            .putChar = putChar,
            .getChar = getChar,
            .writer = .{
                .buffer = &.{},
                .vtable = &.{ .drain = drain },
            },
            .reader = .{
                .buffer = read_buffer,
                .vtable = &.{ .stream = stream },
                .seek = 0,
                .end = 0,
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

fn stream(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
    const console: *Console = @fieldParentPtr("reader", r);

    const dest = limit.slice(try w.writableSliceGreedy(1));
    dest[0] = console.getChar() catch return error.ReadFailed;
    w.advance(1);

    return 1;
}
