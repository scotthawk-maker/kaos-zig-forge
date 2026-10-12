# CLAUDE.md — Kaos Zig Forge (KZF) Integration Guidelines

## Overview
This machine has **Kaos Zig Forge (KZF) v1.2.0** and **Zig 0.16.0** installed — a small homegrown toolkit for Zig work. Lean on it.
Zig evolves rapidly across releases. To avoid reaching for deprecated APIs (e.g. `std.heap.GeneralPurposeAllocator`, `std.io.getStdOut()`, or outdated `build.zig` targets) and to catch the common ones *before* the compiler does, use `kzf` for project scaffolding, syntax linting, benchmarking, and cross-platform compilation. `kzf doctor` is a fast pre-flight — run it, then still run `zig build` (it complements the compiler, it does not replace it).

---

## 🛠️ CLI Workflows

`kzf` is globally available on the system `PATH` (`kzf.exe`).

### 1. Host Silicon Inspection & Auto-Benchmarking
Always probe the host CPU architecture and run silicon-aware benchmarks:
```bash
kzf hardware   # Probe CPU brand, Intel Core/Xeon & AMD Zen 3/4/5, AVX-512 flags, and march
kzf bench      # Automatically compiles with -Doptimize=ReleaseFast -Dcpu=<detected_cpu> and runs benchmark
```

### 2. Syntax Guard & Linter (`kzf doctor`)
Scan files or projects for deprecated patterns before compiling. It exits non-zero on findings, so chain it before a build:
```bash
kzf doctor                    # Scan current project (default: Zig 0.16 rules)
kzf doctor path/to/file       # Scan a specific file or directory
kzf doctor src --zig-version 0.17   # Target a different Zig release
kzf doctor src --rules my.json      # Add project/fork-specific rules on top of the built-ins
kzf doctor src && zig build   # Gate the build on a clean scan
```
Catches (the `0.16` rule set — rules live in `src/rules.json`, selectable by `--zig-version`):
- Deprecated `std.heap.GeneralPurposeAllocator`
- Removed `std.time.nanoTimestamp` / `milliTimestamp`
- Misplaced `.root_source_file` in `b.addExecutable` / `b.addTest` without `b.createModule`
- Removed `std.io.getStdOut()` / `getStdIn()`
- Deprecated `std.Target.CrossTarget` and `std.mem.tokenize`

Note: it is a pattern-based pre-flight, not full semantic analysis — a clean scan means none of these patterns were found, not that the project compiles. Always run `zig build` too.

### 3. Scaffolding New Projects (`kzf new`)
Never write raw Zig boilerplate from scratch. Use `kzf new`:
```bash
# High-Performance System CLI Utility (std.process.Init modern runtime harness)
kzf new cli <project_name>

# AVX-512 SIMD Neural Tensor Vector Engine (@Vector(16, f32) Dot Product & RMSNorm)
kzf new simd <project_name>

# Zero-Copy Lock-Free SPSC Shared Memory Ring Buffer
kzf new shm-ring <project_name>

# Ultra-Low-Latency Event Queue Engine (Lock-Free SPSC Ring Buffer, Fixed-Point Ticks)
kzf new hft <project_name>

# Silicon-Aware NUMA & Worker Pool
kzf new numa-worker <project_name>

# Zero-Allocation WebMCP JSON-RPC 2.0 Microservice
kzf new webmcp-server <project_name>

# Crash-Consistent Block Storage & Sector-Aligned WAL Journal (CRC32)
kzf new wal-storage <project_name>
```

---

## 🔌 Model Context Protocol (MCP) Stdio Server

KZF includes a built-in JSON-RPC 2.0 stdio MCP server for direct tool-calling:

```bash
kzf mcp
```

### Connecting Claude Desktop
Add to `%APPDATA%\Claude\claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "kzf": {
      "command": "kzf",
      "args": ["mcp"]
    }
  }
}
```

### Exposed MCP Tools
- `kzf_inspect_hardware`: Returns CPU architecture (Intel Core/Xeon & AMD Zen), AVX-512 extensions, and `-Dcpu=` recommendations.
- `kzf_list_templates`: Returns production template descriptions and feature breakdowns.
- `kzf_get_targets`: Returns optimized compilation commands for native, Intel (x86_64_v3/v4), and AMD (znver4/5) targets.
- `kzf_doctor`: Scans files/projects for deprecated syntax (rule set selectable via `zig_version`) and returns fixes directly to Claude.
- `kzf_scaffold_project`: Scaffolds a new project in the active directory.

---

## ⚠️ Zig 0.16.0 Rules & Invariants
- **Runtime Entrypoint**: Use `pub fn main(init: std.process.Init) !void` for standard CLI binaries (`init.io` for I/O, `init.arena.allocator()` for allocations, `init.minimal.args.toSlice(arena)` for CLI arguments).
- **Output**: Use `std.debug.print(...)` for unbuffered terminal output or `Io.File.Writer.init(.stdout(), io, &buf)` for buffered stream writes.
- **Build Graphs**: `b.addExecutable` and `b.addTest` MUST define `.root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize })`. Do not pass `.root_source_file` directly to `b.addExecutable`.
- **Clocks & Cycles**: `std.time.nanoTimestamp()` is removed in 0.16.0. Use x86_64 inline assembly `rdtsc` or Windows QPC (`RtlQueryPerformanceCounter`).
