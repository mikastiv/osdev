const std = @import("std");
const user = @import("user.zig");
const common = @import("common.zig");

comptime {
    _ = user.start;
}

var read_buffer: [128]u8 = undefined;
var console: common.Console = .init(&user.putChar, &user.getChar, &read_buffer);

pub fn main() !void {
    prompt: while (true) {
        try console.writer.writeAll("> ");
        var buffer: [256]u8 = undefined;
        var cmdline: []const u8 = &.{};
        for (0..buffer.len) |i| {
            const char = try console.reader.takeByte();
            try console.writer.writeByte(char);
            if (char == '\r') {
                try console.writer.writeByte('\n');
                cmdline = buffer[0..i];
                break;
            } else {
                buffer[i] = char;
            }
        } else {
            try console.writer.writeAll("command line too long\n");
            continue :prompt;
        }

        if (std.mem.eql(u8, cmdline, "hello")) {
            try console.writer.writeAll("Hello world from shell!\n");
        } else if (std.mem.eql(u8, cmdline, "exit")) {
            user.exit();
        } else {
            try console.writer.print("unknown command: {s}\n", .{cmdline});
        }
    }
}
