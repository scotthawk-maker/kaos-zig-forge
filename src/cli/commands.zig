//! Kaos Zig Forge (KZF) Command Execution Engine
const std = @import("std");
const Io = std.Io;
const cpuid = @import("../hardware/cpuid.zig");
const simd_tensor = @import("../templates/simd_tensor.zig");
const hft_engine = @import("../templates/hft_engine.zig");
const system_cli = @import("../templates/system_cli.zig");
const webmcp_server = @import("../templates/webmcp_server.zig");
const numa_worker = @import("../templates/numa_worker.zig");
const shm_ring = @import("../templates/shm_ring.zig");
const wal_storage = @import("../templates/wal_storage.zig");

pub fn printHelp() void {
    std.debug.print(
        \\======================================================================
        \\Kaos Zig Forge (KZF) v1.2.0 — Systems & Performance Toolkit
        \\======================================================================
        \\Commands:
        \\  kzf new <template> <name>  Scaffold a new production project
        \\  kzf list                   List available starter templates
        \\  kzf hardware               Inspect host CPU silicon (CPUID/AVX-512)
        \\  kzf targets                Display high-performance compile targets
        \\  kzf doctor [path] [--zig-version <v>]  Syntax Guard & Anti-Hallucination Linter (default 0.16)
        \\  kzf bench                  Run silicon-aware benchmark on host CPU
        \\  kzf mcp                    Start Stdio Model Context Protocol (MCP) server
        \\  kzf version                Display KZF version information
        \\  kzf help                   Show this help message
        \\
        \\Available Templates:
        \\  cli            High-performance system CLI utility with args parser
        \\  simd           AVX-512 16-lane vector neural tensor math engine
        \\  shm-ring       Zero-copy cacheline-padded lock-free SPSC IPC ring buffer
        \\  hft            Ultra-low-latency event queue & SPSC microservice
        \\  numa-worker    Silicon-aware work-stealing pool with CPU affinity pinning
        \\  webmcp-server  Zero-allocation WebMCP JSON-RPC 2.0 AI agent microservice
        \\  wal-storage    Crash-consistent sector-aligned block storage & WAL journal
        \\======================================================================
        \\
    , .{});
}

pub fn printVersion() void {
    std.debug.print("Kaos Zig Forge (KZF) v1.2.0 (Zig 0.16.0)\n", .{});
}

pub fn printList() void {
    std.debug.print(
        \\📋 Available KZF Production Templates:
        \\----------------------------------------------------------------------
        \\• [cli]           High-Performance System CLI Utility
        \\  - Leak-checked memory management & argument parsing
        \\  - Standard library fast execution harness
        \\
        \\• [simd]          SIMD Neural Tensor Engine
        \\  - 16-lane @Vector(16, f32) parallel dot products & vector math
        \\  - Hardware-optimized for modern x86_64 (Intel Core/Xeon & AMD Zen 3/4/5)
        \\  - Unit test suite included
        \\
        \\• [shm-ring]      Zero-Copy Lock-Free SPSC Shared Memory Ring
        \\  - 64-byte cacheline-padded Head & Tail pointers (zero false sharing)
        \\  - Sub-microsecond IPC over POSIX /dev/shm or Windows Named SHM
        \\  - Built-in RDTSC latency benchmark (millions of msgs/sec)
        \\
        \\• [hft]           Ultra-Low-Latency Event Queue & SPSC Microservice
        \\  - Lock-free Single-Producer Single-Consumer (SPSC) ring buffer
        \\  - Fixed-point 64-bit microsecond event tick ingestion (zero float error)
        \\  - Sub-microsecond execution profile
        \\
        \\• [numa-worker]   Silicon-Aware NUMA & Worker Pool
        \\  - CPU core and NUMA node affinity pinning (L3 cache resident)
        \\  - Hierarchical work stealing across hardware threads
        \\  - Ideal for multi-core x86_64 systems
        \\
        \\• [webmcp-server] Freestanding WebMCP JSON-RPC 2.0 Microservice
        \\  - Zero-heap allocation JSON-RPC 2.0 dispatch engine
        \\  - Stdio & HTTP transport compatible (Agent/Claude Desktop ready)
        \\  - Sub-millisecond response generation with schema reflection
        \\
        \\• [wal-storage]   Crash-Consistent Block Storage & WAL Journal
        \\  - Sector-aligned (512B / 4KB) atomic disk journaling
        \\  - Hardware CRC32 verification on every sector with torn-write guard
        \\  - Ideal for SSD ring buffers and atomic data journaling
        \\----------------------------------------------------------------------
        \\
    , .{});
}

