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
            .optimize = .ReleaseSmall,
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

    run_cmd.addArg("-kernel");
    run_cmd.addArtifactArg(kernel);

    const run_step = b.step("run", "Launch the kernel");
    run_step.dependOn(&run_cmd.step);
}
