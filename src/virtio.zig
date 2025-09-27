const std = @import("std");
const kernel = @import("kernel.zig");

pub const sector_size = 512;
pub const device_blk = 2;
pub const blk_paddr = 0x10001000;

pub const Queue = extern struct {
    pub const entry_num = 16;

    pub const Desc = extern struct {
        pub const Flags = packed struct(u16) {
            next: bool = false,
            write: bool = false,
            _reserved: u14 = 0,
        };

        addr: u64 align(1),
        len: u32 align(1),
        flags: Flags align(1),
        next: u16 align(1),
    };

    pub const Avail = extern struct {
        pub const Flags = packed struct(u16) {
            no_interrupt: bool = false,
            _reserved: u15 = 0,
        };

        flags: Flags align(1),
        index: u16 align(1),
        ring: [entry_num]u16 align(1),
    };

    pub const UsedElem = extern struct {
        id: u32 align(1),
        len: u32 align(1),
    };

    pub const Used = extern struct {
        flags: u16 align(1),
        index: u16 align(1),
        ring: [entry_num]UsedElem align(1),
    };

    descs: [entry_num]Desc align(1),
    avail: Avail align(1),
    used: Used align(kernel.page_size),
    index: usize align(1),
    used_index: *volatile u16 align(1),
    last_used_index: u16 align(1),

    pub fn init(index: usize) *Queue {
        const size = @sizeOf(Queue);
        const paddr = kernel.allocPages(
            std.mem.alignForward(usize, size, kernel.page_size) / kernel.page_size,
        );

        const queue: *Queue = @ptrCast(@alignCast(paddr.ptr));
        queue.index = index;
        queue.used_index = @ptrCast(@alignCast(&queue.used.index));

        // Select the queue writing its index to QueueSel.
        Reg.write32(Reg.queue_sel, index);
        // Notify the device about the queue size by writing the size to QueueNum.
        Reg.write32(Reg.queue_num, entry_num);
        // Notify the device about the used alignment by writing its value in bytes to QueueAlign.
        Reg.write32(Reg.queue_align, 0);
        // Write physical number of the first page of the queue to the QueuePFN register.
        Reg.write32(Reg.queue_pfn, @intFromPtr(paddr.ptr));

        return queue;
    }

    pub fn kick(self: *Queue, desc_index: usize) void {
        self.avail.ring[self.avail.index % entry_num] = @intCast(desc_index);
        self.avail.index += 1;
        asm volatile ("fence rw, rw");
        Reg.write32(Reg.queue_notify, self.index);
        self.last_used_index += 1;
    }

    pub fn isBusy(self: *Queue) bool {
        return self.last_used_index != self.used_index.*;
    }
};

pub const StatusFlag = struct {
    const ack = 1 << 0;
    const driver = 1 << 1;
    const driver_ok = 1 << 2;
    const feat_ok = 1 << 3;
};

pub const Reg = struct {
    pub const magic = 0x00;
    pub const version = 0x04;
    pub const device_id = 0x08;
    pub const queue_sel = 0x30;
    pub const queue_num_max = 0x34;
    pub const queue_num = 0x38;
    pub const queue_align = 0x3c;
    pub const queue_pfn = 0x40;
    pub const queue_ready = 0x44;
    pub const queue_notify = 0x50;
    pub const device_status = 0x70;
    pub const device_config = 0x100;

    pub fn read32(offset: usize) u32 {
        const blk_ptr: *volatile u32 = @ptrFromInt(blk_paddr + offset);
        return blk_ptr.*;
    }

    pub fn read64(offset: usize) u64 {
        const blk_ptr: *volatile u64 = @ptrFromInt(blk_paddr + offset);
        return blk_ptr.*;
    }

    pub fn write32(offset: usize, value: u32) void {
        const blk_ptr: *volatile u32 = @ptrFromInt(blk_paddr + offset);
        blk_ptr.* = value;
    }

    pub fn fetchAndOr32(offset: usize, value: u32) void {
        write32(offset, read32(offset) | value);
    }
};

