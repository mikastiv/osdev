const std = @import("std");
const common = @import("common.zig");
const Csr = common.Csr;

const bss = @extern([*]u8, .{ .name = "__bss" });
const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
const stack_top = @extern([*]u8, .{ .name = "__stack_top" });

const ram_start = @extern([*]u8, .{ .name = "__free_ram_start" });
const ram_end = @extern([*]u8, .{ .name = "__free_ram_end" });
const page_size = 4 * 1024;

var console: common.Console = .init;

export fn kernelMain() noreturn {
    main() catch |err| {
        std.debug.panic("failed with: {t}", .{err});
    };

    while (true) asm volatile ("wfi");
}

fn main() !void {
    const bss_size = bss_end - bss;
    @memset(bss[0..bss_size], 0);

    Csr.write(.stvec, @intFromPtr(&kernelEntry));

    const pages0 = allocPages(2);
    const pages1 = allocPages(1);

    try console.writer.print("allocPages test: pages0={*}\n", .{pages0.ptr});
    try console.writer.print("allocPages test: pages1={*}\n", .{pages1.ptr});
}

export fn boot() linksection(".text.boot") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top]
        \\j kernelMain
        :
        : [stack_top] "r" (stack_top),
    );
}

fn allocPages(count: usize) []u8 {
    const S = struct {
        var next_ram_index: usize = 0;
    };

    const ram = ram_start[0 .. ram_end - ram_start];
    const size = count * page_size;
    if (S.next_ram_index + size > ram.len) {
        @panic("out of memory");
    }

    defer S.next_ram_index += size;
    return ram[S.next_ram_index .. S.next_ram_index + size];
}

export fn kernelEntry() align(4) callconv(.naked) void {
    asm volatile (
        \\csrw sscratch, sp
        \\addi sp, sp, -4 * 31
        \\
        \\sw ra, 4 * 0(sp)
        \\sw gp, 4 * 1(sp)
        \\sw tp, 4 * 2(sp)
        \\sw t0, 4 * 3(sp)
        \\sw t1, 4 * 4(sp)
        \\sw t2, 4 * 5(sp)
        \\sw t3, 4 * 6(sp)
        \\sw t4, 4 * 7(sp)
        \\sw t5, 4 * 8(sp)
        \\sw t6, 4 * 9(sp)
        \\sw a0, 4 * 10(sp)
        \\sw a1, 4 * 11(sp)
        \\sw a2, 4 * 12(sp)
        \\sw a3, 4 * 13(sp)
        \\sw a4, 4 * 14(sp)
        \\sw a5, 4 * 15(sp)
        \\sw a6, 4 * 16(sp)
        \\sw a7, 4 * 17(sp)
        \\sw s0, 4 * 18(sp)
        \\sw s1, 4 * 19(sp)
        \\sw s2, 4 * 20(sp)
        \\sw s3, 4 * 21(sp)
        \\sw s4, 4 * 22(sp)
        \\sw s5, 4 * 23(sp)
        \\sw s6, 4 * 24(sp)
        \\sw s7, 4 * 25(sp)
        \\sw s8, 4 * 26(sp)
        \\sw s9, 4 * 27(sp)
        \\sw s10, 4 * 28(sp)
        \\sw s11, 4 * 29(sp)
        \\
        \\csrr a0, sscratch
        \\sw a0, 4 * 30(sp)
        \\
        \\mv a0, sp
        \\call handleTrap
        \\
        \\lw ra, 4 * 0(sp)
        \\lw gp, 4 * 1(sp)
        \\lw tp, 4 * 2(sp)
        \\lw t0, 4 * 3(sp)
        \\lw t1, 4 * 4(sp)
        \\lw t2, 4 * 5(sp)
        \\lw t3, 4 * 6(sp)
        \\lw t4, 4 * 7(sp)
        \\lw t5, 4 * 8(sp)
        \\lw t6, 4 * 9(sp)
        \\lw a0, 4 * 10(sp)
        \\lw a1, 4 * 11(sp)
        \\lw a2, 4 * 12(sp)
        \\lw a3, 4 * 13(sp)
        \\lw a4, 4 * 14(sp)
        \\lw a5, 4 * 15(sp)
        \\lw a6, 4 * 16(sp)
        \\lw a7, 4 * 17(sp)
        \\lw s0, 4 * 18(sp)
        \\lw s1, 4 * 19(sp)
        \\lw s2, 4 * 20(sp)
        \\lw s3, 4 * 21(sp)
        \\lw s4, 4 * 22(sp)
        \\lw s5, 4 * 23(sp)
        \\lw s6, 4 * 24(sp)
        \\lw s7, 4 * 25(sp)
        \\lw s8, 4 * 26(sp)
        \\lw s9, 4 * 27(sp)
        \\lw s10, 4 * 28(sp)
        \\lw s11, 4 * 29(sp)
        \\lw sp, 4 * 30(sp)
        \\
        \\sret
    );
}

export fn handleTrap(frame: *common.TrapFrame) void {
    _ = frame;
    const scause = Csr.read(.scause);
    const stval = Csr.read(.stval);
    const user_pc = Csr.read(.sepc);

    std.debug.panic("unexpected trap scause={x}, stval={x}, sepc={x}", .{ scause, stval, user_pc });
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    return_address: ?usize,
) noreturn {
    @branchHint(.cold);

    _ = return_address;

    console.writer.print("PANIC: {s}\n", .{msg}) catch {};
    if (error_return_trace) |trace| {
        console.writer.print("{f}\n", .{trace}) catch {};
    }

    while (true) asm volatile ("wfi");
}
