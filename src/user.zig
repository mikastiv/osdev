const std = @import("std");
const root = @import("root");
const Syscall = @import("sys.zig").Syscall;

const stack_top = @extern([*]u8, .{ .name = "__stack_top" });

pub fn exit() noreturn {
    _ = Syscall.zero(.exit) catch {};
    while (true) asm volatile ("");
}

pub fn putChar(char: u8) !void {
    _ = try Syscall.one(.putchar, char);
}

pub fn getChar() !u8 {
    return @intCast(try Syscall.zero(.getchar));
}

pub export fn start() linksection(".text.start") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[stack_top]
        \\call %[main]
        \\call %[exit]
        :
        : [stack_top] "r" (stack_top),
          [main] "X" (&callMain),
          [exit] "X" (&exit),
    );
}

fn callMain() void {
    root.main() catch |err| {
        std.debug.panic("user main error={t}", .{err});
    };
}
