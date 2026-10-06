//! Kaos Zig Forge (KZF) — Core Library
const std = @import("std");

pub const cpuid = @import("hardware/cpuid.zig");
pub const args = @import("cli/args.zig");
pub const commands = @import("cli/commands.zig");
pub const mcp = @import("cli/mcp.zig");
pub const doctor = @import("cli/doctor.zig");
pub const bench = @import("cli/bench.zig");

pub const templates = struct {
    pub const system_cli = @import("templates/system_cli.zig");
    pub const simd_tensor = @import("templates/simd_tensor.zig");
    pub const shm_ring = @import("templates/shm_ring.zig");
    pub const hft_engine = @import("templates/hft_engine.zig");
    pub const numa_worker = @import("templates/numa_worker.zig");
    pub const webmcp_server = @import("templates/webmcp_server.zig");
    pub const wal_storage = @import("templates/wal_storage.zig");
};

test "all templates compile and generate" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try templates.system_cli.generate(tmp.dir, io, "test_cli");
    try templates.simd_tensor.generate(tmp.dir, io, "test_simd");
    try templates.shm_ring.generate(tmp.dir, io, "test_shm");
    try templates.hft_engine.generate(tmp.dir, io, "test_hft");
    try templates.numa_worker.generate(tmp.dir, io, "test_numa");
    try templates.webmcp_server.generate(tmp.dir, io, "test_mcp");
    try templates.wal_storage.generate(tmp.dir, io, "test_wal");
}
