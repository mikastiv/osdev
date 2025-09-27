const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .abi = .none,
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel.zig"),
            .target = target,
            // .optimize = .ReleaseSmall,
            .optimize = .Debug,
            .strip = false,
        }),
    });
    kernel.setLinkerScript(b.path("src/kernel.ld"));
    kernel.entry = .disabled;

    b.installArtifact(kernel);

    const run_cmd = b.addSystemCommand(&.{"qemu-system-riscv32"});
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addArgs(&.{ "-machine", "virt" });
    run_cmd.addArgs(&.{ "-bios", "default" });
    run_cmd.addArgs(&.{ "-serial", "mon:stdio" });
    run_cmd.addArg("-nographic");
    run_cmd.addArg("--no-reboot");

    run_cmd.addArgs(&.{ "-d", "unimp,guest_errors,int,cpu_reset" });
    run_cmd.addArgs(&.{ "-D", "qemu.log" });

    run_cmd.addArgs(&.{ "-drive", "id=drive0,file=lorem.txt,format=raw,if=none" });
    run_cmd.addArgs(&.{ "-device", "virtio-blk-device,drive=drive0,bus=virtio-mmio-bus.0" });

    run_cmd.addArg("-kernel");
    run_cmd.addArtifactArg(kernel);

    // run_cmd.addArg("-S");
    // run_cmd.addArgs(&.{ "-gdb", "tcp::1234" });

    const shell = b.addExecutable(.{
        .name = "shell.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shell.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .strip = false,
        }),
    });
    shell.setLinkerScript(b.path("src/user.ld"));
    shell.entry = .disabled;

    b.installArtifact(shell);

    // const elf2bin = b.addObjCopy(shell.getEmittedBin(), .{
    //     .set_section_flags = .{
    //         .section_name = ".bss",
    //         .flags = .{ .alloc = true, .contents = true },
    //     },
    //     .format = .bin,
    // });
    // const bin = elf2bin.getOutput();

    const elf2bin = b.addSystemCommand(&.{"llvm-objcopy"});
    elf2bin.addArgs(&.{ "--set-section-flags", ".bss=alloc,contents" });
    elf2bin.addArgs(&.{ "-O", "binary" });
    elf2bin.addArtifactArg(shell);
    const bin = elf2bin.addOutputFileArg("shell.bin");

    kernel.root_module.addAnonymousImport("shell.bin", .{ .root_source_file = bin });

    const install_bin = b.addInstallBinFile(bin, "shell.bin");
    b.getInstallStep().dependOn(&install_bin.step);

    const run_step = b.step("run", "Launch the kernel");
    run_step.dependOn(&run_cmd.step);
}