pub fn inspectHardware() void {
    const info = cpuid.CpuInfo.inspect();

    std.debug.print(
        \\🔍 Host Silicon Inspection (CPUID & Microarchitecture):
        \\----------------------------------------------------------------------
        \\• CPU Brand:          {s}
        \\• Microarchitecture:  {s}
        \\
        \\Cache Hierarchy & Alignment:
        \\• L1 Data Cache:      {d} KB per core ({d}-byte line size, align(64))
        \\• L2 Cache:           {d} KB per core (8-way associative)
        \\• L3 Cache:           {d} KB shared
        \\
        \\Vector Acceleration (ISA):
        \\• AVX-512 Foundation: {s} (F, VL, BW, DQ)
        \\• AVX-512 VNNI:       {s} (VPDPBUSD: 64 INT8 ops/cycle/core)
        \\• AVX-512 BF16:       {s}
        \\• AVX-512 VBMI/VBMI2: {s}
        \\• AVX2 & FMA3:        {s}
        \\• Vector AES / VAES:  {s}
        \\• Hardware SHA:       {s}
        \\
        \\Silicon Optimization Guidance:
        \\• FMA Pipeline Latency:     {d} cycles
        \\• Optimal Accumulator Depth: {d}-way interleaved registers
        \\• Recommended Architecture:  -Dcpu={s}
        \\----------------------------------------------------------------------
        \\
    , .{
        info.getBrand(),
        info.getMicroarch(),
        info.l1d_size_kb,
        info.l1d_line_bytes,
        info.l2_size_kb,
        info.l3_size_kb,
        if (info.has_avx512f and info.has_avx512vl) "Supported (32 ZMM registers)" else "Not Available",
        if (info.has_avx512_vnni) "Supported" else "Not Available",
        if (info.has_avx512_bf16) "Supported" else "Not Available",
        if (info.has_avx512_vbmi and info.has_avx512_vbmi2) "Supported" else "Not Available",
        if (info.has_avx2 and info.has_fma) "Supported" else "Not Available",
        if (info.has_vaes) "Supported" else "Not Available",
        if (info.has_sha) "Supported" else "Not Available",
        info.fma_latency_cycles,
        info.optimal_unroll_factor,
        info.recommended_march,
    });
}

pub fn printTargets() void {
    std.debug.print(
        \\🎯 Optimized Build & Performance Targets:
        \\----------------------------------------------------------------------
        \\• Native Host Optimized (Auto-detect all extensions):
        \\  zig build -Dcpu=native -Doptimize=ReleaseFast
        \\
        \\• Intel Core & Xeon (AVX2 & FMA3):
        \\  zig build -Dcpu=x86_64_v3 -Doptimize=ReleaseFast
        \\
        \\• Intel Xeon Scalable / High-End Core (AVX-512):
        \\  zig build -Dcpu=x86_64_v4 -Doptimize=ReleaseFast
        \\
        \\• AMD Zen 4/5 Native AVX-512:
        \\  zig build -Dcpu=znver4 -Doptimize=ReleaseFast
        \\
        \\• Microsecond Low-Latency Execution:
        \\  zig build -Dcpu=native -Doptimize=ReleaseSafe
        \\----------------------------------------------------------------------
        \\
    , .{});
}

fn getBasename(path: []const u8) []const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return path[i + 1 ..];
        }
    }
    return path;
}

pub fn createProject(dir: Io.Dir, io: Io, template: []const u8, name: []const u8) !void {
    std.debug.print("🔨 Forging new project '{s}' from template '{s}'...\n", .{ name, template });

    try dir.createDirPath(io, name);
    var proj_dir = try dir.openDir(io, name, .{});
    defer proj_dir.close(io);

    const proj_name = getBasename(name);

    if (std.mem.eql(u8, template, "cli") or std.mem.eql(u8, template, "app")) {
        try system_cli.generate(proj_dir, io, proj_name);
    } else if (std.mem.eql(u8, template, "simd") or std.mem.eql(u8, template, "tensor")) {
        try simd_tensor.generate(proj_dir, io, proj_name);
    } else if (std.mem.eql(u8, template, "shm-ring") or std.mem.eql(u8, template, "shm") or std.mem.eql(u8, template, "ipc")) {
        try shm_ring.generate(proj_dir, io, proj_name);
    } else if (std.mem.eql(u8, template, "hft") or std.mem.eql(u8, template, "event") or std.mem.eql(u8, template, "queue")) {
        try hft_engine.generate(proj_dir, io, proj_name);
    } else if (std.mem.eql(u8, template, "numa-worker") or std.mem.eql(u8, template, "numa") or std.mem.eql(u8, template, "pool")) {
        try numa_worker.generate(proj_dir, io, proj_name);
    } else if (std.mem.eql(u8, template, "webmcp-server") or std.mem.eql(u8, template, "webmcp") or std.mem.eql(u8, template, "rpc")) {
        try webmcp_server.generate(proj_dir, io, proj_name);
    } else if (std.mem.eql(u8, template, "wal-storage") or std.mem.eql(u8, template, "wal") or std.mem.eql(u8, template, "storage") or std.mem.eql(u8, template, "journal")) {
        try wal_storage.generate(proj_dir, io, proj_name);
    } else {
        std.debug.print("❌ Unknown template: '{s}'. Use 'kzf list' to see available templates.\n", .{template});
        return;
    }

    std.debug.print(
        \\✨ Project successfully forged!
        \\----------------------------------------------------------------------
        \\• Name:     {s}
        \\• Template: {s}
        \\• Directory: ./{s}/
        \\
        \\Next Steps:
        \\  cd {s}
        \\  zig build run
        \\----------------------------------------------------------------------
        \\
    , .{ name, template, name, name });
}
