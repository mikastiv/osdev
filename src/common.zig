const std = @import("std");
const sbi = @import("sbi.zig");

pub const Csr = enum {
    sscratch,
    stvec,
    scause,
    stval,
    sepc,

    pub fn read(comptime self: Csr) usize {
        return asm ("csrr %[ret], " ++ @tagName(self)
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

pub const TrapFrame = packed struct {
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

pub const Console = struct {
    writer: std.Io.Writer,

    pub const init: Console = .{
        .writer = .{
            .buffer = &.{},
            .vtable = &.{ .drain = drain },
        },
    };
};

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var n: usize = 0;
    if (w.end > 0) {
        for (w.buffer[0..w.end]) |char| {
            putChar(char) catch return error.WriteFailed;
        }
        n += w.end;
        w.end = 0;
    }

    for (data, 0..) |row, i| {
        if (i == data.len - 1) break;

        for (row) |char| {
            putChar(char) catch return error.WriteFailed;
        }
        n += row.len;
    }

    const pattern = data[data.len - 1];
    for (0..splat) |_| {
        for (pattern) |char| {
            putChar(char) catch return error.WriteFailed;
        }
        n += pattern.len;
    }

    return n;
}

fn putChar(char: u8) !void {
    _ = try sbi.call(char, 0, 0, 0, 0, 0, 0, 1);
}
