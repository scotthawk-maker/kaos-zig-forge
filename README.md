<p align="center">
  <img src="assets/zig-mark-red.svg" alt="Red Zig Logo" width="96" height="88" />
</p>

<h1 align="center">🦅 Kaos Zig Forge (KZF)</h1>

<p align="center">
  <strong>The Zero-Friction Project Scaffolder, Linter & Hardware Inspector for Zig 0.16.0</strong>
  <br />
  <em>Streamlining compilation on Windows & Linux with built-in checks and anti-hallucination guards.</em>
</p>

<p align="center">
  <a href="#-the-story"><img src="https://img.shields.io/badge/Zig-0.16.0-red?logoColor=white" alt="Zig 0.16.0" /></a>
  <a href="#-production-templates"><img src="https://img.shields.io/badge/Templates-7%20Production-blue" alt="Templates" /></a>
  <a href="#-syntax-guard--linter-kzf-doctor"><img src="https://img.shields.io/badge/Linter-Anti--Hallucination-brightgreen" alt="Linter" /></a>
  <a href="#-silicon-inspection-kzf-hardware"><img src="https://img.shields.io/badge/Silicon-AVX--512%20Auto--Tune-orange" alt="Silicon" /></a>
  <a href="#-model-context-protocol-mcp-server"><img src="https://img.shields.io/badge/AI%20Agent-MCP%20Ready-purple" alt="MCP Ready" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-black" alt="License" /></a>
</p>

---

## 📖 The Story

It started late one night while watching my AI coding agent try to build a Zig project. 

Zig evolves rapidly — between `0.14`, `0.15`, and bleeding-edge `0.16`, massive parts of the standard library were refactored: `getStdOut()` was removed, `GeneralPurposeAllocator` was overhauled, and `root_source_file` in `addExecutable` broke in favor of `b.createModule`. Because most tutorials and LLM training data are stuck on older Zig versions, my agent kept hallucinating deprecated APIs, hitting compiler walls, and wandering down rabbit holes trying random workarounds.

I got tired of watching my agent wander and wrestling with compiler errors every time we wanted to build something new.

I wanted a rock-solid foundation where both developers and autonomous AI agents could hit the ground running with zero friction:
* **Templates that compile on the first try** on Windows and Linux, pre-wired with modern `b.createModule` build graphs and leak-checked allocators.
* **An automated anti-hallucination syntax doctor (`kzf doctor`)** to stop agents and developers from using dead APIs *before* the compiler even complains.
* **Direct CPU silicon auto-tuning (`kzf hardware`)** via inline assembly so you never have to guess `-Dcpu=...` optimization flags.
* **A native MCP server (`kzf mcp`)** so AI agents (Claude Desktop, Cursor, Antigravity) can scaffold verified, runnable Zig 0.16 projects directly through tool calls instead of guessing.

That is how **Kaos Zig Forge (KZF)** was born.

---

## ⚡ Quickstart & Global CLI

`kzf` compiles into a single, self-contained native binary (`kzf.exe` on Windows, `kzf` on Linux) with zero runtime dependencies.

```bash
# Verify installation & version
kzf version

# Inspect CPU silicon and get optimal compiler flags (-Dcpu=...)
kzf hardware

# Scan any Zig file or directory for deprecated APIs before compiling
kzf doctor

# List all available production templates
kzf list

# View high-performance compilation targets
kzf targets
```

---

## 🏎️ Production Templates

Scaffold robust, verified Zig 0.16 codebases in seconds:

```bash
# 1. High-Performance System CLI (Modern std.process.Init, leak-checked allocator)
kzf new cli my_cli_app

# 2. AVX-512 SIMD Neural Tensor Vector Engine (@Vector(16, f32) Dot Products)
kzf new simd my_tensor_engine

# 3. Zero-Copy Lock-Free SPSC Shared Memory Ring Buffer (Cacheline-padded, Windows SHM / POSIX)
kzf new shm-ring my_ipc_queue

# 4. Ultra-Low-Latency Event Queue & SPSC Engine (Fixed-point 64-bit event ingestion)
kzf new hft my_event_engine

# 5. Silicon-Aware NUMA & Worker Pool (CPU core affinity pinning, work-stealing)
kzf new numa-worker my_worker_pool

# 6. Zero-Allocation WebMCP JSON-RPC 2.0 AI Agent Server (Claude Desktop / Cursor ready)
kzf new webmcp-server my_mcp_service

# 7. Crash-Consistent Block Storage & WAL Journal (Sector-aligned, hardware CRC32 checksums)
kzf new wal-storage my_wal_journal
```

---

## 🩺 Syntax Guard & Linter (`kzf doctor`)

