//! CPUID & Silicon Inspection for Modern x86_64 (Intel Core / Xeon & AMD Zen 3/4/5)
const std = @import("std");

pub const CpuInfo = struct {
    brand: [48]u8 = [_]u8{0} ** 48,
    brand_len: usize = 0,
    // ISA Vector Extensions
    has_avx512f: bool = false,
    has_avx512vl: bool = false,
    has_avx512bw: bool = false,
    has_avx512dq: bool = false,
    has_avx512_vnni: bool = false,
    has_avx512_bf16: bool = false,
    has_avx512_vbmi: bool = false,
    has_avx512_vbmi2: bool = false,
    has_avx2: bool = false,
    has_fma: bool = false,
    has_vaes: bool = false,
    has_vpclmul: bool = false,
    has_sha: bool = false,
    is_amd: bool = false,
    is_intel: bool = false,
    is_zen4_or_newer: bool = false,
    is_zen5: bool = false,
    is_dual_ccd: bool = false,
    nodes_per_processor: u32 = 1,
    // Cache Topology
    l1d_size_kb: u32 = 32,
    l1d_line_bytes: u32 = 64,
    l2_size_kb: u32 = 1024,
    l3_size_kb: u32 = 16384,
    // AMD SOG Microarchitectural Levers & Instruction Latencies
    fma_latency_cycles: u32 = 4,
    vnni_latency_cycles: u32 = 4,
    vnni_throughput: u32 = 1,
    bf16_latency_cycles: u32 = 4,
    bf16_throughput: u32 = 1,
    optimal_unroll_factor: u32 = 4,
    loop_alignment_bytes: u32 = 64,
    op_cache_capacity_uops: u32 = 6750,
    prefetch_stride_bytes: u32 = 384, // 6 cache lines (AMD SOG sweet spot)
    non_temporal_threshold_bytes: usize = 512 * 1024, // 512 KB
    simd_pipe_width_bits: u32 = 512,
    dual_fused_256: bool = true,
    zero_downclock_avx512: bool = true,
    recommended_march: []const u8 = "native",

    pub fn inspect() CpuInfo {
        var info = CpuInfo{};

        if (builtin.cpu.arch != .x86_64) {
            return info;
        }

        // 1. Vendor string
        const vendor_res = cpuid(0, 0);
        var vendor: [12]u8 = undefined;
        std.mem.writeInt(u32, vendor[0..4], vendor_res.ebx, .little);
        std.mem.writeInt(u32, vendor[4..8], vendor_res.edx, .little);
        std.mem.writeInt(u32, vendor[8..12], vendor_res.ecx, .little);

        if (std.mem.eql(u8, &vendor, "AuthenticAMD")) {
            info.is_amd = true;
        } else if (std.mem.eql(u8, &vendor, "GenuineIntel")) {
            info.is_intel = true;
        }

        // 2. Features Leaf 1
        const leaf1 = cpuid(1, 0);
        info.has_fma = (leaf1.ecx & (1 << 12)) != 0;

        // Family / Model calculation
        const family_base = (leaf1.eax >> 8) & 0xF;
        const family_ext = (leaf1.eax >> 20) & 0xFF;
        const actual_family = family_base + family_ext;

        if (info.is_amd and actual_family == 0x19) {
            info.is_zen4_or_newer = true;
            info.recommended_march = "znver4";
            info.dual_fused_256 = true;
            info.zero_downclock_avx512 = true;
        } else if (info.is_amd and actual_family >= 0x1A) {
            info.is_zen4_or_newer = true;
            info.is_zen5 = true;
            info.recommended_march = "znver5";
            info.dual_fused_256 = false; // Zen 5 has full 512-bit native datapath
            info.zero_downclock_avx512 = true;
        }

        // 3. Extended Features Leaf 7, Sub-leaf 0
        const leaf7_0 = cpuid(7, 0);
        info.has_avx2 = (leaf7_0.ebx & (1 << 5)) != 0;
        info.has_avx512f = (leaf7_0.ebx & (1 << 16)) != 0;
        info.has_avx512dq = (leaf7_0.ebx & (1 << 17)) != 0;
        info.has_sha = (leaf7_0.ebx & (1 << 29)) != 0;
        info.has_avx512bw = (leaf7_0.ebx & (1 << 30)) != 0;
        info.has_avx512vl = (leaf7_0.ebx & (1 << 31)) != 0;

        info.has_avx512_vbmi = (leaf7_0.ecx & (1 << 1)) != 0;
        info.has_avx512_vbmi2 = (leaf7_0.ecx & (1 << 6)) != 0;
        info.has_vaes = (leaf7_0.ecx & (1 << 9)) != 0;
        info.has_vpclmul = (leaf7_0.ecx & (1 << 10)) != 0;
        info.has_avx512_vnni = (leaf7_0.ecx & (1 << 11)) != 0;

        // 4. Extended Features Leaf 7, Sub-leaf 1 (BF16)
        const leaf7_1 = cpuid(7, 1);
        info.has_avx512_bf16 = (leaf7_1.eax & (1 << 5)) != 0;

        if (!info.is_amd) {
            if (info.has_avx512f and info.has_avx512vl) {
                info.recommended_march = "x86_64_v4";
            } else if (info.has_avx2) {
                info.recommended_march = "x86_64_v3";
            } else {
                info.recommended_march = "native";
            }
        }

        // 5. Cache Topology (AMD Leafs 0x80000005/6 or Intel Deterministic Leaf 4)
        if (info.is_amd) {
            const l1_leaf = cpuid(0x80000005, 0);
            if (l1_leaf.ecx != 0) {
                info.l1d_size_kb = l1_leaf.ecx >> 24;
                info.l1d_line_bytes = l1_leaf.ecx & 0xFF;
            }

            const l2_l3_leaf = cpuid(0x80000006, 0);
            if (l2_l3_leaf.ecx != 0) {
                info.l2_size_kb = l2_l3_leaf.ecx >> 16;
            }
            if (l2_l3_leaf.edx != 0) {
                const l3_chunks = l2_l3_leaf.edx >> 18;
                if (l3_chunks > 0) {
                    info.l3_size_kb = l3_chunks * 512;
                }
            }

            // AMD Topology Leaf 0x8000001E (CCDs / Nodes)
            const top_leaf = cpuid(0x8000001E, 0);
            if (top_leaf.eax != 0 or top_leaf.ebx != 0 or top_leaf.ecx != 0) {
                info.nodes_per_processor = ((top_leaf.ecx >> 8) & 0x7) + 1;
                info.is_dual_ccd = (info.nodes_per_processor > 1);
            }
        } else {
            // Intel Deterministic Cache Parameters (Leaf 4)
            var subleaf: u32 = 0;
            while (subleaf < 8) : (subleaf += 1) {
                const leaf4 = cpuid(4, subleaf);
                const cache_type = leaf4.eax & 0x1F;
                if (cache_type == 0) break; // End of cache descriptors

                const cache_level = (leaf4.eax >> 5) & 0x7;
                const line_size = (leaf4.ebx & 0xFFF) + 1;
                const partitions = ((leaf4.ebx >> 12) & 0x3FF) + 1;
                const ways = ((leaf4.ebx >> 22) & 0x3FF) + 1;
                const sets = leaf4.ecx + 1;
                const size_kb = (ways * partitions * line_size * sets) / 1024;

                if (cache_level == 1 and (cache_type == 1 or cache_type == 3)) {
                    info.l1d_size_kb = @intCast(size_kb);
                    info.l1d_line_bytes = @intCast(line_size);
                } else if (cache_level == 2) {
                    info.l2_size_kb = @intCast(size_kb);
                } else if (cache_level == 3) {
                    info.l3_size_kb = @intCast(size_kb);
                }
            }
        }

        // 6. Processor Brand String (0x80000002 .. 0x80000004)
        var brand_buf: [48]u8 = undefined;
        var offset: usize = 0;
        var fn_id: u32 = 0x80000002;
        while (fn_id <= 0x80000004) : (fn_id += 1) {
            const b = cpuid(fn_id, 0);
            std.mem.writeInt(u32, brand_buf[offset..][0..4], b.eax, .little);
            std.mem.writeInt(u32, brand_buf[offset + 4 ..][0..4], b.ebx, .little);
            std.mem.writeInt(u32, brand_buf[offset + 8 ..][0..4], b.ecx, .little);
            std.mem.writeInt(u32, brand_buf[offset + 12 ..][0..4], b.edx, .little);
            offset += 16;
        }

        var start: usize = 0;
        while (start < 48 and brand_buf[start] == ' ') : (start += 1) {}
        var end: usize = 48;
        while (end > start and (brand_buf[end - 1] == 0 or brand_buf[end - 1] == ' ')) : (end -= 1) {}

        const len = end - start;
        @memcpy(info.brand[0..len], brand_buf[start..end]);
        info.brand_len = len;

        return info;
    }

    pub fn getBrand(self: *const CpuInfo) []const u8 {
        if (self.brand_len == 0) return "x86_64 Processor";
        return self.brand[0..self.brand_len];
    }

    pub fn getMicroarch(self: *const CpuInfo) []const u8 {
        if (self.is_zen5) return "AMD Zen 5 (znver5)";
        if (self.is_zen4_or_newer) return "AMD Zen 4 (znver4)";
        if (self.is_amd) return "AMD x86_64 (Zen/Legacy)";
        if (self.is_intel) {
            if (self.has_avx512f and self.has_avx512vl) {
                return "Intel Xeon Scalable / Core (AVX-512)";
            } else if (self.has_avx2) {
                return "Intel Core / Xeon (AVX2)";
            } else {
                return "Intel Core Legacy";
            }
        }
        return "Generic x86_64";
    }
};

const builtin = @import("builtin");

const CpuidResult = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

fn cpuid(leaf: u32, sub_leaf: u32) CpuidResult {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile (
        \\cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [sub_leaf] "{ecx}" (sub_leaf),
    );

    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}
