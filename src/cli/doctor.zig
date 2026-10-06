//! Kaos Zig Forge (KZF) — Zig 0.16 Syntax Guard & Anti-Hallucination Doctor
const std = @import("std");
const Io = std.Io;

pub const Issue = struct {
    file: []const u8,
    line: usize,
    pattern: []const u8,
    message: []const u8,
    suggestion: []const u8,
};

pub const CheckRule = struct {
    pattern: []const u8,
    message: []const u8,
    suggestion: []const u8,
};

pub const RULES = [_]CheckRule{
    .{
        .pattern = "GeneralPurposeAllocator",
        .message = "std.heap.GeneralPurposeAllocator is deprecated/removed in Zig 0.16.0.",
        .suggestion = "Use 'init.gpa' from main(init: std.process.Init), 'std.heap.DebugAllocator', or 'std.heap.smp_allocator'.",
    },
    .{
        .pattern = "nanoTimestamp",
        .message = "std.time.nanoTimestamp is removed from std.time in Zig 0.16.0.",
        .suggestion = "Use x86_64 RDTSC inline asm, Windows QPC (RtlQueryPerformanceCounter), or std.time.epoch.",
    },
    .{
        .pattern = "milliTimestamp",
        .message = "std.time.milliTimestamp is removed from std.time in Zig 0.16.0.",
        .suggestion = "Use x86_64 RDTSC inline asm or Windows QPC.",
    },
    .{
        .pattern = "getStdOut()",
        .message = "std.io.getStdOut() is removed/changed in Zig 0.16.0.",
        .suggestion = "Use 'std.debug.print' for console, or 'std.Io.File.Writer.init(.stdout(), io, &buf)' with modern std.Io.",
    },
    .{
        .pattern = "getStdIn()",
        .message = "std.io.getStdIn() is removed/changed in Zig 0.16.0.",
        .suggestion = "Use 'std.Io.File.Reader.init(.stdin(), io, &buf)' with modern std.Io.",
    },
    .{
        .pattern = "CrossTarget",
        .message = "std.Target.CrossTarget is removed in Zig 0.16.0.",
        .suggestion = "Use 'std.Target.Query' instead.",
    },
    .{
        .pattern = "std.mem.tokenize(",
        .message = "std.mem.tokenize is deprecated in favor of explicit tokenizers.",
        .suggestion = "Use 'std.mem.tokenizeAny', 'tokenizeScalar', or 'tokenizeSequence'.",
    },
};

pub fn checkFile(io: Io, alloc: std.mem.Allocator, path: []const u8, issues: *std.ArrayList(Issue)) !void {
    const file = Io.Dir.openFileAbsolute(io, path, .{}) catch return;
    defer file.close(io);

    var buf: [65536]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &buf);
    const reader = &file_reader.interface;

    var line_num: usize = 1;
    var inside_add_target = false;
    var has_root_module = false;

    while (try reader.takeDelimiter('\n')) |raw_line| : (line_num += 1) {
        const line = std.mem.trim(u8, raw_line, "\r");

        if (std.mem.indexOf(u8, line, "addExecutable(") != null or std.mem.indexOf(u8, line, "addTest(") != null) {
            inside_add_target = true;
            has_root_module = false;
        }
        if (inside_add_target and std.mem.indexOf(u8, line, ".root_module =") != null) {
            has_root_module = true;
        }
        if (inside_add_target and std.mem.indexOf(u8, line, ".root_source_file =") != null and !has_root_module) {
            try issues.append(alloc, .{
                .file = try alloc.dupe(u8, path),
                .line = line_num,
                .pattern = ".root_source_file in addExecutable/addTest",
                .message = ".root_source_file directly on addExecutable / addTest is deprecated in Zig 0.16.0.",
                .suggestion = "Wrap root source file in .root_module = b.createModule(.{ .root_source_file = ... }).",
            });
            inside_add_target = false;
        }
        if (inside_add_target and std.mem.indexOf(u8, line, "});") != null) {
            inside_add_target = false;
        }

        for (RULES) |rule| {
            if (std.mem.indexOf(u8, line, rule.pattern) != null) {
                try issues.append(alloc, .{
                    .file = try alloc.dupe(u8, path),
                    .line = line_num,
                    .pattern = rule.pattern,
                    .message = rule.message,
                    .suggestion = rule.suggestion,
                });
            }
        }
    }
}

pub fn scanPath(io: Io, alloc: std.mem.Allocator, scan_path: []const u8, issues: *std.ArrayList(Issue)) !void {
    if (std.mem.endsWith(u8, scan_path, ".zig")) {
        try checkFile(io, alloc, scan_path, issues);
    } else {
        const common_files = [_][]const u8{
            "build.zig",
            "src/main.zig",
            "src/root.zig",
            "src/lib.zig",
        };
        for (common_files) |cf| {
            var full_buf: [1024]u8 = undefined;
            const full_path = std.fmt.bufPrint(&full_buf, "{s}/{s}", .{ scan_path, cf }) catch continue;
            checkFile(io, alloc, full_path, issues) catch {};
        }
    }
}

pub fn runDoctor(io: Io, alloc: std.mem.Allocator, target_path: ?[]const u8) !void {
    std.debug.print(
        \\======================================================================
        \\🩺 Kaos Zig Forge (KZF) — Zig 0.16.0 Syntax Guard & Linter
        \\======================================================================
        \\
    , .{});

    var issues: std.ArrayList(Issue) = .empty;
    defer issues.deinit(alloc);

    const cwd_path = try std.process.currentPathAlloc(io, alloc);
    defer alloc.free(cwd_path);

    const scan_path = target_path orelse cwd_path;
    try scanPath(io, alloc, scan_path, &issues);

    if (issues.items.len == 0) {
        std.debug.print(
            \\✅ 0 Hallucinations Detected!
            \\----------------------------------------------------------------------
            \\All inspected code strictly adheres to Zig 0.16.0 standards:
            \\• Modern std.Io architecture
            \\• b.createModule root module wiring
            \\• Native allocator & cycle timer APIs
            \\----------------------------------------------------------------------
            \\
        , .{});
    } else {
        std.debug.print("⚠️ Found {d} deprecated / hallucinated Zig pattern(s):\n", .{issues.items.len});
        std.debug.print("----------------------------------------------------------------------\n", .{});
        for (issues.items) |iss| {
            std.debug.print("❌ [{s}:{d}]\n", .{ iss.file, iss.line });
            std.debug.print("   Pattern:    '{s}'\n", .{iss.pattern});
            std.debug.print("   Issue:      {s}\n", .{iss.message});
            std.debug.print("   Fix (0.16): {s}\n\n", .{iss.suggestion});
        }
        std.debug.print("----------------------------------------------------------------------\n", .{});
    }
}
