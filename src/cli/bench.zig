//! Kaos Zig Forge (KZF) — Silicon-Aware Benchmark Runner
const std = @import("std");
const Io = std.Io;
const cpuid = @import("../hardware/cpuid.zig");

pub fn runBench(io: Io, alloc: std.mem.Allocator) !void {
    const info = cpuid.CpuInfo.inspect();

    std.debug.print(
        \\======================================================================
        \\🏎️ Kaos Zig Forge (KZF) — Silicon-Aware Benchmark Runner
        \\======================================================================
        \\• Host Processor:  {s}
        \\• Silicon Microarch: {s}
        \\• AVX-512 Vector:  {s}
        \\• Optimization:    ReleaseFast (-Dcpu={s})
        \\======================================================================
        \\🚀 Launching native benchmark...
        \\
    , .{
        info.getBrand(),
        info.getMicroarch(),
        if (info.has_avx512f and info.has_avx512vl) "AVX-512 F/VL/BW/DQ 512-bit" else if (info.has_avx2) "AVX2 256-bit" else "SSE4.2",
        info.recommended_march,
    });

    var cpu_arg_buf: [64]u8 = undefined;
    const cpu_arg = try std.fmt.bufPrint(&cpu_arg_buf, "-Dcpu={s}", .{info.recommended_march});

    const argv = [_][]const u8{
        "zig",
        "build",
        "run",
        "-Doptimize=ReleaseFast",
        cpu_arg,
    };

    var child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        std.debug.print("❌ Error spawning 'zig build run': {s}\n", .{@errorName(err)});
        return;
    };

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code == 0) {
                std.debug.print("\n✨ Benchmark completed with exit code 0.\n", .{});
            } else {
                std.debug.print("\n⚠️ Benchmark exited with non-zero code {d}.\n", .{code});
            }
        },
        else => {
            std.debug.print("\n❌ Benchmark process terminated abnormally.\n", .{});
        },
    }
    _ = alloc;
}
