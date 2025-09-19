const std = @import("std");
const common = @import("common.zig");

const bss = @extern([*]u8, .{ .name = "__bss" });
const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
const stack_top = @extern([*]u8, .{ .name = "__stack_top" });

export fn kernelMain() noreturn {
    const bss_size = bss_end - bss;
    @memset(bss[0..bss_size], 0);

    common.printf("\nHello %s\n", .{"World"}) catch {};
    common.printf("1 + 2 = %d, %x\n", .{ 1 + 2, 0x1234abcd }) catch {};

    while (true) asm volatile ("wfi");
}

export fn boot() linksection(".text.boot") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top]
        \\j kernelMain
        :
        : [stack_top] "r" (stack_top),
    );
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
