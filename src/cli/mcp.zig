//! Kaos Zig Forge (KZF) — Stdio MCP Server (JSON-RPC 2.0)
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
const doctor = @import("doctor.zig");

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

pub fn runMcp(io: Io, alloc: std.mem.Allocator) !void {
    const stdin_handle = Io.File.stdin();
    const stdout_handle = Io.File.stdout();

    var in_buf: [131072]u8 = undefined;
    var out_buf: [131072]u8 = undefined;

    var stdin_reader: Io.File.Reader = .init(stdin_handle, io, &in_buf);
    const reader = &stdin_reader.interface;

    var stdout_writer: Io.File.Writer = .init(stdout_handle, io, &out_buf);
    const writer = &stdout_writer.interface;

    while (true) {
        const line = reader.takeDelimiter('\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        } orelse break;

        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;

        var parsed = std.json.parseFromSlice(std.json.Value, alloc, trimmed, .{}) catch {
            continue;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;
        const root_obj = root.object;

        const id_val = root_obj.get("id");
        const method_val = root_obj.get("method");
        if (method_val == null or method_val.? != .string) continue;
        const method = method_val.?.string;

        if (std.mem.eql(u8, method, "initialize")) {
            try writeResponse(writer, id_val,
                \\{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"kzf","version":"1.3.0"}}
            );
        } else if (std.mem.eql(u8, method, "notifications/initialized")) {
            continue;
        } else if (std.mem.eql(u8, method, "ping")) {
            try writeResponse(writer, id_val, "{}");
        } else if (std.mem.eql(u8, method, "tools/list")) {
            try writeResponse(writer, id_val,
                \\{"tools":[{"name":"kzf_inspect_hardware","description":"Inspect host CPU silicon capabilities via inline assembly CPUID (Intel Core / Xeon, AMD Zen 3/4/5, AVX-512, AVX2, FMA, SHA, AES, and recommended compilation flags)","inputSchema":{"type":"object","properties":{}}},{"name":"kzf_list_templates","description":"List all available production starter templates (cli, simd, shm-ring, hft, numa-worker, webmcp-server, wal-storage)","inputSchema":{"type":"object","properties":{}}},{"name":"kzf_get_targets","description":"Get optimized build and performance compiler target flags for host CPU and AVX-512 execution","inputSchema":{"type":"object","properties":{}}},{"name":"kzf_doctor","description":"Scan a Zig project or file for deprecated patterns and syntax hallucinations with precise modern replacements, for the target Zig version","inputSchema":{"type":"object","properties":{"path":{"type":"string","description":"Optional file path or directory to scan. Defaults to current working directory."},"zig_version":{"type":"string","description":"Target Zig version selecting the deprecation rule set, e.g. 0.16 or 0.17 (default 0.16)."},"rules":{"type":"string","description":"Optional path to an extra rules JSON file (same schema as the built-in rules.json); its rules are added to the built-in set."}}}},{"name":"kzf_scaffold_project","description":"Scaffold a new production Zig 0.16 project in the current working directory","inputSchema":{"type":"object","properties":{"template":{"type":"string","description":"The template to use: 'cli', 'simd', 'shm-ring', 'hft', 'numa-worker', 'webmcp-server', or 'wal-storage'","enum":["cli","simd","shm-ring","hft","numa-worker","webmcp-server","wal-storage"]},"name":{"type":"string","description":"The project folder and package name"}},"required":["template","name"]}}]}
            );
        } else if (std.mem.eql(u8, method, "tools/call")) {
            const params_opt = root_obj.get("params");
            if (params_opt == null or params_opt.? != .object) {
                try writeError(writer, id_val, -32602, "Invalid params");
                try writer.flush();
                continue;
            }
            const params = params_opt.?.object;
            const tool_name = if (params.get("name")) |n| (if (n == .string) n.string else "") else "";

            if (std.mem.eql(u8, tool_name, "kzf_inspect_hardware")) {
                const info = cpuid.CpuInfo.inspect();
                var text_buf: [2048]u8 = undefined;
                const text = try std.fmt.bufPrint(&text_buf,
                    \\CPU Brand: {s}
                    \\Microarchitecture: {s}
                    \\Topology: {s} ({d} CCD/Node)
                    \\Cache: L1d {d} KB ({d}B line) | L2 {d} KB | L3 {d} KB
                    \\AVX-512: {s} | VNNI (INT8): {s} | BF16: {s} | VBMI: {s}
                    \\SOG Tuning Levers:
                    \\  • Execution Latencies: FMA={d}cyc, VNNI={d}cyc, BF16={d}cyc
                    \\  • Vector Accumulator Unroll: {d}-way interleaved registers
                    \\  • Fetch Block & Loop Alignment: {d} bytes (Op-Cache: {d} uOps)
                    \\  • Memory Prefetch Stride: {d} bytes (PREFETCHNTA L2-bypass)
                    \\  • Non-Temporal Store Floor: {d} KB (Write-Combining)
                    \\Compiler Flag: -Dcpu={s}
                , .{
                    info.getBrand(),
                    info.getMicroarch(),
                    if (info.is_dual_ccd) "Dual-CCD NUMA Split" else "Monolithic Single CCD",
                    info.nodes_per_processor,
                    info.l1d_size_kb,
                    info.l1d_line_bytes,
                    info.l2_size_kb,
                    info.l3_size_kb,
                    if (info.has_avx512f and info.has_avx512vl) "F/VL/BW/DQ" else "None",
                    if (info.has_avx512_vnni) "VPDPBUSD (64 ops/cyc)" else "None",
                    if (info.has_avx512_bf16) "Supported" else "None",
                    if (info.has_avx512_vbmi) "Supported" else "None",
                    info.fma_latency_cycles,
                    info.vnni_latency_cycles,
                    info.bf16_latency_cycles,
                    info.optimal_unroll_factor,
                    info.loop_alignment_bytes,
                    info.op_cache_capacity_uops,
                    info.prefetch_stride_bytes,
                    info.non_temporal_threshold_bytes / 1024,
                    info.recommended_march,
                });
                try writeToolContent(writer, id_val, text);
            } else if (std.mem.eql(u8, tool_name, "kzf_list_templates")) {
                const text =
                    \\Available KZF Production Templates:
                    \\• cli: High-Performance System CLI Utility (std.process.Init modern runtime harness)
                    \\• simd: SIMD Neural Tensor Vector Engine (@Vector(16, f32) AVX-512 Dot Product & RMSNorm)
                    \\• shm-ring: Zero-Copy Lock-Free SPSC Shared Memory Ring Buffer (/dev/shm or Windows SHM)
                    \\• hft: Ultra-Low-Latency Event Microservice (Lock-Free SPSC Ring Buffer, Fixed-Point Ticks)
                    \\• numa-worker: Silicon-Aware NUMA & Worker Pool with Core Pinning
                    \\• webmcp-server: Zero-Allocation Freestanding WebMCP JSON-RPC 2.0 Microservice
                    \\• wal-storage: Crash-Consistent Block Storage & Sector-Aligned WAL Journal (CRC32)
                ;
                try writeToolContent(writer, id_val, text);
            } else if (std.mem.eql(u8, tool_name, "kzf_get_targets")) {
                const text =
                    \\Optimized Build & Performance Targets:
                    \\• Native Host Optimized (Auto-detect all extensions): zig build -Dcpu=native -Doptimize=ReleaseFast
                    \\• Intel Core & Xeon (AVX2 & FMA3): zig build -Dcpu=x86_64_v3 -Doptimize=ReleaseFast
                    \\• Intel Xeon Scalable / High-End Core (AVX-512): zig build -Dcpu=x86_64_v4 -Doptimize=ReleaseFast
                    \\• AMD Zen 4/5 Native AVX-512: zig build -Dcpu=znver4 -Doptimize=ReleaseFast
                    \\• Microsecond Low-Latency Execution: zig build -Dcpu=native -Doptimize=ReleaseSafe
                ;
                try writeToolContent(writer, id_val, text);
            } else if (std.mem.eql(u8, tool_name, "kzf_doctor")) {
                var target_path: ?[]const u8 = null;
                var zig_version: ?[]const u8 = null;
                var rules_path: ?[]const u8 = null;
                if (params.get("arguments")) |args_val| {
                    if (args_val == .object) {
                        if (args_val.object.get("path")) |p| {
                            if (p == .string and p.string.len > 0) target_path = p.string;
                        }
                        if (args_val.object.get("zig_version")) |v| {
                            if (v == .string and v.string.len > 0) zig_version = v.string;
                        }
                        if (args_val.object.get("rules")) |r| {
                            if (r == .string and r.string.len > 0) rules_path = r.string;
                        }
                    }
                }

                const target = zig_version orelse doctor.DEFAULT_ZIG_VERSION;
                var loaded = doctor.loadRules(io, alloc, target, rules_path) catch |err| {
                    try writeError(writer, id_val, -32000, @errorName(err));
                    continue;
                };
                defer loaded.deinit();

                var issues = std.ArrayList(doctor.Issue).empty;
                const path_to_scan = target_path orelse ".";
                try doctor.scanPath(io, alloc, path_to_scan, loaded.rules, &issues);

                if (issues.items.len == 0) {
                    var ok_buf: [128]u8 = undefined;
                    const ok_msg = std.fmt.bufPrint(&ok_buf, "✅ 0 Hallucinations Detected! Code strictly adheres to Zig {s} standards.", .{target}) catch "✅ 0 Hallucinations Detected!";
                    try writeToolContent(writer, id_val, ok_msg);
                } else {
                    var tool_out_buf: [8192]u8 = undefined;
                    var pos: usize = 0;
                    const header = std.fmt.bufPrint(tool_out_buf[pos..], "⚠️ Detected {d} deprecated / hallucinated patterns in Zig code:\n\n", .{issues.items.len}) catch "";
                    pos += header.len;
                    for (issues.items) |iss| {
                        if (pos >= tool_out_buf.len - 256) break;
                        const chunk = std.fmt.bufPrint(tool_out_buf[pos..], "• {s}:{d} [{s}]\n  Issue: {s}\n  Fix:   {s}\n\n", .{ iss.file, iss.line, iss.pattern, iss.message, iss.suggestion }) catch break;
                        pos += chunk.len;
                    }
                    try writeToolContent(writer, id_val, tool_out_buf[0..pos]);
                }
            } else if (std.mem.eql(u8, tool_name, "kzf_scaffold_project")) {
                const args_val = params.get("arguments");
                if (args_val == null or args_val.? != .object) {
                    try writeError(writer, id_val, -32602, "Missing arguments");
                    try writer.flush();
                    continue;
                }
                const args_obj = args_val.?.object;
                const template = if (args_obj.get("template")) |t| (if (t == .string) t.string else "") else "";
                const name = if (args_obj.get("name")) |n| (if (n == .string) n.string else "") else "";

                if (template.len == 0 or name.len == 0) {
                    try writeError(writer, id_val, -32602, "Template and name must not be empty");
                    try writer.flush();
                    continue;
                }

                const cwd_path = std.process.currentPathAlloc(io, alloc) catch {
                    try writeError(writer, id_val, -32000, "Failed to resolve working directory");
                    try writer.flush();
                    continue;
                };

                var current_dir = Io.Dir.openDirAbsolute(io, cwd_path, .{}) catch {
                    try writeError(writer, id_val, -32000, "Failed to open working directory");
                    try writer.flush();
                    continue;
                };
                defer current_dir.close(io);

                current_dir.createDirPath(io, name) catch {
                    try writeError(writer, id_val, -32000, "Failed to create project directory");
                    try writer.flush();
                    continue;
                };

                var proj_dir = current_dir.openDir(io, name, .{}) catch {
                    try writeError(writer, id_val, -32000, "Failed to open project directory");
                    try writer.flush();
                    continue;
                };
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
                    try writeError(writer, id_val, -32602, "Unknown template. Choose from: cli, simd, shm-ring, hft, numa-worker, webmcp-server, wal-storage");
                    try writer.flush();
                    continue;
                }

                var success_buf: [1024]u8 = undefined;
                const success_msg = try std.fmt.bufPrint(&success_buf,
                    \\Project '{s}' forged successfully from template '{s}'.
                    \\Location: ./{s}/
                    \\Run commands:
                    \\  cd {s}
                    \\  zig build run
                , .{ name, template, name, name });
                try writeToolContent(writer, id_val, success_msg);
            } else {
                try writeError(writer, id_val, -32601, "Tool not found");
            }
            try writer.flush();
        } else {
            try writeError(writer, id_val, -32601, "Method not found");
            try writer.flush();
        }
    }
}

