const std = @import("std");

const common = @import("common.zig");
const sbi = @import("sbi.zig");
const Syscall = @import("sys.zig").Syscall;

const kernel_base = @extern([*]u8, .{ .name = "__kernel_base" });
const user_base = @extern([*]u8, .{ .name = "__user_base" });
const bss = @extern([*]u8, .{ .name = "__bss" });
const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
const stack_top = @extern([*]u8, .{ .name = "__stack_top" });

const ram_start = @extern([*]u8, .{ .name = "__free_ram_start" });
const ram_end = @extern([*]u8, .{ .name = "__free_ram_end" });
const page_size = 4 * 1024;

const user_image = @embedFile("shell.bin");

var console: common.Console = .init(&putChar);

const Csr = enum {
    sscratch,
    sstatus,
    stvec,
    scause,
    stval,
    sepc,

    const satp_sv32 = 1 << 31;
    const scause_ecall = 8;
    const sstatus_spie = 1 << 5;

    pub fn read(comptime self: Csr) usize {
        return asm volatile ("csrr %[ret], " ++ @tagName(self)
            : [ret] "=r" (-> usize),
        );
    }

    pub fn write(comptime self: Csr, value: usize) void {
        asm volatile ("csrw " ++ @tagName(self) ++ ", %[value]"
            :
            : [value] "r" (value),
        );
    }
};

const TrapFrame = packed struct {
    ra: usize,
    gp: usize,
    tp: usize,
    t0: usize,
    t1: usize,
    t2: usize,
    t3: usize,
    t4: usize,
    t5: usize,
    t6: usize,
    a0: usize,
    a1: usize,
    a2: usize,
    a3: usize,
    a4: usize,
    a5: usize,
    a6: usize,
    a7: usize,
    s0: usize,
    s1: usize,
    s2: usize,
    s3: usize,
    s4: usize,
    s5: usize,
    s6: usize,
    s7: usize,
    s8: usize,
    s9: usize,
    s10: usize,
    s11: usize,
};

const Process = struct {
    const max = 8;

    pid: usize,
    state: enum { unused, runnable },
    sp: usize,
    page_table: [*]PageTableEntry,
    stack: [8192]u8 align(4),

    const init: Process = .{
        .pid = 0,
        .state = .unused,
        .sp = 0,
        .page_table = undefined,
        .stack = @splat(0),
    };

    fn create(image: []const u8) *Process {
        const process = for (&processes) |*proc| {
            if (proc.state == .unused) break proc;
        } else @panic("no free process slots");

        const word_stack = std.mem.bytesAsSlice(usize, &process.stack);
        var sp = word_stack.len;
        for (0..12) |_| { // s0 to s11
            sp -= 1;
            word_stack[sp] = 0;
        }
        sp -= 1;
        word_stack[sp] = @intFromPtr(&userEntry); // ra

        const page_table: [*]PageTableEntry = @ptrCast(@alignCast(allocPages(1)));

        // Map kernel pages.
        const page_count = (ram_end - kernel_base) / page_size;
        const pages: [*][page_size]u8 = @ptrCast(kernel_base);
        for (pages[0..page_count]) |*page| {
            const flags: PageTableEntry.Flags = .{ .read = true, .write = true, .execute = true };
            const paddr = @intFromPtr(page);
            mapPage(page_table, paddr, paddr, flags);
        }

        // Map user pages.
        var image_pages = std.mem.window(u8, image, page_size, page_size);
        while (image_pages.next()) |image_page| {
            const page = allocPages(1);
            @memcpy(page[0..image_page.len], image_page);

            const flags: PageTableEntry.Flags = .{ .read = true, .write = true, .execute = true, .user = true };
            const vaddr = @intFromPtr(user_base + (image_page.ptr - image.ptr));
            const paddr = @intFromPtr(page.ptr);
            mapPage(page_table, vaddr, paddr, flags);
        }

        const offset = process - &processes[0];
        process.pid = offset + 1;
        process.state = .runnable;
        process.sp = @intFromPtr(&word_stack[sp]);
        process.page_table = page_table;

        return process;
    }
};

const PageTableEntry = packed struct(u32) {
    const Flags = packed struct(u8) {
        valid: bool = false,
        read: bool = false,
        write: bool = false,
        execute: bool = false,
        user: bool = false,
        global: bool = false,
        accessed: bool = false,
        dirty: bool = false,
    };

    flags: Flags,
    _reserved: u2 = 0,
    ppn: u22,

    fn asPhysicalAddr(self: PageTableEntry) [*]PageTableEntry {
        const ppn: u32 = self.ppn;
        return @ptrFromInt(ppn * page_size);
    }
};

const VirtualAddr = packed struct(u32) {
    offset: u12,
    vpn_0: u10,
    vpn_1: u10,
};

var processes: [Process.max]Process = @splat(.init);

fn userEntry() callconv(.naked) void {
    asm volatile (
        \\csrw sepc, %[sepc]
        \\csrw sstatus, %[sstatus]
        \\sret
        :
        : [sepc] "r" (user_base),
          [sstatus] "r" (Csr.sstatus_spie),
    );
}

var current_process: *Process = undefined;
var idle_process: *Process = undefined;

fn main() !void {
    const bss_size = bss_end - bss;
    @memset(bss[0..bss_size], 0);

    Csr.write(.stvec, @intFromPtr(&kernelEntry));

    idle_process = Process.create(&.{});
    idle_process.pid = 0;
    current_process = idle_process;

    _ = Process.create(user_image);

    yield();

    @panic("switched to idle process");
}

