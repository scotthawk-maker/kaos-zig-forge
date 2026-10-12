//! Kaos Zig Forge (KZF) — Zig Syntax Guard & Anti-Hallucination Doctor
//! Deprecation rules are data (src/rules.json), each tagged with the Zig version it applies
//! `since`. --zig-version (default DEFAULT_ZIG_VERSION) selects which rules fire: a rule fires
//! when the target version >= its `since`, so an API removed in 0.16 still flags for 0.17+.
const std = @import("std");
const Io = std.Io;

/// Default target when --zig-version is not supplied.
pub const DEFAULT_ZIG_VERSION = "0.16";

const rules_json = @embedFile("../rules.json");

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
    since: []const u8 = "0.16",
};

const RulesFile = struct {
    rules: []CheckRule,
};

/// Rules loaded from the embedded rules.json (plus an optional external file), filtered to a
/// target Zig version. Caller must deinit.
pub const LoadedRules = struct {
    embedded: std.json.Parsed(RulesFile),
    external: ?std.json.Parsed(RulesFile) = null,
    external_src: ?[]u8 = null,
    rules: []CheckRule,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *LoadedRules) void {
        self.alloc.free(self.rules);
        if (self.external) |*e| e.deinit();
        if (self.external_src) |s| self.alloc.free(s);
        self.embedded.deinit();
    }
};

fn parseVer(v: []const u8) struct { major: u32, minor: u32 } {
    var it = std.mem.splitScalar(u8, v, '.');
    const maj = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
    const min = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
    return .{ .major = maj, .minor = min };
}

/// True when version `a` <= version `b` (compared by major.minor).
fn versionAtMost(a: []const u8, b: []const u8) bool {
    const pa = parseVer(a);
    const pb = parseVer(b);
    if (pa.major != pb.major) return pa.major < pb.major;
    return pa.minor <= pb.minor;
}

/// Read a whole text file (resolving a relative path against cwd). Caller frees the result.
fn readAllText(io: Io, alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var abs_buf: [4096]u8 = undefined;
    var abs_path = path;
    if (!std.fs.path.isAbsolute(path)) {
        const cwd = try std.process.currentPathAlloc(io, alloc);
        defer alloc.free(cwd);
        abs_path = try std.fmt.bufPrint(&abs_buf, "{s}/{s}", .{ cwd, path });
    }
    const file = try Io.Dir.openFileAbsolute(io, abs_path, .{});
    defer file.close(io);

    var buf: [262144]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &buf);
    const reader = &file_reader.interface;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    while (true) {
        const line = reader.takeDelimiter('\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        } orelse break;
        try out.appendSlice(alloc, line);
        try out.append(alloc, '\n');
    }
    return out.toOwnedSlice(alloc);
}

/// Load the rules that apply to `target` (since <= target): the embedded rules.json, plus — when
/// `external_path` is given — the rules from that file appended (same schema). Caller must deinit.
pub fn loadRules(io: Io, alloc: std.mem.Allocator, target: []const u8, external_path: ?[]const u8) !LoadedRules {
    const embedded = try std.json.parseFromSlice(RulesFile, alloc, rules_json, .{ .ignore_unknown_fields = true });
    errdefer embedded.deinit();

    var external: ?std.json.Parsed(RulesFile) = null;
    errdefer if (external) |*e| e.deinit();
    var external_src: ?[]u8 = null;
    errdefer if (external_src) |s| alloc.free(s);

    if (external_path) |path| {
        external_src = try readAllText(io, alloc, path);
        external = try std.json.parseFromSlice(RulesFile, alloc, external_src.?, .{ .ignore_unknown_fields = true });
    }

    var list: std.ArrayList(CheckRule) = .empty;
    errdefer list.deinit(alloc);
    for (embedded.value.rules) |rule| {
        if (versionAtMost(rule.since, target)) try list.append(alloc, rule);
    }
    if (external) |e| for (e.value.rules) |rule| {
        if (versionAtMost(rule.since, target)) try list.append(alloc, rule);
    };

    return .{
        .embedded = embedded,
        .external = external,
        .external_src = external_src,
        .rules = try list.toOwnedSlice(alloc),
        .alloc = alloc,
    };
}

