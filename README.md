<p align="center">
  <img src="assets/zig-mark-red.svg" alt="Red Zig Logo" width="96" height="88" />
</p>

<h1 align="center">🦅 Kaos Zig Forge (KZF)</h1>

<p align="center">
  <strong>A little Zig 0.16 toolkit I threw together on a weekend: project scaffolder, deprecation linter, and CPU inspector.</strong>
  <br />
  <em>Mostly so my AI coding agent would quit inventing standard-library APIs that got removed three versions ago.</em>
</p>

<p align="center">
  <a href="https://github.com/scotthawk-maker/kaos-zig-forge/actions/workflows/ci.yml"><img src="https://github.com/scotthawk-maker/kaos-zig-forge/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="#-the-story"><img src="https://img.shields.io/badge/Zig-0.16.0-red?logoColor=white" alt="Zig 0.16.0" /></a>
  <a href="#-production-templates"><img src="https://img.shields.io/badge/Templates-7%20Production-blue" alt="Templates" /></a>
  <a href="#-syntax-guard--linter-kzf-doctor"><img src="https://img.shields.io/badge/Linter-Deprecation%20Guard-brightgreen" alt="Linter" /></a>
  <a href="#-silicon-inspection-kzf-hardware"><img src="https://img.shields.io/badge/Silicon-AVX--512%20Auto--Tune-orange" alt="Silicon" /></a>
  <a href="#-model-context-protocol-mcp-server"><img src="https://img.shields.io/badge/AI%20Agent-MCP%20Ready-purple" alt="MCP Ready" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-black" alt="License" /></a>
</p>

---

## 📖 The Story

This started late one night watching my AI coding agent flail at a Zig project.

Zig moves fast. Between `0.14`, `0.15`, and `0.16`, big chunks of the std library got reshuffled — `getStdOut()` disappeared, `GeneralPurposeAllocator` changed, and passing `root_source_file` straight to `addExecutable` stopped working (it wants `b.createModule` now). Trouble is, most tutorials and most of what the LLMs were trained on are stuck on older Zig, so my agent kept confidently writing dead APIs, slamming into compiler errors, and then trying random nonsense to dig out.

I got tired of babysitting it, so over a weekend I built the thing I wished existed:

* **Templates that actually compile the first time** on Windows and Linux, already wired up with `b.createModule` and leak-checked allocators — so there's a known-good starting point instead of a blank file.
* **A deprecation linter (`kzf doctor`)** that catches the usual dead-API mistakes *before* the compiler does, and tells you what to use instead.
* **A CPU probe (`kzf hardware`)** so I stop guessing `-Dcpu=...` flags.
* **An MCP server (`kzf mcp`)** so the agent can scaffold and lint through tool calls instead of guessing.

That's it. It's a weekend tool that grew legs. It won't replace the compiler or `zls` — it just gets you (or your agent) unstuck faster. PRs and bug reports welcome; no promises on turnaround.

---

## ⚡ Quickstart & Global CLI

`kzf` builds to one self-contained binary (`kzf.exe` on Windows, `kzf` on Linux), no runtime deps. Drop it on your `PATH` and go:

```bash
# What am I running?
kzf version

# What's this CPU got? (and the -Dcpu=... flag to match)
kzf hardware

# Check a file or dir for dead APIs before building (exits non-zero if it finds any)
kzf doctor src/

# What templates are there?
kzf list

# Show the compile targets
kzf targets
```

---

## 🏎️ Production Templates

Starter projects that compile on the first try — grab one instead of staring at an empty `main.zig`:

```bash
# 1. Plain system CLI (modern std.process.Init, leak-checked allocator)
kzf new cli my_cli_app

# 2. AVX-512 SIMD tensor math (@Vector(16, f32) dot products)
kzf new simd my_tensor_engine

# 3. Lock-free SPSC shared-memory ring buffer (cacheline-padded, Windows SHM / POSIX)
kzf new shm-ring my_ipc_queue

# 4. Low-latency event queue (fixed-point 64-bit ticks)
kzf new hft my_event_engine

# 5. NUMA-aware worker pool (core pinning, work-stealing)
kzf new numa-worker my_worker_pool

# 6. Tiny WebMCP JSON-RPC 2.0 agent server (Claude Desktop / Cursor ready)
kzf new webmcp-server my_mcp_service

# 7. Crash-consistent block storage + WAL journal (sector-aligned, CRC32)
kzf new wal-storage my_wal_journal
```

They're starting points, not a framework — rip out whatever you don't need.

---

## 🩺 Syntax Guard & Linter (`kzf doctor`)