pub const BlkRequest = extern struct {
    // First descriptor: read-only from the device
    ty: enum(u32) { in = 0, out = 1 } align(1),
    reserved: u32 align(1),
    sector: u64 align(1),
    // Second descriptor: writable by the device if it's a read operation (Queue.Flags.write)
    data: [sector_size]u8 align(1),
    // Third descriptor: writable by the device (Queue.Flags.write)
    status: u8 align(1),
};

var blk_request_vq: *Queue = undefined;
var blk_request: *BlkRequest = undefined;
var blk_request_paddr: usize = 0;
var blk_capacity: u64 = 0;

pub fn init() void {
    if (Reg.read32(Reg.magic) != 0x74726976) @panic("virtio: invalid magic value");
    if (Reg.read32(Reg.version) != 1) @panic("virtio: invalid version");
    if (Reg.read32(Reg.device_id) != device_blk) std.debug.panic("virtio: invalid device id: {d}", .{Reg.read32(Reg.device_id)});

    // Reset the device.
    Reg.write32(Reg.device_status, 0);
    // Set the ACKNOWLEDGE status bit.
    Reg.fetchAndOr32(Reg.device_status, StatusFlag.ack);
    // Set the DRIVER status bit.
    Reg.fetchAndOr32(Reg.device_status, StatusFlag.driver);
    // Set the FEATURES_OK status bit.
    Reg.fetchAndOr32(Reg.device_status, StatusFlag.feat_ok);
    // Perform device-specific setup, including discovery of virtqueues for the device.
    blk_request_vq = .init(0);
    // Set the DRIVER_OK status bit.
    Reg.write32(Reg.device_status, StatusFlag.driver_ok);

    // Get the disk capacity.
    blk_capacity = Reg.read64(Reg.device_config) * sector_size;
    kernel.console.writer.print("virtio-blk: capacity is {d} bytes\n", .{blk_capacity}) catch {};

    // Allocate a region to store requests to the device.
    const size = @sizeOf(@TypeOf(blk_request.*));
    const region = kernel.allocPages(
        std.mem.alignForward(usize, size, kernel.page_size) / kernel.page_size,
    );
    blk_request_paddr = @intFromPtr(region.ptr);
    blk_request = @ptrFromInt(blk_request_paddr);
}

pub fn readWriteDisk(buffer: []u8, sector: usize, is_write: bool) void {
    if (sector >= blk_capacity / sector_size) {
        kernel.console.writer.print(
            "virtio: tried to read/write sector={d}, but capacity is {d}\n",
            .{ sector, blk_capacity / sector_size },
        ) catch {};
        return;
    }

    // Construct the request.
    blk_request.sector = sector;
    blk_request.ty = if (is_write) .out else .in;
    if (is_write) @memcpy(&blk_request.data, buffer);

    // Construct the queue descriptors (using 3 descriptors).
    var queue = blk_request_vq;
    queue.descs[0] = .{
        .addr = blk_request_paddr,
        .len = @sizeOf(u32) * 2 + @sizeOf(u64),
        .flags = .{ .next = true },
        .next = 1,
    };

    queue.descs[1] = .{
        .addr = blk_request_paddr + @offsetOf(BlkRequest, "data"),
        .len = sector_size,
        .flags = .{ .next = true, .write = is_write },
        .next = 2,
    };

    queue.descs[2] = .{
        .addr = blk_request_paddr + @offsetOf(BlkRequest, "status"),
        .len = @sizeOf(u8),
        .flags = .{ .write = true },
        .next = 0,
    };

    // Notify the device that there is a new request.
    queue.kick(0);

    // Wait until the device finishes processing.
    while (queue.isBusy()) {}

    if (blk_request.status != 0) {
        kernel.console.writer.print(
            "virtio: warn: failed to read/write sector={d} status={d}\n",
            .{ sector, blk_request.status },
        ) catch {};
        return;
    }

    if (!is_write) @memcpy(buffer, &blk_request.data);
}
