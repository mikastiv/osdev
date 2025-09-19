const sbi = @import("sbi.zig");

pub fn putChar(char: u8) !void {
    _ = try sbi.call(char, 0, 0, 0, 0, 0, 0, 1);
}

pub fn printf(comptime fmt: []const u8, args: anytype) !void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected struct, found " ++ @typeName(args_type_info));
    }

    const fields_info = args_type_info.@"struct".fields;

    comptime var i = 0;
    comptime var fmt_i = 0;
    comptime var in_format = false;
    inline while (i < fmt.len) : (i += 1) {
        if (in_format) {
            switch (fmt[i]) {
                '%' => try putChar('%'),
                's', 'd', 'x' => {
                    const arg = @field(args, fields_info[fmt_i].name);
                    const ArgType = @TypeOf(arg);
                    const type_info = @typeInfo(ArgType);

                    switch (fmt[i]) {
                        's' => {
                            if (type_info != .pointer) {
                                @compileError("%s expected a string, found " ++ @typeName(ArgType));
                            }

                            for (arg) |char| {
                                try putChar(char);
                            }
                        },
                        'd' => {
                            if (type_info != .int and type_info != .comptime_int) {
                                @compileError("%d expected a number, found " ++ @typeName(ArgType));
                            }

                            var magnitude: u32 = @abs(arg);
                            if (arg < 0) {
                                try putChar('-');
                            }

                            var divisor: u32 = 1;
                            while (magnitude / divisor > 9) {
                                divisor *= 10;
                            }

                            while (divisor > 0) : (divisor /= 10) {
                                const digit: u8 = @intCast(magnitude / divisor);
                                try putChar('0' + digit);
                                magnitude %= divisor;
                            }
                        },
                        'x' => {
                            if (type_info != .int and type_info != .comptime_int) {
                                @compileError("%d expected a number, found " ++ @typeName(ArgType));
                            }

                            comptime var n: u5 = 8;
                            inline while (n > 0) : (n -= 1) {
                                const shift: u5 = (n - 1) * 4;
                                const nibble = (arg >> shift) & 0xf;
                                try putChar("0123456789abcdef"[nibble]);
                            }
                        },
                        else => {},
                    }

                    fmt_i += 1;
                },
                else => {},
            }
            in_format = false;
        } else switch (fmt[i]) {
            '%' => in_format = true,
            else => try putChar(fmt[i]),
        }
    }

    if (in_format) try putChar('%');

    if (fmt_i != fields_info.len) {
        @compileError("too many arguments");
    }
}
