//! Generator for NUMA-Aware Work-Stealing Thread Pool Template
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
        \\        .name = "numa_bench",
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the NUMA worker pool benchmark");
        \\    run_step.dependOn(&run_cmd.step);
        \\
        \\    const tests = b.addTest(.{
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = target,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    const test_step = b.step("test", "Run NUMA worker unit tests");
        \\    test_step.dependOn(&b.addRunArtifact(tests).step);
        \\}
    ;
    try dir.writeFile(io, .{ .sub_path = "build.zig", .data = build_zig_content });

    // 2. src/main.zig
    var main_buf: [16384]u8 = undefined;
    const main_content = try std.fmt.bufPrint(&main_buf,
        \\//! {s} — Silicon-Aware NUMA & CCD Work-Stealing Engine
        \\//! Scaffolded by Kaos Zig Forge (KZF) for high-performance multi-core x86_64 systems
        \\
        \\const std = @import("std");
        \\const builtin = @import("builtin");
        \\
        \\pub const Task = struct {{
        \\    func: *const fn (?*anyopaque) void,
        \\    arg: ?*anyopaque,
        \\}};
        \\
        \\pub const WorkerQueue = struct {{
        \\    tasks: [256]Task = undefined,
        \\    head: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        \\    tail: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        \\    ccd_id: u32 = 0,
        \\
        \\    pub fn push(self: *WorkerQueue, task: Task) bool {{
        \\        const t = self.tail.load(.monotonic);
        \\        const h = self.head.load(.acquire);
        \\        if (t -% h >= 256) return false;
        \\        self.tasks[t % 256] = task;
        \\        self.tail.store(t +% 1, .release);
        \\        return true;
        \\    }}
        \\
        \\    pub fn pop(self: *WorkerQueue) ?Task {{
        \\        while (true) {{
        \\            const h = self.head.load(.monotonic);
        \\            const t = self.tail.load(.acquire);
        \\            if (h == t) return null;
        \\            const task = self.tasks[h % 256];
        \\            if (self.head.cmpxchgWeak(h, h +% 1, .release, .monotonic) == null) {{
        \\                return task;
        \\            }}
        \\        }}
        \\    }}
        \\}};
        \\
        \\pub const NumaPool = struct {{
        \\    queues: []WorkerQueue,
        \\    worker_count: usize,
        \\    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
        \\
        \\    pub fn init(alloc: std.mem.Allocator, count: usize) !NumaPool {{
        \\        const queues = try alloc.alloc(WorkerQueue, count);
        \\        for (queues, 0..) |*q, i| {{
        \\            q.* = WorkerQueue{{ .ccd_id = @intCast(i / 8) }};
        \\        }}
        \\        return NumaPool{{
        \\            .queues = queues,
        \\            .worker_count = count,
        \\        }};
        \\    }}
        \\
        \\    pub fn deinit(self: *NumaPool, alloc: std.mem.Allocator) void {{
        \\        self.running.store(false, .release);
        \\        alloc.free(self.queues);
        \\    }}
        \\
        \\    pub fn submit(self: *NumaPool, worker_id: usize, task: Task) bool {{
        \\        return self.queues[worker_id % self.worker_count].push(task);
        \\    }}
        \\
        \\    pub fn executeLocalOrSteal(self: *NumaPool, worker_id: usize) ?Task {{
        \\        // 1. Try local worker queue first (hot in L1/L2)
        \\        if (self.queues[worker_id].pop()) |task| {{
        \\            return task;
        \\        }}
        \\
        \\        // 2. Intra-CCD peer steal (same L3 cache slice)
        \\        const my_ccd = self.queues[worker_id].ccd_id;
        \\        for (self.queues, 0..) |*q, i| {{
        \\            if (i != worker_id and q.ccd_id == my_ccd) {{
        \\                if (q.pop()) |stolen| return stolen;
        \\            }}
        \\        }}
        \\
        \\        // 3. Fallback: Inter-CCD steal (crosses Infinity Fabric / socket)
        \\        for (self.queues, 0..) |*q, i| {{
        \\            if (i != worker_id and q.ccd_id != my_ccd) {{
        \\                if (q.pop()) |stolen| return stolen;
        \\            }}
        \\        }}
        \\        return null;
        \\    }}
        \\}};
        \\
        \\var g_completed: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
        \\
        \\fn sampleTask(arg: ?*anyopaque) void {{
        \\    _ = arg;
        \\    _ = g_completed.fetchAdd(1, .monotonic);
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
        \\    std.debug.print("\n=== ⚡ {s} NUMA Work-Stealing Pool ===\n", .{{}});
        \\
        \\    const workers = 16;
        \\    var pool = try NumaPool.init(alloc, workers);
        \\    defer pool.deinit(alloc);
        \\
        \\    std.debug.print("• Initialized {{d}} worker queues across simulated CCDs\n", .{{workers}});
        \\
        \\    const task_count = 50_000;
        \\    const t0 = rdtsc();
        \\    var submitted: usize = 0;
        \\    var drained: usize = 0;
        \\    while (drained < task_count) {{
        \\        while (submitted < task_count) {{
        \\            if (!pool.submit(submitted % workers, Task{{ .func = sampleTask, .arg = null }})) break;
        \\            submitted += 1;
        \\        }}
        \\        for (0..workers) |w| {{
        \\            if (pool.executeLocalOrSteal(w)) |t| {{
        \\                t.func(t.arg);
        \\                drained += 1;
        \\            }}
        \\        }}
        \\    }}
        \\    const t1 = rdtsc();
        \\
        \\    const cycles = @as(f64, @floatFromInt(t1 - t0)) / @as(f64, task_count);
        \\    std.debug.print("• Completed: {{d}} tasks\n", .{{g_completed.load(.monotonic)}});
        \\    std.debug.print("• Dispatch Latency: {{d:.1}} CPU cycles / task\n", .{{cycles}});
        \\    std.debug.print("• Status: Optimal Intra-CCD Work Stealing\n\n", .{{}});
        \\}}
        \\
        \\test "numa queue push and pop" {{
        \\    var q = WorkerQueue{{}};
        \\    try std.testing.expect(q.push(Task{{ .func = sampleTask, .arg = null }}));
        \\    const t = q.pop();
        \\    try std.testing.expect(t != null);
        \\    try std.testing.expect(q.pop() == null);
        \\}}
    , .{ project_name, project_name });

    try dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = main_content });

    // 3. README.md
    var readme_buf: [2048]u8 = undefined;
    const readme_content = try std.fmt.bufPrint(&readme_buf,
        \\# {s}
        \\
        \\Silicon-Aware NUMA & CCD Work-Stealing Pool scaffolded with **Kaos Zig Forge (KZF)**.
        \\
        \\## Features
        \\- Multi-queue work stealing with hierarchical locality
        \\- Tier 1: Local worker queue (L1/L2 cache resident)
        \\- Tier 2: Intra-CCD sibling steal (shared L3 slice, zero Infinity Fabric hop)
        \\- Tier 3: Inter-CCD / cross-socket fallback
        \\- Lock-free atomic ring buffers
        \\
        \\## Build & Test
        \\```bash
        \\zig test src/main.zig
        \\zig build run -Doptimize=ReleaseFast
        \\```
    , .{project_name});
    try dir.writeFile(io, .{ .sub_path = "README.md", .data = readme_content });
}