pub fn checkFile(io: Io, alloc: std.mem.Allocator, path: []const u8, rules: []const CheckRule, issues: *std.ArrayList(Issue)) !void {
    // openFileAbsolute asserts an absolute path; resolve relative args (e.g. `kzf doctor src/main.zig`)
    // against cwd first, or it panics. Reporting still uses the original `path` for readability.
    var abs_buf: [4096]u8 = undefined;
    var abs_path = path;
    if (!std.fs.path.isAbsolute(path)) {
        const cwd = std.process.currentPathAlloc(io, alloc) catch return;
        defer alloc.free(cwd);
        abs_path = std.fmt.bufPrint(&abs_buf, "{s}/{s}", .{ cwd, path }) catch return;
    }
    const file = Io.Dir.openFileAbsolute(io, abs_path, .{}) catch return;
    defer file.close(io);

    var buf: [65536]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &buf);
    const reader = &file_reader.interface;

    var line_num: usize = 1;
    var inside_add_target = false;
    var has_root_module = false;

    while (try reader.takeDelimiter('\n')) |raw_line| : (line_num += 1) {
        const full = std.mem.trim(u8, raw_line, "\r");
        // ponytail: cut line comments so a pattern mentioned in a `//` note doesn't false-positive.
        // naive (ignores `//` inside a string literal); switch to std.zig.Ast if that ever bites.
        const line = if (std.mem.indexOf(u8, full, "//")) |i| full[0..i] else full;

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

        for (rules) |rule| {
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

pub fn scanPath(io: Io, alloc: std.mem.Allocator, scan_path: []const u8, rules: []const CheckRule, issues: *std.ArrayList(Issue)) !void {
    if (std.mem.endsWith(u8, scan_path, ".zig")) {
        try checkFile(io, alloc, scan_path, rules, issues);
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
            checkFile(io, alloc, full_path, rules, issues) catch {};
        }
    }
}

/// Returns the number of issues found so the caller can set a non-zero exit code (CI/agent gate).
/// zig_version selects the deprecation rule set (default DEFAULT_ZIG_VERSION).
pub fn runDoctor(io: Io, alloc: std.mem.Allocator, target_path: ?[]const u8, zig_version: ?[]const u8, rules_path: ?[]const u8) !usize {
    const target = zig_version orelse DEFAULT_ZIG_VERSION;
    std.debug.print(
        \\======================================================================
        \\🩺 Kaos Zig Forge (KZF) — Zig {s} Syntax Guard & Linter
        \\======================================================================
        \\
    , .{target});

    var loaded = loadRules(io, alloc, target, rules_path) catch |err| {
        std.debug.print("❌ Could not load rules file '{s}': {s}\n", .{ rules_path orelse "", @errorName(err) });
        std.process.exit(2);
    };
    defer loaded.deinit();

    var issues: std.ArrayList(Issue) = .empty;
    defer issues.deinit(alloc);

    const cwd_path = try std.process.currentPathAlloc(io, alloc);
    defer alloc.free(cwd_path);

    const scan_path = target_path orelse cwd_path;
    try scanPath(io, alloc, scan_path, loaded.rules, &issues);

    if (issues.items.len == 0) {
        std.debug.print(
            \\✅ 0 Hallucinations Detected!
            \\----------------------------------------------------------------------
            \\All inspected code strictly adheres to Zig {s} standards ({d} rule(s) checked):
            \\• Modern std.Io architecture
            \\• b.createModule root module wiring
            \\• Native allocator & cycle timer APIs
            \\----------------------------------------------------------------------
            \\
        , .{ target, loaded.rules.len });
    } else {
        std.debug.print("⚠️ Found {d} deprecated / hallucinated Zig pattern(s):\n", .{issues.items.len});
        std.debug.print("----------------------------------------------------------------------\n", .{});
        for (issues.items) |iss| {
            std.debug.print("❌ [{s}:{d}]\n", .{ iss.file, iss.line });
            std.debug.print("   Pattern:    '{s}'\n", .{iss.pattern});
            std.debug.print("   Issue:      {s}\n", .{iss.message});
            std.debug.print("   Fix:        {s}\n\n", .{iss.suggestion});
        }
        std.debug.print("----------------------------------------------------------------------\n", .{});
    }

    return issues.items.len;
}

test "versionAtMost compares by major.minor" {
    try std.testing.expect(versionAtMost("0.16", "0.16")); // equal -> fires
    try std.testing.expect(versionAtMost("0.16", "0.17")); // removed-in-0.16 still fires on 0.17
    try std.testing.expect(versionAtMost("0.16.3", "0.17.0")); // patch suffix ignored
    try std.testing.expect(!versionAtMost("0.16", "0.15")); // not yet removed on 0.15
    try std.testing.expect(!versionAtMost("1.0", "0.17")); // major dominates
}

test "embedded rules.json parses and filters by version" {
    const a = std.testing.allocator;
    var none = try loadRules(std.testing.io, a, "0.15", null); // nothing removed before 0.16
    defer none.deinit();
    try std.testing.expectEqual(@as(usize, 0), none.rules.len);

    var all = try loadRules(std.testing.io, a, "0.16", null);
    defer all.deinit();
    try std.testing.expect(all.rules.len > 0);
}
