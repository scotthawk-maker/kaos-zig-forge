//! Generator for SIMD Tensor Neural Engine Template
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
        \\        .name = "tensor_bench",
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the SIMD benchmark");
        \\    run_step.dependOn(&run_cmd.step);
        \\
        \\    const tests = b.addTest(.{
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    const test_step = b.step("test", "Run tensor math tests");
        \\    test_step.dependOn(&b.addRunArtifact(tests).step);
        \\}
    ;
    try dir.writeFile(io, .{ .sub_path = "build.zig", .data = build_zig_content });

    // 2. src/main.zig
    var main_buf: [8192]u8 = undefined;
    const main_content = try std.fmt.bufPrint(&main_buf,
        \\//! {s} — High-Performance SIMD Vector & Neural Tensor Engine
        \\//! Built with Kaos Zig Forge (KZF) with AMD Zen 4/5 AVX-512 4-Way Unrolling
        \\
        \\const std = @import("std");
        \\
        \\pub const Vec16f = @Vector(16, f32);
        \\
        \\/// AMD Zen 4 Optimized 4-Way Vector Unrolled Dot Product (64 floats per cycle)
        \\/// Fully hides the 4-cycle FMA latency by interleaving 4 independent %zmm registers
        \\pub fn dotProduct(a: []align(64) const f32, b: []align(64) const f32) f32 {{
        \\    @setFloatMode(.optimized);
        \\    std.debug.assert(a.len == b.len);
        \\
        \\    var acc0: Vec16f = @splat(0.0);
        \\    var acc1: Vec16f = @splat(0.0);
        \\    var acc2: Vec16f = @splat(0.0);
        \\    var acc3: Vec16f = @splat(0.0);
        \\
        \\    var i: usize = 0;
        \\    while (i + 64 <= a.len) : (i += 64) {{
        \\        if (i + 128 < a.len) {{
        \\            @prefetch(&a[i + 128], .{{ .locality = 3, .cache = .data }});
        \\            @prefetch(&b[i + 128], .{{ .locality = 3, .cache = .data }});
        \\        }}
        \\        acc0 += a[i..][0..16].* * b[i..][0..16].*;
        \\        acc1 += a[i + 16 ..][0..16].* * b[i + 16 ..][0..16].*;
        \\        acc2 += a[i + 32 ..][0..16].* * b[i + 32 ..][0..16].*;
        \\        acc3 += a[i + 48 ..][0..16].* * b[i + 48 ..][0..16].*;
        \\    }}
        \\
        \\    const total = (acc0 + acc1) + (acc2 + acc3);
        \\    var sum: f32 = @reduce(.Add, total);
        \\    while (i < a.len) : (i += 1) {{
        \\        sum += a[i] * b[i];
        \\    }}
        \\    return sum;
        \\}}
        \\
        \\/// Fast RMSNorm Layer
        \\pub fn rmsNorm(out: []f32, x: []const f32, weight: []const f32, eps: f32) void {{
        \\    var ss: f32 = 0.0;
        \\    for (x) |v| ss += v * v;
        \\    const scale = 1.0 / @sqrt((ss / @as(f32, @floatFromInt(x.len))) + eps);
        \\    for (out, 0..) |*o, i| {{
        \\        o.* = x[i] * scale * weight[i];
        \\    }}
        \\}}
        \\
        \\pub inline fn rdtsc() u64 {{
        \\    var lo: u32 = undefined;
        \\    var hi: u32 = undefined;
        \\    asm volatile ("rdtsc" : [lo] "={{eax}}" (lo), [hi] "={{edx}}" (hi));
        \\    return (@as(u64, hi) << 32) | @as(u64, lo);
        \\}}
        \\
        \\pub fn main(init: std.process.Init) !void {{
        \\    const alloc = init.gpa;
        \\    const size = 4096;
        \\    const a = try alloc.alignedAlloc(f32, .fromByteUnits(64), size);
        \\    defer alloc.free(a);
        \\    const b = try alloc.alignedAlloc(f32, .fromByteUnits(64), size);
        \\    defer alloc.free(b);
        \\
        \\    @memset(a, 1.0);
        \\    @memset(b, 2.0);
        \\
        \\    const iters = 100_000;
        \\    const c0 = rdtsc();
        \\    var acc: f32 = 0;
        \\    for (0..iters) |_| {{
        \\        acc += dotProduct(a, b);
        \\    }}
        \\    const c1 = rdtsc();
        \\    std.mem.doNotOptimizeAway(acc);
        \\
        \\    const cycles_per_dot = @as(f64, @floatFromInt(c1 - c0)) / @as(f64, iters);
        \\    std.debug.print("🚀 {{s}} Zen 4 4-Way Unrolled SIMD ({{d}} floats): {{d:.1}} CPU cycles\n", .{{ "{s}", size, cycles_per_dot }});
        \\}}
        \\
        \\test "dotProduct correctness" {{
        \\    const a = [_]f32{{1.0}} ** 128;
        \\    const b = [_]f32{{2.0}} ** 128;
        \\    const a_aligned: []align(64) const f32 = &a;
        \\    const b_aligned: []align(64) const f32 = &b;
        \\    try std.testing.expectEqual(@as(f32, 256.0), dotProduct(a_aligned, b_aligned));
        \\}}
    , .{ project_name, project_name });

    try dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = main_content });

    // 3. README.md
    var readme_buf: [2048]u8 = undefined;
    const readme_content = try std.fmt.bufPrint(&readme_buf,
        \\# {s}
        \\
        \\AMD Zen 4/5 Ultra-Optimized SIMD Vector & Neural Tensor Engine.
        \\
        \\## Silicon Optimizations
        \\- 4-Way Vector Accumulator Register Unrolling (hiding 4-cycle FMA latency)
        \\- 64-Byte Cache Line Alignment (`align(64)`) to eliminate cache-line split penalties
        \\- Dual-line software prefetching for AMD Zen 4 Stream Prefetcher
        \\- Full AVX-512 F/VL/BW/DQ 512-bit single-cycle execution
        \\
        \\## Build & Benchmark
        \\```bash
        \\kzf bench
        \\```
    , .{project_name});
    try dir.writeFile(io, .{ .sub_path = "README.md", .data = readme_content });
}
