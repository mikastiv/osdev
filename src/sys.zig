pub const Syscall = enum(usize) {
    putchar = 1,
    getchar = 2,
    exit = 3,
    _,

    pub fn zero(self: Syscall) !usize {
        return try Syscall.one(self, 0);
    }

    pub fn one(self: Syscall, arg0: usize) !usize {
        var result: isize = undefined;
        asm volatile ("ecall"
            : [ret] "={a0}" (result),
            : [sysno] "{a0}" (self),
              [arg0] "{a1}" (arg0),
            : .{ .memory = true });

        if (result < 0) {
            return error.SyscallFailed;
        }

        return @intCast(result);
    }
};