fn writeResponse(writer: anytype, id: ?std.json.Value, result_json: []const u8) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |v| {
        if (v == .integer) {
            try writer.print("{d}", .{v.integer});
        } else if (v == .string) {
            try writer.print("\"{s}\"", .{v.string});
        } else {
            try writer.writeAll("null");
        }
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"result\":");
    try writer.writeAll(result_json);
    try writer.writeAll("}\n");
    try writer.flush();
}

fn writeToolContent(writer: anytype, id: ?std.json.Value, text: []const u8) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |v| {
        if (v == .integer) {
            try writer.print("{d}", .{v.integer});
        } else if (v == .string) {
            try writer.print("\"{s}\"", .{v.string});
        } else {
            try writer.writeAll("null");
        }
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"result\":{{\"content\":[{{\"type\":\"text\",\"text\":{f}}}]}}\n", .{std.json.fmt(text, .{})});
    try writer.flush();
}

fn writeError(writer: anytype, id: ?std.json.Value, code: i32, msg: []const u8) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |v| {
        if (v == .integer) {
            try writer.print("{d}", .{v.integer});
        } else if (v == .string) {
            try writer.print("\"{s}\"", .{v.string});
        } else {
            try writer.writeAll("null");
        }
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"error\":{{\"code\":{d},\"message\":{f}}}\n", .{ code, std.json.fmt(msg, .{}) });
    try writer.flush();
}
