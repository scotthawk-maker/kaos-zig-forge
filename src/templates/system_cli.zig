//! Generator for High-Performance System CLI Template
const std = @import("std");

pub fn generate(dir: std.Io.Dir, io: std.Io, project_name: []const u8) !void {
    try dir.createDirPath(io, "src");

    // 1. build.zig
    const build_zig_content =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "app",
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    if (b.args) |args| run_cmd.addArgs(args);
        \\    const run_step = b.step("run", "Run the application");
        \\    run_step.dependOn(&run_cmd.step);
        \\
        \\    const tests = b.addTest(.{
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    const test_step = b.step("test", "Run tests");
        \\    test_step.dependOn(&b.addRunArtifact(tests).step);
        \\}
    ;
    try dir.writeFile(io, .{ .sub_path = "build.zig", .data = build_zig_content });

    // 2. src/main.zig
    var main_buf: [4096]u8 = undefined;
    const main_content = try std.fmt.bufPrint(&main_buf,
        \\//! {s} — High-Performance System CLI Utility
        \\//! Built with Kaos Zig Forge (KZF)
        \\
        \\const std = @import("std");
        \\
        \\pub fn main(init: std.process.Init) !void {{
        \\    const arena = init.arena.allocator();
        \\    const args = try init.minimal.args.toSlice(arena);
        \\
        \\    std.debug.print("🔧 {{s}} CLI Utility Online\n", .{{ "{s}" }});
        \\    if (args.len <= 1) {{
        \\        std.debug.print("   (Pass flags or arguments to see them parsed here!)\n", .{{}});
        \\    }} else {{
        \\        for (args[1..], 1..) |arg, i| {{
        \\            std.debug.print("   Arg [{{d}}]: {{s}}\n", .{{ i, arg }});
        \\        }}
        \\    }}
        \\}}
        \\
        \\test "basic math" {{
        \\    try std.testing.expectEqual(@as(i32, 42), 40 + 2);
        \\}}
    , .{ project_name, project_name });
    try dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = main_content });

    // 3. README.md
    var readme_buf: [2048]u8 = undefined;
    const readme_content = try std.fmt.bufPrint(&readme_buf,
        \\# {s}
        \\
        \\High-performance CLI utility built with **Kaos Zig Forge (KZF)**.
        \\
        \\## 🛠️ Usage
        \\```bash
        \\zig build run -- --help
        \\zig build test
        \\```
    , .{project_name});
    try dir.writeFile(io, .{ .sub_path = "README.md", .data = readme_content });
}