fn mapPage(table1: [*]PageTableEntry, vaddr: usize, paddr: usize, flags: PageTableEntry.Flags) void {
    if (!std.mem.isAligned(vaddr, page_size)) {
        std.debug.panic("unaligned vaddr: {x}", .{vaddr});
    }

    if (!std.mem.isAligned(paddr, page_size)) {
        std.debug.panic("unaligned paddr: {x}", .{paddr});
    }

    const virtual_addr: VirtualAddr = @bitCast(vaddr);
    if (!table1[virtual_addr.vpn_1].flags.valid) {
        const page_table = allocPages(1);
        const ppn = @intFromPtr(page_table.ptr) / page_size;
        table1[virtual_addr.vpn_1] = .{
            .flags = .{ .valid = true },
            .ppn = @intCast(ppn),
        };
    }

    var new_entry: PageTableEntry = .{
        .flags = flags,
        .ppn = @intCast(paddr / page_size),
    };
    new_entry.flags.valid = true;

    const table0 = table1[virtual_addr.vpn_1].asPhysicalAddr();
    table0[virtual_addr.vpn_0] = new_entry;
}

noinline fn yield() void {
    var next_process = idle_process;
    for (0..Process.max) |i| {
        const index = (current_process.pid + i) % Process.max;
        const process = &processes[index];
        if (process.state == .runnable and process.pid > 0) {
            next_process = process;
            break;
        }
    }

    if (next_process == current_process) return;

    const ppn = @intFromPtr(next_process.page_table) / page_size;
    asm volatile (
        \\sfence.vma
        \\csrw satp, %[satp]
        \\sfence.vma
        \\csrw sscratch, %[next_top]
        :
        : [satp] "r" (Csr.satp_sv32 | ppn),
          [next_top] "r" (next_process.stack[next_process.stack.len..].ptr),
    );

    const prev_process = current_process;
    current_process = next_process;
    switchContext(&prev_process.sp, &next_process.sp);
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

    const result = ram[S.next_ram_index .. S.next_ram_index + size];
    S.next_ram_index += size;

    @memset(result, 0);

    return result;
}

fn putChar(char: u8) !void {
    _ = try sbi.call(char, 0, 0, 0, 0, 0, 0, 1);
}

export fn kernelMain() noreturn {
    main() catch |err| {
        std.debug.panic("failed with: {t}", .{err});
    };

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

noinline fn switchContext(prev_sp: *usize, next_sp: *usize) void {
    asm volatile (
        \\
        // Save callee-saved regisers on the current process's stack.
        \\addi sp, sp, -4 * 13
        \\sw ra, 0 * 4(sp)
        \\sw s0, 1 * 4(sp)
        \\sw s1, 2 * 4(sp)
        \\sw s2, 3 * 4(sp)
        \\sw s3, 4 * 4(sp)
        \\sw s4, 5 * 4(sp)
        \\sw s5, 6 * 4(sp)
        \\sw s6, 7 * 4(sp)
        \\sw s7, 8 * 4(sp)
        \\sw s8, 9 * 4(sp)
        \\sw s9, 10 * 4(sp)
        \\sw s10, 11 * 4(sp)
        \\sw s11, 12 * 4(sp)
        // Switch stack pointer.
        \\sw sp, (%[prev_sp])
        \\lw sp, (%[next_sp])
        // Restore callee-saved registers from the next process's stack.
        \\lw ra, 0 * 4(sp)
        \\lw s0, 1 * 4(sp)
        \\lw s1, 2 * 4(sp)
        \\lw s2, 3 * 4(sp)
        \\lw s3, 4 * 4(sp)
        \\lw s4, 5 * 4(sp)
        \\lw s5, 6 * 4(sp)
        \\lw s6, 7 * 4(sp)
        \\lw s7, 8 * 4(sp)
        \\lw s8, 9 * 4(sp)
        \\lw s9, 10 * 4(sp)
        \\lw s10, 11 * 4(sp)
        \\lw s11, 12 * 4(sp)
        \\addi sp, sp, 4 * 13
        :
        : [prev_sp] "r" (prev_sp),
          [next_sp] "r" (next_sp),
    );
}

export fn kernelEntry() align(4) callconv(.naked) void {
    asm volatile (
        \\
        // Retrieve kernel stack of the current process from sscratch.
        \\csrrw sp, sscratch, sp
        // Allocate space on the stack.
        \\addi sp, sp, -4 * 31
        // Save registers to a TrapFrame struct.
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
        // Retrieve and save the sp at the time of exception.
        \\csrr a0, sscratch
        \\sw a0, 4 * 30(sp)
        // Reset the kernel stack
        \\addi a0, sp, 4 * 31
        \\csrw sscratch, a0
        // Call handler with TrapFrame param.
        \\mv a0, sp
        \\call handleTrap
        // Restore registers with values of TrapFrame.
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

export fn handleTrap(frame: *TrapFrame) void {
    const scause = Csr.read(.scause);
    const stval = Csr.read(.stval);
    var user_pc = Csr.read(.sepc);

    if (scause == Csr.scause_ecall) {
        handleSyscall(frame);
        user_pc += 4;
    } else {
        std.debug.panic("unexpected trap scause={x}, stval={x}, sepc={x}", .{ scause, stval, user_pc });
    }

    Csr.write(.sepc, user_pc);
}

fn handleSyscall(frame: *TrapFrame) void {
    const syscall: Syscall = @enumFromInt(frame.a0);
    switch (syscall) {
        Syscall.putchar => console.writer.writeByte(@truncate(frame.a1)) catch |err| {
            frame.a0 = @intFromError(err);
        },
        else => std.debug.panic("unexpected syscall a0={x}\n", .{frame.a0}),
    }
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