AI models and outdated docs frequently hallucinate deprecated Zig APIs. `kzf doctor` acts as an automated syntax guard that scans your code and provides exact modern replacements:

```bash
kzf doctor src/main.zig
```

Checks performed:
* Replaces deprecated `GeneralPurposeAllocator` with `init.gpa` or `DebugAllocator`.
* Catches removed `std.time.nanoTimestamp` / `milliTimestamp` and suggests cycle timers (`rdtsc`, Windows QPC).
* Flags outdated `b.addExecutable` missing `b.createModule`.
* Detects removed `std.io.getStdOut()` / `getStdIn()` in favor of modern `std.Io`.
* Replaces deprecated `std.mem.tokenize` with `tokenizeAny` / `tokenizeScalar`.

---

## 🛡️ Silicon Inspection (`kzf hardware`)

Directly probes your CPU registers via inline x86_64 assembly:
* **Modern x86_64 Silicon**: First-class detection for both Intel Core / Xeon and AMD Zen 3/4/5 microarchitectures.
* **Vector Extensions**: Probes AVX-512 foundation (`AVX-512F`, `VL`, `BW`, `DQ`), AVX2, and FMA3.
* **Neural & Crypto Acceleration**: Probes AVX-512 VNNI (`VPDPBUSD`), BF16, VBMI, Vector AES (VAES), and hardware SHA.
* **Cache Topology**: Parses core cache line size and L1d/L2/L3 topology (Intel Deterministic Leaf 4 & AMD Leafs 0x80000005/6).
* **Compiler Flag Recommendations**: Recommends the exact `-Dcpu=...` flag (`native`, `x86_64_v3` for Intel Core, `x86_64_v4` for Intel Xeon, `znver4` / `znver5` for AMD Zen) to squeeze peak performance from your hardware.

---

## 🔌 Model Context Protocol (MCP) Server

KZF includes a built-in JSON-RPC 2.0 stdio MCP server for direct AI agent integration with Claude Desktop, Claude Code, Cursor, and Antigravity:

```bash
kzf mcp
```

### Claude Desktop Configuration
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

### Exposed AI Agent Tools
* `kzf_inspect_hardware`: Probes CPU silicon extensions and returns compiler optimization flags.
* `kzf_list_templates`: Returns production starter templates and descriptions.
* `kzf_get_targets`: Returns optimized compilation targets and flags.
* `kzf_doctor`: Scans files/projects for deprecated syntax and suggests fixes directly to AI agents.
* `kzf_scaffold_project`: Autonomously scaffolds new production Zig 0.16 projects.

---

## 🔄 Compiler Version Flexibility (Migrating to Zig 0.17.0+)

> [!IMPORTANT]
> **Built for Zig 0.16.0**: This release of Kaos Zig Forge (KZF) is rigorously verified, benchmarked, and battle-tested specifically on **Zig 0.16.0**. 

### Selecting a target version (`--zig-version`)

The `doctor` rule set is **data, not hardcoded** — it lives in [`src/rules.json`](src/rules.json), and each rule is tagged with the Zig version it applies `since`. Pick the target version at runtime:

```bash
kzf doctor src/              # default: Zig 0.16 rules
kzf doctor src/ --zig-version 0.17   # 0.16 rules still apply + any tagged "0.17"
kzf doctor src/ --zig-version 0.15   # only rules introduced by 0.15 or earlier
```

A rule fires when the target version is **>= its `since`**, so an API removed in 0.16 keeps flagging for 0.17 and beyond — you never lose coverage by moving forward. The MCP `kzf_doctor` tool takes the same selector as an optional `zig_version` argument.

**Adding support for a new Zig release is a data change, not a code change:** append rules to `src/rules.json` with the new version as their `since` (existing rules keep applying) and rebuild. No linter logic to touch — ideal for community PRs.

If you additionally want to compile KZF or scaffolded projects on a newer compiler (such as bleeding-edge master), here is the checklist to adapt the build:

### 1. Update Package Manifest (`build.zig.zon`)
Adjust the minimum compiler requirement to allow newer toolchains:
```zig
.minimum_zig_version = "0.17.0",
```

### 2. Run the Syntax Guard (`kzf doctor`)
Use `kzf doctor` to scan for any standard library APIs that Zig may have shifted between 0.16.0 and 0.17.0:
```bash
kzf doctor src/
```

### 3. Verify Build Module Wiring (`build.zig`)
Ensure your `build.zig` adheres to the current target module convention:
```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const exe = b.addExecutable(.{
    .name = "my_app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
```

### 4. Execute Full Verification Test Suite
Run the test harness to confirm all templates compile cleanly under your compiler version:
```bash
zig build test
```

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
