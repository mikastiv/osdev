const user = @import("user.zig");
comptime {
    _ = user.start;
}

pub fn main() void {
    while (true) asm volatile ("");
}
