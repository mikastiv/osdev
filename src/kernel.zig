const std = @import("std");

const bss = @extern([*]u8, .{ .name = "__bss" });
const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
const stack_top = @extern([*]u8, .{ .name = "__stack_top" });

export fn boot() linksection(".text.boot") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top]
        \\j kernelMain
        :
        : [stack_top] "r" (stack_top),
    );
}

export fn kernelMain() noreturn {
    const bss_size = bss_end - bss;
    @memset(bss[0..bss_size], 0);

    while (true) asm volatile ("");
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    return_address: ?usize,
) noreturn {
    @branchHint(.cold);
    _ = msg;
    _ = error_return_trace;
    _ = return_address;
    while (true) {}
}
