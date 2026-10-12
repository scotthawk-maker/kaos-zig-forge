//! Kaos Zig Forge (KZF) CLI Argument Parser
const std = @import("std");

pub const Command = union(enum) {
    new: struct {
        template: []const u8,
        name: []const u8,
    },
    list: void,
    hardware: void,
    targets: void,
    doctor: struct {
        path: ?[]const u8 = null,
        zig_version: ?[]const u8 = null,
        rules_path: ?[]const u8 = null,
    },
    bench: void,
    mcp: void,
    help: void,
    version: void,
    unknown: []const u8,
};

pub fn parse(args: []const []const u8) Command {
    if (args.len <= 1) return .help;

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "new") or std.mem.eql(u8, cmd, "init")) {
        if (args.len < 4) {
            return .help;
        }
        return .{
            .new = .{
                .template = args[2],
                .name = args[3],
            },
        };
    } else if (std.mem.eql(u8, cmd, "list") or std.mem.eql(u8, cmd, "ls")) {
        return .list;
    } else if (std.mem.eql(u8, cmd, "hardware") or std.mem.eql(u8, cmd, "hw") or std.mem.eql(u8, cmd, "cpu")) {
        return .hardware;
    } else if (std.mem.eql(u8, cmd, "targets")) {
        return .targets;
    } else if (std.mem.eql(u8, cmd, "doctor") or std.mem.eql(u8, cmd, "lint")) {
        // Accept `doctor [path] [--zig-version <v>] [--rules <file.json>]` in any order.
        var target_path: ?[]const u8 = null;
        var zig_version: ?[]const u8 = null;
        var rules_path: ?[]const u8 = null;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            const a = args[i];
            if (std.mem.eql(u8, a, "--zig-version") or std.mem.eql(u8, a, "-z")) {
                if (i + 1 < args.len) {
                    zig_version = args[i + 1];
                    i += 1;
                }
            } else if (std.mem.startsWith(u8, a, "--zig-version=")) {
                zig_version = a["--zig-version=".len..];
            } else if (std.mem.eql(u8, a, "--rules")) {
                if (i + 1 < args.len) {
                    rules_path = args[i + 1];
                    i += 1;
                }
            } else if (std.mem.startsWith(u8, a, "--rules=")) {
                rules_path = a["--rules=".len..];
            } else if (!std.mem.startsWith(u8, a, "-")) {
                target_path = a;
            }
        }
        return .{ .doctor = .{ .path = target_path, .zig_version = zig_version, .rules_path = rules_path } };
    } else if (std.mem.eql(u8, cmd, "bench") or std.mem.eql(u8, cmd, "benchmark")) {
        return .bench;
    } else if (std.mem.eql(u8, cmd, "mcp")) {
        return .mcp;
    } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        return .help;
    } else if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v")) {
        return .version;
    } else {
        return .{ .unknown = cmd };
    }
}
