const stack_top = @extern([*]u8, .{ .name = "__stack_top" });
const root = @import("root");

fn exit() noreturn {
    while (true) asm volatile ("");
}

pub fn putChar(char: u8) void {
    _ = char;
}

pub export fn start() linksection(".text.start") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[stack_top]
        \\call %[main]
        \\call %[exit]
        :
        : [stack_top] "r" (stack_top),
          [main] "X" (&root.main),
          [exit] "X" (&exit),
    );
}
