pub const Syscall = enum(usize) {
    putchar = 1,
    _,

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