LLMs and old tutorials keep reaching for Zig APIs that a newer release deleted, and you don't find out until the compiler yells. `kzf doctor` is a quick pass that catches the common ones up front and tells you the modern replacement. It's a dumb-but-fast pattern check — not a substitute for the compiler or `zls`. Run it *before* `zig build`, not instead of it.

```bash
kzf doctor src/                       # scan a file or dir (default: Zig 0.16 rules)
kzf doctor src/ --zig-version 0.17    # target a different release (see below)
kzf doctor src/ && zig build          # chain it — doctor exits non-zero if it finds something
```

What the `0.16` rule set looks for (rules live in [`src/rules.json`](src/rules.json)):
* `std.heap.GeneralPurposeAllocator` → `init.gpa` / `std.heap.DebugAllocator`
* removed `std.time.nanoTimestamp` / `milliTimestamp` → cycle timers (`rdtsc`, Windows QPC)
* `b.addExecutable` / `b.addTest` missing `.root_module = b.createModule(...)`
* removed `std.io.getStdOut()` / `getStdIn()` → modern `std.Io`
* `std.Target.CrossTarget` → `std.Target.Query`
* deprecated `std.mem.tokenize` → `tokenizeAny` / `tokenizeScalar`

It prints each hit with a fix and exits `1`, so it slots into CI or a pre-commit hook without any glue. The rules are plain data, pickable per Zig version — see [Compiler Version Flexibility](#-compiler-version-flexibility-migrating-to-zig-0170).

---

## 🛡️ Silicon Inspection (`kzf hardware`)

Reads your CPU straight from `CPUID` via inline x86_64 asm, so you don't have to look anything up:
* **CPU detection**: Intel Core / Xeon and AMD Zen 3/4/5.
* **Vector extensions**: AVX-512 (`AVX-512F`, `VL`, `BW`, `DQ`), AVX2, FMA3.
* **Fancy stuff**: AVX-512 VNNI (`VPDPBUSD`), BF16, VBMI, Vector AES (VAES), hardware SHA.
* **Cache layout**: cache-line size and L1d/L2/L3 topology (Intel leaf 4 & AMD leafs `0x80000005/6`).
* **The flag you actually wanted**: the matching `-Dcpu=...` (`native`, `x86_64_v3` for Intel Core, `x86_64_v4` for Xeon, `znver4` / `znver5` for Zen).

---

## 🔌 Model Context Protocol (MCP) Server

There's a built-in stdio MCP server (JSON-RPC 2.0) so an agent — Claude Desktop, Claude Code, Cursor, Antigravity — can call this stuff directly instead of guessing:

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

### The tools it exposes
* `kzf_inspect_hardware`: CPU extensions + the compiler flags to match.
* `kzf_list_templates`: the starter templates and what they are.
* `kzf_get_targets`: compile targets and flags.
* `kzf_doctor`: scans for dead APIs and hands back fixes. Optional `zig_version` picks the rule set.
* `kzf_scaffold_project`: drops a new project into the current directory.

---

## 🔄 Compiler Version Flexibility (Migrating to Zig 0.17.0+)

> [!NOTE]
> I built and run this on **Zig 0.16.0** — that's what it's tested against. Newer Zig probably works, but you're a little ahead of me if you're on master.

### Picking a target version (`--zig-version`)

The `doctor` rules aren't hardcoded — they live in [`src/rules.json`](src/rules.json), each tagged with the Zig version it applies `since`. Pick one at runtime:

```bash
kzf doctor src/              # default: Zig 0.16 rules
kzf doctor src/ --zig-version 0.17   # 0.16 rules still apply + anything tagged "0.17"
kzf doctor src/ --zig-version 0.15   # only rules from 0.15 or earlier
```

A rule fires when your target is **>= its `since`**, so something removed in 0.16 keeps getting flagged on 0.17 and up — moving forward never drops coverage. The MCP `kzf_doctor` tool takes the same thing as an optional `zig_version` argument.

**Teaching it about a new Zig release is just editing data:** add rules to `src/rules.json` with the new version as their `since` (the old ones keep applying) and rebuild. No linter code to touch — easy PR if you hit a new deprecation before I do.

If you also want to build KZF itself on a newer compiler (like bleeding-edge master), here's the rough checklist:

### 1. Bump the manifest (`build.zig.zon`)
```zig
.minimum_zig_version = "0.17.0",
```

### 2. Run the linter on yourself
```bash
kzf doctor src/
```

### 3. Sanity-check your `build.zig` wiring
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

### 4. Build and test
```bash
zig build test
```

---

## 📄 License

MIT — do whatever, see [LICENSE](LICENSE). It's a weekend project; use at your own risk.
