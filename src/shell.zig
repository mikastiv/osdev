const user = @import("user.zig");
const common = @import("common.zig");

comptime {
    _ = user.start;
}

var console: common.Console = .init(&user.putChar);

pub fn main() void {
    console.writer.print("Hello World from shell!\n", .{}) catch {};
}
