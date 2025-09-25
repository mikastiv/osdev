pub const SbiRet = extern struct {
    err: isize,
    value: isize,
};

pub const SbiError = error{
    Failed,
    NotSupported,
    InvalidParam,
    Denied,
    InvalidAddress,
    AlreadyAvailable,
    AlreadyStarted,
    AlreadyStopped,
    NoShmem,
    InvalidState,
    BadRange,
    Timeout,
    Io,
    DeniedLocked,
    Unknown,
};

pub fn call(
    arg0: isize,
    arg1: isize,
    arg2: isize,
    arg3: isize,
    arg4: isize,
    arg5: isize,
    fid: isize,
    eid: isize,
) SbiError!usize {
    var err: isize = undefined;
    var value: isize = undefined;

    asm volatile (
        \\ecall
        : [err] "={a0}" (err),
          [value] "={a1}" (value),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [arg3] "{a3}" (arg3),
          [arg4] "{a4}" (arg4),
          [arg5] "{a5}" (arg5),
          [fid] "{a6}" (fid),
          [eid] "{a7}" (eid),
        : .{ .memory = true });

    if (err < 0) return switch (err) {
        -1 => SbiError.Failed,
        -2 => SbiError.NotSupported,
        -3 => SbiError.InvalidParam,
        -4 => SbiError.Denied,
        -5 => SbiError.InvalidAddress,
        -6 => SbiError.AlreadyAvailable,
        -7 => SbiError.AlreadyStarted,
        -8 => SbiError.AlreadyStopped,
        -9 => SbiError.NoShmem,
        -10 => SbiError.InvalidState,
        -11 => SbiError.BadRange,
        -12 => SbiError.Timeout,
        -13 => SbiError.Io,
        -14 => SbiError.DeniedLocked,
        else => SbiError.Unknown,
    };

    return @intCast(value);
}
