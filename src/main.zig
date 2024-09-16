const std = @import("std");
const heap = std.heap;
const io = std.io;
const log = std.log;
const net = std.net;

const cova = @import("cova");
const cli = @import("cli.zig");
const gps = @import("gps");

pub fn main() !void {
    const stdout_file = io.getStdOut().writer();
    var stdout_bw = io.bufferedWriter(stdout_file);
    defer stdout_bw.flush() catch log.warn("Couldn't flush stdout before exiting!", .{});
    const stdout = stdout_bw.writer().any();

    var gpa = heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer if (gpa.detectLeaks()) log.err("Memory leak detected!", .{});
    const alloc = gpa.allocator();

    // Parse Args
    var main_cmd = try cli.setup_cmd.init(alloc, .{});
    defer main_cmd.deinit();
    var args_iter = try cova.ArgIteratorGeneric.init(alloc);
    defer args_iter.deinit();
    cova.parseArgs(
        &args_iter,
        cli.CommandT,
        main_cmd,
        stdout,
        .{},
    ) catch |err| {
        try stdout_bw.flush();
        switch (err) {
            error.UsageHelpCalled => return,
            error.TooManyValues,
            error.UnrecognizedArgument,
            error.UnexpectedArgument,
            error.CouldNotParseOption => {},
            else => |parse_err| return parse_err,
        }
    };

    const main_opts = try main_cmd.getOpts(.{});
    const gpsd_addr_opt = main_opts.get("gpsd-addr").?;
    const gpsd_addr = try gpsd_addr_opt.val.getAs(net.Address);


    // Client Setup
    var client = gps.Client.open(
        alloc,
        .{ .gpsd_addr = gpsd_addr },
    ) catch |err| switch (err) {
        error.ConnectionRefused => {
            log.err("Could not connect to GPSD on '{any}'. Please check that the service is running on the provided IP and Port.", .{ gpsd_addr });
            return;
        },
        else => return err,
    };
    defer client.close();
    try stdout.print("Connected to GPSD on '{any}'.\n", .{ gpsd_addr });

    if (main_cmd.matchSubCmd("get")) |get_cmd| {
        defer stdout_bw.flush() catch {};
        if (get_cmd.checkSubCmd("version")) try version(&client, stdout);
        if (get_cmd.checkSubCmd("devices")) try devices(&client, stdout);
        if (get_cmd.checkSubCmd("device")) try device(&client, stdout);
        if (get_cmd.checkSubCmd("location")) try location(&client, stdout);
        if (get_cmd.checkSubCmd("poll")) try poll(&client, stdout);
        return;
    }

    try stdout.print("Coordz WIP!\n", .{});
}

/// Get GPSD's current Time and Location
fn location(client: *gps.Client, writer: io.AnyWriter) !void {
    const loc_info = client.getLoc() orelse {
        try writer.print("No Location Data!\n", .{});
        return;
    };
    try writer.print(
        \\ Time: {s}
        \\ Loc:  {d}, {d}
        \\ Alt:  {d}m
        \\
        , .{
            loc_info.time,
            loc_info.lat, loc_info.lon,
            loc_info.alt orelse 0,
        }
    );
}

/// Get GPSD Version Info
fn version(client: *gps.Client, writer: io.AnyWriter) !void {
    const ver_info_jv = try client.version();
    defer ver_info_jv.deinit();
    const ver_info = ver_info_jv.value;
    try writer.print(
        \\ Version:
        \\ - Release:    {s}
        \\ - Revision:   {s}
        \\ - Major:      {d}
        \\ - Minor:      {d}
        \\ - Remote URL: {s}
        \\
        , .{
            ver_info.release,
            ver_info.rev,
            ver_info.proto_major,
            ver_info.proto_minor,
            ver_info.remote orelse "(Local)",
        }
    );
}

/// Get GPSD Devices
fn devices(client: *gps.Client, writer: io.AnyWriter) !void {
    const dev_info_jv = try client.devices();
    defer dev_info_jv.deinit();
    const dev_info = dev_info_jv.value;
    try writer.print(
        \\ Devices:
        \\ - Remote URL: {s}
        \\
        , .{
            dev_info.remote orelse "(Local)",
        }
    );
    for (dev_info.devices) |dev| try printDevice(dev, writer, .{ .indent = "   " });
}

/// Get an individual GPSD Device
fn device(client: *gps.Client, writer: io.AnyWriter) !void {
    const dev_info_jv = try client.device(.{});
    defer dev_info_jv.deinit();
    const dev_info = dev_info_jv.value;
    try printDevice(dev_info, writer, .{});
}

/// Print Config
const PrintConfig = struct {
    indent: []const u8 =  " ",
    prefix: []const u8 = "- ",
};

/// Print Info for a Device
fn printDevice(
    dev: gps.response.Device,
    writer: io.AnyWriter,
    config: PrintConfig,
) !void {
    try writer.print(
        \\{s}Device: {s}
        \\{s}{s}Activated:  {s}
        \\{s}{s}BPS:        {?d}
        \\{s}{s}Cycle:      {?d} s
        \\{s}{s}Driver:     {s}
        \\{s}{s}Flags:      {?x}
        \\{s}{s}Hex Data:   {?s}
        \\
        , .{
            config.indent, dev.path orelse "(unspecified)",
            config.indent, config.prefix, dev.activated orelse "(inactive)",
            config.indent, config.prefix, dev.bps,
            config.indent, config.prefix, dev.cycle,
            config.indent, config.prefix, dev.driver orelse "(not given)",
            config.indent, config.prefix, dev.flags,
            config.indent, config.prefix, dev.hexdata,
        }
    );
    // Split for arbitrary 32 format arg limit in Zig.
    try writer.print(
        \\{s}{s}Min Cycle:  {?d} s
        \\{s}{s}Native:     {?d}
        \\{s}{s}Parity:     {s}
        \\{s}{s}Read Only:  {any}
        \\{s}{s}Serial #:   {s}
        \\{s}{s}Stop Bits:  {d}
        \\{s}{s}Version:    {s}
        \\{s}{s}Misc:       {s}
        \\
        , .{
            config.indent, config.prefix, dev.mincycle,
            config.indent, config.prefix, dev.native,
            config.indent, config.prefix, dev.parity orelse "(not given)",
            config.indent, config.prefix, dev.readonly,
            config.indent, config.prefix, dev.sernum orelse "(not given)",
            config.indent, config.prefix, dev.stopbits,
            config.indent, config.prefix, dev.subtype orelse "(not given)",
            config.indent, config.prefix, dev.subtype1 orelse "(not given)",
        }
    );
}

/// Poll GPSD
fn poll(client: *gps.Client, writer: io.AnyWriter) !void {
    const poll_info_jv = try client.poll();
    defer poll_info_jv.deinit();
    const poll_info = poll_info_jv.value;
    try writer.print(
        \\ Poll:
        \\ - Time:    {s}
        \\ - Devices: {d}
        \\
        , .{
            poll_info.time,
            poll_info.active,
        });
    //for (poll_info.tpv) |tpv| try printTPV(poll, writer, .{ .indent = "   " });
}
