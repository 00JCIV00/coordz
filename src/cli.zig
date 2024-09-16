//! Cova Commands for the Coordz CLI.

const builtin = @import("builtin");
const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const json = std.json;
const log = std.log;
const mem = std.mem;
const meta = std.meta;
const net = std.net;
const testing = std.testing;
const time = std.time;

const cova = @import("cova");

/// The Cova Command Type for Coordz.
pub const CommandT = cova.Command.Custom(.{
    .global_help_prefix = "Coordz",
    .val_config = .{
        .custom_types = &.{
            net.Address,
            fs.File,
        },
        .child_type_parse_fns = &.{
            .{
                .ChildT = net.Address,
                .parse_fn = struct{
                    pub fn parseIP(addr: []const u8, _: mem.Allocator) !net.Address {
                        var iter = mem.splitScalar(u8, addr, ':');
                        return net.Address.parseIp(
                            iter.first(),
                            try fmt.parseInt(u16, iter.next() orelse "-", 10)
                        ) catch |err| {
                            log.err("The provided destination address '{s}' is invalid.", .{ addr });
                            return err;
                        };
                    }
                }.parseIP,
            },
            .{
                .ChildT = fs.File,
                .parse_fn = struct{
                    pub fn parseFilePath(path: []const u8, _: mem.Allocator) !fs.File {
                        var cwd = fs.cwd();
                        return cwd.openFile(path, .{ .lock = .shared }) catch |err| {
                            log.err("The provided path to the File '{s}' is invalid.", .{ path });
                            return err;
                        };
                    }
                }.parseFilePath,
            },
        },
        .child_type_aliases = &.{
            .{ .ChildT = fs.File, .alias = "filepath" },
            .{ .ChildT = net.Address, .alias = "ip_address:port" },
            .{ .ChildT = bool, .alias = "toggle" },
        }
    }
});

/// The Root Setup Command for Coordz
pub const setup_cmd = CommandT{
    .name = "coordz",
    .description = "A TUI Client for GPSD.",
    .examples = &.{
        "coordz",
        "coordz get version",
    },
    .sub_cmds_mandatory = false,
    .sub_cmds = &.{
        .{
            .name = "get",
            .description = "Get information from GPSD in a single response with a temporary client.",
            .sub_cmds = &.{
                .{
                    .name = "version",
                    .description = "Get GPSD's Version info.",
                },
                .{
                    .name = "devices",
                    .description = "Get the list of Devices that GPSD is using.",
                },
                .{
                    .name = "device",
                    .description = "Get the individual Device that GPSD is using.",
                },
                .{
                    .name = "poll",
                    .description = "Poll for GPSD's latest TPV and SKY Messages.",
                },
                .{
                    .name = "location",
                    .description = "Get GPSD's current reported Time and Position."
                }
            }
        }
    },
    .opts = &.{
        .{
            .name = "gpsd-addr",
            .description = "Set the IP Address and Port for the GPSD connection. (Default: 127.0.0.1:2947)",
            .short_name = 'g',
            .long_name = "gpsd-addr",
            .val = CommandT.ValueT.ofType(net.Address, .{
                .name = "addr",
                .default_val = net.Address.parseIp("127.0.0.1", 2947) catch @panic("Something went wrong with the default GPSD Address."),
            }),
        },
        .{
            .name = "log-path",
            .description = "Save the JSON output to the specified Log Path.",
            .short_name = 'l',
            .long_name = "log-path",
            .val = CommandT.ValueT.ofType(fs.File, .{
                .name = "log_path",
                .description = "Path to the save JSON Log File.",
            }),
        },
        .{
            .name = "no-tui",
            .description = "Run coordz without a TUI.",
            .short_name = 'n',
            .long_name = "no-tui",
        },
        .{
            .name = "no-logo",
            .description = "Disable the startup logo.",
            .short_name = 'N',
            .long_name = "no-logo",
        },
        .{
            .name = "no-mouse",
            .description = "Disable mouse events for the TUI.",
            .long_name = "no-mouse",
        },
    },
    .vals = &.{
    },
};

