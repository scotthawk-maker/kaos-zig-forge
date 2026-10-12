//! Kaos Zig Forge (KZF) — Main CLI Entrypoint
const std = @import("std");
const kzf = @import("kaos_zig_forge");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const cmd = kzf.args.parse(args);

    switch (cmd) {
        .help => kzf.commands.printHelp(),
        .version => kzf.commands.printVersion(),
        .list => kzf.commands.printList(),
        .hardware => kzf.commands.inspectHardware(),
        .targets => kzf.commands.printTargets(),
        .doctor => |d| {
            const n = try kzf.doctor.runDoctor(init.io, arena, d.path, d.zig_version, d.rules_path);
            if (n > 0) std.process.exit(1); // non-zero so `kzf doctor && zig build` gates correctly
        },
        .bench => try kzf.bench.runBench(init.io, arena),
        .mcp => try kzf.mcp.runMcp(init.io, arena),
        .new => |n| {
            const cwd_path = std.process.currentPathAlloc(init.io, arena) catch |err| {
                std.debug.print("❌ Error: Unable to resolve current directory: {s}\n", .{@errorName(err)});
                return;
            };
            var current_dir = std.Io.Dir.openDirAbsolute(init.io, cwd_path, .{}) catch |err| {
                std.debug.print("❌ Error: Unable to open current directory '{s}': {s}\n", .{ cwd_path, @errorName(err) });
                return;
            };
            defer current_dir.close(init.io);

            try kzf.commands.createProject(current_dir, init.io, n.template, n.name);
        },
        .unknown => |u| {
            std.debug.print("❌ Unknown command: '{s}'. Run 'kzf help' for usage.\n", .{u});
        },
    }
}
