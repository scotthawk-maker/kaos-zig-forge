//! Generator for Ultra-Low-Latency Event Queue & SPSC Microservice Template
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
        \\        .name = "event_engine",
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the event queue engine");
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
        \\//! {s} — Ultra-Low-Latency Event Queue & Lock-Free SPSC Engine
        \\//! Built with Kaos Zig Forge (KZF) with zero-alloc ring buffers
        \\
        \\const std = @import("std");
        \\
        \\pub const EventTick = struct {{
        \\    timestamp_ns: u64,
        \\    value: u64, // Scaled 64-bit fixed-point metric (1e6)
        \\    quantity: u64,
        \\    is_ingress: bool,
        \\}};
        \\
        \\/// Lock-Free Single-Producer Single-Consumer (SPSC) Ring Buffer
        \\pub fn RingBuffer(comptime T: type, comptime Capacity: usize) type {{
        \\    comptime std.debug.assert(std.math.isPowerOfTwo(Capacity));
        \\    return struct {{
        \\        buffer: [Capacity]T = undefined,
        \\        head: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        \\        tail: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        \\
        \\        const Self = @This();
        \\        const Mask = Capacity - 1;
        \\
        \\        pub fn push(self: *Self, item: T) bool {{
        \\            const h = self.head.load(.monotonic);
        \\            const t = self.tail.load(.acquire);
        \\            if (h -% t >= Capacity) return false; // Buffer full
        \\            self.buffer[h & Mask] = item;
        \\            self.head.store(h +% 1, .release);
        \\            return true;
        \\        }}
        \\
        \\        pub fn pop(self: *Self) ?T {{
        \\            const t = self.tail.load(.monotonic);
        \\            const h = self.head.load(.acquire);
        \\            if (t == h) return null; // Buffer empty
        \\            const item = self.buffer[t & Mask];
        \\            self.tail.store(t +% 1, .release);
        \\            return item;
        \\        }}
        \\    }};
        \\}}
        \\
        \\pub fn main() !void {{
        \\    std.debug.print("⚡ {{s}} SPSC Engine Online. Initializing RingBuffer...\n", .{{ "{s}" }});
        \\
        \\    var ring = RingBuffer(EventTick, 1024){{}};
        \\    _ = ring.push(.{{ .timestamp_ns = 1791146000000, .value = 68420000000, .quantity = 1500, .is_ingress = true }});
        \\
        \\    if (ring.pop()) |tick| {{
        \\        std.debug.print("🎯 Ingested Event: Value {{d:.2}} Qty {{d}}\n", .{{ @as(f64, @floatFromInt(tick.value)) / 1e6, tick.quantity }});
        \\    }}
        \\}}
        \\
        \\test "ring buffer FIFO order" {{
        \\    var ring = RingBuffer(u32, 4){{}};
        \\    try std.testing.expect(ring.push(10));
        \\    try std.testing.expect(ring.push(20));
        \\    try std.testing.expectEqual(@as(u32, 10), ring.pop().?);
        \\    try std.testing.expectEqual(@as(u32, 20), ring.pop().?);
        \\    try std.testing.expect(ring.pop() == null);
        \\}}
    , .{ project_name, project_name });
    try dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = main_content });

    // 3. README.md
    var readme_buf: [2048]u8 = undefined;
    const readme_content = try std.fmt.bufPrint(&readme_buf,
        \\# {s}
        \\
        \\Ultra-low-latency event queue engine built with **Kaos Zig Forge (KZF)**.
        \\
        \\## ⚡ Performance Profile
        \\- Zero-allocation SPSC ring buffers for sub-microsecond event ingestion.
        \\- Fixed-point 64-bit integer accounting (zero float rounding errors).
        \\- Lock-free memory ordering (`acquire`/`release` atomics).
    , .{project_name});
    try dir.writeFile(io, .{ .sub_path = "README.md", .data = readme_content });
}
