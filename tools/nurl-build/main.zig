const std = @import("std");
const builtin = @import("builtin");

const LibrarySpec = struct {
    marker: []const u8,
    pkg_config: []const u8,
    fallback: []const []const u8,
};

const library_specs = [_]LibrarySpec{
    .{ .marker = "runtime.curl", .pkg_config = "libcurl", .fallback = &.{"-lcurl"} },
    .{ .marker = "runtime.openssl", .pkg_config = "openssl", .fallback = &.{ "-lssl", "-lcrypto" } },
    .{ .marker = "runtime.sqlite3", .pkg_config = "sqlite3", .fallback = &.{"-lsqlite3"} },
    .{ .marker = "runtime.pq", .pkg_config = "libpq", .fallback = &.{"-lpq"} },
    .{ .marker = "runtime.z", .pkg_config = "zlib", .fallback = &.{"-lz"} },
    .{ .marker = "runtime.zstd", .pkg_config = "libzstd", .fallback = &.{"-lzstd"} },
};

const Command = enum {
    link,
    nurl,
    wasmnurl,
    fmt,
    fmt_idempotent,
    mkdir,
    copy,
    symlink,
    marker,
    compare,
    buildwasm,
    bench_csv,
    mcp_spec_drift,
    clean,
    startdev,
    dockerpush,
};

const SystemLibMode = enum {
    native,
    windows,
    none,
};

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        std.debug.print("nurl-build: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = std.Io.Threaded.global_single_threaded.io();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return error.InvalidArgs;

    if (parseCommand(args[1])) |cmd| {
        return switch (cmd) {
            .link => runLink(init, args[2..]),
            .nurl => runNurl(init, args[2..]),
            .wasmnurl => runWasmNurl(init, args[2..]),
            .fmt => runFmt(init, args[2..]),
            .fmt_idempotent => runFmtIdempotent(init, args[2..]),
            .mkdir => runMkdir(io, args[2..]),
            .copy => runCopy(init.gpa, arena, io, args[2..]),
            .symlink => runSymlink(arena, init, io, args[2..]),
            .marker => runMarker(io, args[2..]),
            .compare => runCompare(init, io, args[2..]),
            .buildwasm => runBuildWasm(init, args[2..]),
            .bench_csv => runBenchCsv(init, args[2..]),
            .mcp_spec_drift => runMcpSpecDrift(init, args[2..]),
            .clean => runClean(init, args[2..]),
            .startdev => runStartDev(init, args[2..]),
            .dockerpush => runDockerPush(init, args[2..]),
        };
    }

    return runLink(init, args[1..]);
}

fn parseCommand(name: []const u8) ?Command {
    if (std.mem.eql(u8, name, "fmt-idempotent")) return .fmt_idempotent;
    if (std.mem.eql(u8, name, "bench-csv")) return .bench_csv;
    if (std.mem.eql(u8, name, "mcp-spec-drift")) return .mcp_spec_drift;
    return std.meta.stringToEnum(Command, name);
}

const CompileFlavor = enum {
    native,
    wasm,
};

const UserCompileConfig = struct {
    root: []const u8,
    srcfile: []const u8,
    outbase: []const u8,
    emit_ir: bool,
    emit_asm: bool,
    debug_info: bool,
    opt: []const u8,
};

fn runNurl(init: std.process.Init, args: []const []const u8) !void {
    const cfg = try parseUserCompileArgs(init, args, .native);
    try runUserCompile(init, cfg, .native);
}

fn runWasmNurl(init: std.process.Init, args: []const []const u8) !void {
    const cfg = try parseUserCompileArgs(init, args, .wasm);
    try runUserCompile(init, cfg, .wasm);
}

fn runFmt(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;

    const root_abs = try absolutePath(arena, ".");
    const nurlfmt_path = try resolveBuildOrRootBinary(init, root_abs, "nurlfmt");

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, nurlfmt_path);
    try argv.appendSlice(gpa, args);
    try runInherited(init, argv.items);
}

fn runFmtIdempotent(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("usage: nurl-build fmt-idempotent [--root <path>] [file.nu ...]\n", .{});
            std.process.exit(0);
        } else {
            std.debug.print("nurl-build: unknown fmt-idempotent arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    const root_abs = try absolutePath(arena, root);
    const nurlfmt_path = try resolveBuildOrRootBinary(init, root_abs, "nurlfmt");
    const nurlc_path = try resolveNurlc(init, root_abs);
    try ensureExists(io, nurlfmt_path, "nurlfmt");
    try ensureExists(io, nurlc_path, "nurlc");

    var files: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &files);

    if (i < args.len) {
        for (args[i..]) |arg| {
            try files.append(gpa, try gpa.dupe(u8, arg));
        }
    } else {
        try collectFmtCandidateFiles(gpa, io, root_abs, &files);
    }

    if (files.items.len == 0) {
        std.debug.print("ERROR: no .nu files selected for fmt-idempotent\n", .{});
        return error.FileNotFound;
    }
    std.sort.heap([]const u8, files.items, {}, lessThanString);

    const tmp_dir = try std.fs.path.join(arena, &.{ root_abs, "build", "fmt-idempotent.tmp" });
    try deleteTreeIfExists(io, tmp_dir);
    try ensureDirPath(io, tmp_dir);
    defer deleteTreeIfExists(io, tmp_dir) catch {};

    const pass1_path = try std.fs.path.join(arena, &.{ tmp_dir, "pass1.nu" });
    const pass2_path = try std.fs.path.join(arena, &.{ tmp_dir, "pass2.nu" });

    var fail_idemp: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &fail_idemp);
    var fail_ir: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &fail_ir);

    var first_idemp_diff: ?[]const u8 = null;
    defer if (first_idemp_diff) |msg| gpa.free(msg);
    var first_ir_diff: ?[]const u8 = null;
    defer if (first_ir_diff) |msg| gpa.free(msg);

    var checked: usize = 0;
    var skipped_ir: usize = 0;

    for (files.items) |file_path| {
        checked += 1;
        const file_abs = try resolvePathFromRoot(arena, root_abs, file_path);
        if (!pathExists(io, file_abs)) continue;

        const pass1 = try std.process.run(gpa, io, .{ .argv = &.{ nurlfmt_path, file_abs } });
        defer {
            gpa.free(pass1.stdout);
            gpa.free(pass1.stderr);
        }
        if (!runResultSucceeded(pass1.term)) {
            try fail_idemp.append(gpa, try std.fmt.allocPrint(gpa, "{s}  (pass 1 failed to format)", .{file_path}));
            continue;
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = pass1_path, .data = pass1.stdout });

        const pass2 = try std.process.run(gpa, io, .{ .argv = &.{ nurlfmt_path, pass1_path } });
        defer {
            gpa.free(pass2.stdout);
            gpa.free(pass2.stderr);
        }
        if (!runResultSucceeded(pass2.term)) {
            try fail_idemp.append(gpa, try std.fmt.allocPrint(gpa, "{s}  (pass 2 failed to format)", .{file_path}));
            continue;
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = pass2_path, .data = pass2.stdout });

        if (!std.mem.eql(u8, pass1.stdout, pass2.stdout)) {
            try fail_idemp.append(gpa, try gpa.dupe(u8, file_path));
            if (first_idemp_diff == null) {
                first_idemp_diff = try firstMismatchSummary(gpa, pass1.stdout, pass2.stdout, "fmt(x)", "fmt(fmt(x))");
            }
            continue;
        }

        if (isFmtIrSkipPath(file_path)) {
            skipped_ir += 1;
            continue;
        }

        const ir_orig = try std.process.run(gpa, io, .{ .argv = &.{ nurlc_path, file_abs } });
        defer {
            gpa.free(ir_orig.stdout);
            gpa.free(ir_orig.stderr);
        }
        if (!runResultSucceeded(ir_orig.term)) {
            skipped_ir += 1;
            continue;
        }

        const ir_fmt = try std.process.run(gpa, io, .{ .argv = &.{ nurlc_path, pass1_path } });
        defer {
            gpa.free(ir_fmt.stdout);
            gpa.free(ir_fmt.stderr);
        }
        if (!runResultSucceeded(ir_fmt.term)) {
            try fail_ir.append(gpa, try std.fmt.allocPrint(gpa, "{s}  (formatted source failed to compile)", .{file_path}));
            continue;
        }

        if (!std.mem.eql(u8, ir_orig.stdout, ir_fmt.stdout)) {
            try fail_ir.append(gpa, try gpa.dupe(u8, file_path));
            if (first_ir_diff == null) {
                first_ir_diff = try firstMismatchSummary(gpa, ir_orig.stdout, ir_fmt.stdout, "orig.ll", "fmt.ll");
            }
        }
    }

    std.debug.print("nurlfmt round-trip:\n", .{});
    std.debug.print("  checked         : {d} files\n", .{checked});
    std.debug.print("  ir-equiv covered: {d}\n", .{checked - fail_idemp.items.len - skipped_ir});
    std.debug.print("  ir-equiv skipped: {d}\n", .{skipped_ir});
    std.debug.print("  idempotence FAIL: {d}\n", .{fail_idemp.items.len});
    std.debug.print("  ir-equiv    FAIL: {d}\n", .{fail_ir.items.len});

    if (fail_idemp.items.len == 0 and fail_ir.items.len == 0) {
        std.debug.print("OK — nurlfmt is idempotent and IR-transparent across the covered tree.\n", .{});
        return;
    }

    if (fail_idemp.items.len > 0) {
        std.debug.print("\n── Idempotence failures (top 20) ─────────────────────\n", .{});
        for (fail_idemp.items[0..@min(fail_idemp.items.len, 20)]) |item| {
            std.debug.print("  {s}\n", .{item});
        }
        if (first_idemp_diff) |msg| {
            std.debug.print("\n  diff sample:\n{s}", .{msg});
        }
    }

    if (fail_ir.items.len > 0) {
        std.debug.print("\n── IR-equivalence failures (top 20) ──────────────────\n", .{});
        for (fail_ir.items[0..@min(fail_ir.items.len, 20)]) |item| {
            std.debug.print("  {s}\n", .{item});
        }
        if (first_ir_diff) |msg| {
            std.debug.print("\n  diff sample:\n{s}", .{msg});
        }
    }

    std.process.exit(1);
}

fn runMcpSpecDrift(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var mcp_file: ?[]const u8 = null;
    var html_file: ?[]const u8 = null;
    var spec_url: []const u8 = "https://modelcontextprotocol.io/specification/versioning";

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--mcp-file")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            mcp_file = args[i];
        } else if (std.mem.eql(u8, arg, "--html-file")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            html_file = args[i];
        } else if (std.mem.eql(u8, arg, "--url")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            spec_url = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("usage: nurl-build mcp-spec-drift [--root <path>] [--mcp-file <path>] [--html-file <path>] [--url <url>]\n", .{});
            std.process.exit(0);
        } else {
            std.debug.print("nurl-build: unknown mcp-spec-drift arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len != i) return error.InvalidArgs;

    const root_abs = try absolutePath(arena, root);
    const mcp_path = if (mcp_file) |path|
        try resolvePathFromRoot(arena, root_abs, path)
    else
        try std.fs.path.join(arena, &.{ root_abs, "stdlib", "ext", "mcp.nu" });
    try ensureExists(io, mcp_path, "mcp.nu");

    const mcp_source = try std.Io.Dir.cwd().readFileAlloc(io, mcp_path, gpa, .unlimited);
    defer gpa.free(mcp_source);
    const pinned = extractPinnedMcpVersionFromSource(mcp_source) orelse {
        std.debug.print("ERROR: could not extract pinned version from {s}\n", .{mcp_path});
        return error.InvalidData;
    };

    const html_bytes = if (html_file) |path| blk: {
        const html_path = try resolvePathFromRoot(arena, root_abs, path);
        try ensureExists(io, html_path, "HTML input");
        break :blk try std.Io.Dir.cwd().readFileAlloc(io, html_path, gpa, .unlimited);
    } else blk: {
        break :blk try fetchUrlBody(init, spec_url);
    };
    defer gpa.free(html_bytes);

    const current = extractCurrentMcpVersionFromHtml(html_bytes) orelse {
        std.debug.print("ERROR: could not parse current version from {s}\n", .{if (html_file == null) spec_url else html_file.?});
        return error.InvalidData;
    };

    std.debug.print("NURL pinned : {s}\n", .{pinned});
    std.debug.print("Spec current: {s}\n", .{current});

    if (std.mem.eql(u8, pinned, current)) {
        std.debug.print("OK: NURL is up-to-date with the current MCP spec revision.\n", .{});
        return;
    }

    std.debug.print("\nDRIFT: NURL pins '{s}' but the spec current is '{s}'.\n", .{ pinned, current });
    std.debug.print("Review the changelog for breaking changes:\n", .{});
    std.debug.print("  https://modelcontextprotocol.io/specification/{s}/changelog\n", .{current});
    std.debug.print("\nTo re-pin, edit stdlib/ext/mcp.nu's mcp_protocol_version helper.\n", .{});
    std.process.exit(1);
}

const BenchStage = enum {
    load,
    filter,
    sort,
    write,
    total,
};

const BenchRun = struct {
    load: i64,
    filter: i64,
    sort: i64,
    write: i64,
    total: i64,
};

fn runBenchCsv(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var runs: usize = 5;
    var append_history = true;
    var label: ?[]const u8 = null;
    var binary_path_arg: ?[]const u8 = null;
    var python_path_arg: ?[]const u8 = null;
    var data_path_arg: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--no-history")) {
            append_history = false;
        } else if (std.mem.eql(u8, arg, "--label")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            label = args[i];
        } else if (std.mem.startsWith(u8, arg, "--label=")) {
            label = arg["--label=".len..];
        } else if (std.mem.eql(u8, arg, "--binary")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            binary_path_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--python")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            python_path_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--data")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            data_path_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printBenchCsvUsage();
            std.process.exit(0);
        } else if (std.ascii.isDigit(arg[0])) {
            runs = try std.fmt.parseUnsigned(usize, arg, 10);
        } else {
            std.debug.print("nurl-build: unknown bench-csv arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (runs == 0) {
        std.debug.print("nurl-build: bench-csv run count must be >= 1\n", .{});
        return error.InvalidArgs;
    }

    const root_abs = try absolutePath(arena, root);
    const compare_dir = try std.fs.path.join(arena, &.{ root_abs, "compare" });
    const nurl_binary_name = if (builtin.os.tag == .windows) "nurl_analysis.exe" else "nurl_analysis";
    const nurl_binary = if (binary_path_arg) |path|
        try resolvePathFromRoot(arena, root_abs, path)
    else
        try std.fs.path.join(arena, &.{ compare_dir, nurl_binary_name });
    const python_path = if (python_path_arg) |path|
        try resolvePathFromRoot(arena, root_abs, path)
    else if (builtin.os.tag == .windows)
        try std.fs.path.join(arena, &.{ compare_dir, ".venv", "Scripts", "python.exe" })
    else
        try std.fs.path.join(arena, &.{ compare_dir, ".venv", "bin", "python" });
    const data_path = if (data_path_arg) |path|
        try resolvePathFromRoot(arena, root_abs, path)
    else
        try std.fs.path.join(arena, &.{ compare_dir, "test_data.csv" });
    const polars_script = try std.fs.path.join(arena, &.{ compare_dir, "polars_analysis.py" });
    const history_path = try std.fs.path.join(arena, &.{ compare_dir, "HISTORY.md" });

    if (!pathExists(io, nurl_binary)) {
        std.debug.print("missing {s} — build with zig build bench-csv\n", .{nurl_binary});
        return error.FileNotFound;
    }
    if (!pathExists(io, python_path)) {
        std.debug.print("missing {s} — create venv and pip install polars\n", .{python_path});
        return error.FileNotFound;
    }
    if (!pathExists(io, data_path)) {
        std.debug.print("missing {s} — run: {s} compare/generate_data.py\n", .{ data_path, python_path });
        return error.FileNotFound;
    }
    try ensureExists(io, polars_script, "compare/polars_analysis.py");

    const data_bytes = try std.Io.Dir.cwd().readFileAlloc(io, data_path, gpa, .unlimited);
    defer gpa.free(data_bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data_bytes, &digest, .{});

    var nurl_runs: std.ArrayList(BenchRun) = .empty;
    defer nurl_runs.deinit(gpa);
    var polars_runs: std.ArrayList(BenchRun) = .empty;
    defer polars_runs.deinit(gpa);

    std.debug.print("Running NURL {d}x ...\n", .{runs});
    for (0..runs) |run_idx| {
        const result = try std.process.run(gpa, io, .{
            .argv = &.{nurl_binary},
            .cwd = .{ .path = compare_dir },
        });
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        try ensureSuccessWithStderr(result, "NURL benchmark run failed");
        const parsed = try parseBenchRun(result.stdout, "NURL");
        try nurl_runs.append(gpa, parsed);
        printBenchRunLine(run_idx + 1, parsed);
    }

    std.debug.print("Running Polars {d}x ...\n", .{runs});
    for (0..runs) |run_idx| {
        const result = try std.process.run(gpa, io, .{
            .argv = &.{ python_path, polars_script },
            .cwd = .{ .path = compare_dir },
        });
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        try ensureSuccessWithStderr(result, "Polars benchmark run failed");
        const parsed = try parseBenchRun(result.stdout, "Polars");
        try polars_runs.append(gpa, parsed);
        printBenchRunLine(run_idx + 1, parsed);
    }

    std.debug.print("\n-- NURL --------------------------------------\n", .{});
    try printBenchStats(gpa, "load", nurl_runs.items, .load);
    try printBenchStats(gpa, "filter", nurl_runs.items, .filter);
    try printBenchStats(gpa, "sort", nurl_runs.items, .sort);
    try printBenchStats(gpa, "write", nurl_runs.items, .write);
    try printBenchStats(gpa, "total", nurl_runs.items, .total);

    std.debug.print("\n-- Polars ------------------------------------\n", .{});
    try printBenchStats(gpa, "load", polars_runs.items, .load);
    try printBenchStats(gpa, "filter", polars_runs.items, .filter);
    try printBenchStats(gpa, "sort", polars_runs.items, .sort);
    try printBenchStats(gpa, "write", polars_runs.items, .write);
    try printBenchStats(gpa, "total", polars_runs.items, .total);

    if (append_history) {
        try appendBenchHistory(init, history_path, label, data_bytes.len, digest, runs, nurl_runs.items, polars_runs.items);
        std.debug.print("\nAppended block to {s}\n", .{history_path});
    }
}

fn printBenchCsvUsage() void {
    std.debug.print(
        "usage: nurl-build bench-csv [--root <path>] [--no-history] [--label <text>] [--binary <path>] [--python <path>] [--data <path>] [runs]\n",
        .{},
    );
}

fn parseBenchRun(output: []const u8, label: []const u8) !BenchRun {
    var parsed = BenchRun{
        .load = -1,
        .filter = -1,
        .sort = -1,
        .write = -1,
        .total = -1,
    };

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "Loaded ")) {
            parsed.load = try parseTrailingMs(line);
        } else if (std.mem.startsWith(u8, line, "Filtered")) {
            parsed.filter = try parseTrailingMs(line);
        } else if (std.mem.startsWith(u8, line, "Sorted ")) {
            parsed.sort = try parseTrailingMs(line);
        } else if (std.mem.startsWith(u8, line, "Top-10 ")) {
            parsed.write = try parseTrailingMs(line);
        } else if (std.mem.startsWith(u8, line, "Total: ")) {
            parsed.total = try parseTrailingMs(line);
        }
    }

    if (parsed.load >= 0 and parsed.filter >= 0 and parsed.sort >= 0 and parsed.write >= 0 and parsed.total >= 0) {
        return parsed;
    }

    std.debug.print("{s} benchmark output was missing one or more stage timings:\n{s}\n", .{ label, output });
    return error.InvalidData;
}

fn parseTrailingMs(line: []const u8) !i64 {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    var last_ms: ?[]const u8 = null;
    while (it.next()) |token| {
        if (std.mem.endsWith(u8, token, "ms")) {
            last_ms = token;
        }
    }
    const token = last_ms orelse return error.InvalidData;
    return std.fmt.parseInt(i64, token[0 .. token.len - 2], 10);
}

fn printBenchRunLine(run_idx: usize, bench_run: BenchRun) void {
    std.debug.print(
        "  run {d}: load={d}ms filter={d}ms sort={d}ms write={d}ms total={d}ms\n",
        .{ run_idx, bench_run.load, bench_run.filter, bench_run.sort, bench_run.write, bench_run.total },
    );
}

fn printBenchStats(gpa: std.mem.Allocator, name: []const u8, runs: []const BenchRun, stage: BenchStage) !void {
    const values = try collectBenchStageValues(gpa, runs, stage);
    defer gpa.free(values);
    std.debug.print("{s} min={d}ms median={d}ms\n", .{ name, minI64(values), medianI64(values) });
}

fn collectBenchStageValues(gpa: std.mem.Allocator, runs: []const BenchRun, stage: BenchStage) ![]i64 {
    const values = try gpa.alloc(i64, runs.len);
    for (runs, 0..) |bench_run, idx| {
        values[idx] = benchStageValue(bench_run, stage);
    }
    return values;
}

fn benchStageValue(bench_run: BenchRun, stage: BenchStage) i64 {
    return switch (stage) {
        .load => bench_run.load,
        .filter => bench_run.filter,
        .sort => bench_run.sort,
        .write => bench_run.write,
        .total => bench_run.total,
    };
}

fn minI64(values: []const i64) i64 {
    var min_value = values[0];
    for (values[1..]) |value| {
        if (value < min_value) min_value = value;
    }
    return min_value;
}

fn medianI64(values: []i64) i64 {
    std.sort.heap(i64, values, {}, lessThanI64);
    if (values.len % 2 == 1) return values[values.len / 2];
    return @divTrunc(values[(values.len / 2) - 1] + values[values.len / 2], 2);
}

fn lessThanI64(_: void, lhs: i64, rhs: i64) bool {
    return lhs < rhs;
}

fn appendBenchHistory(
    init: std.process.Init,
    history_path: []const u8,
    label: ?[]const u8,
    data_bytes: usize,
    digest: [32]u8,
    runs: usize,
    nurl_runs: []const BenchRun,
    polars_runs: []const BenchRun,
) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const history_dir = std.fs.path.dirname(history_path) orelse return error.BadPathName;
    const root_abs = try absolutePath(arena, ".");

    const date = (try captureTrimmedCommandOutput(arena, gpa, io, &.{ "date", "-u", "+%Y-%m-%d %H:%M:%SZ" }, null)) orelse "unknown-date";
    const sha = (try captureTrimmedCommandOutput(arena, gpa, io, &.{ "git", "-C", root_abs, "rev-parse", "--short", "HEAD" }, null)) orelse "no-git";
    const dirty = try isGitDirty(gpa, io, root_abs);
    const kernel = (try captureTrimmedCommandOutput(arena, gpa, io, &.{ "uname", "-srm" }, null)) orelse @tagName(builtin.os.tag);
    const cpu = try detectCpuDescription(arena, gpa, io);
    const digest_hex = std.fmt.bytesToHex(digest, .lower);

    var block: std.Io.Writer.Allocating = .init(gpa);
    defer block.deinit();

    try block.writer.print("\n## {s} -- {s}{s}", .{ date, sha, if (dirty) "+dirty" else "" });
    if (label) |text| {
        try block.writer.print(" -- {s}", .{text});
    }
    try block.writer.print(
        "\n- CPU: {s}\n- Kernel: {s}\n- Fixture: test_data.csv ({d} B, sha256={s}...)\n- Runs: {d} per implementation\n\n",
        .{ cpu, kernel, data_bytes, digest_hex[0..16], runs },
    );
    try block.writer.writeAll("| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars med |\n");
    try block.writer.writeAll("|--------|---------:|---------:|-----------:|-----------:|----------------:|\n");

    inline for ([_]BenchStage{ .load, .filter, .sort, .write, .total }) |stage| {
        const stage_name = switch (stage) {
            .load => "load",
            .filter => "filter",
            .sort => "sort",
            .write => "write",
            .total => "total",
        };
        const nurl_values = try collectBenchStageValues(gpa, nurl_runs, stage);
        defer gpa.free(nurl_values);
        const polars_values = try collectBenchStageValues(gpa, polars_runs, stage);
        defer gpa.free(polars_values);
        const nurl_min = minI64(nurl_values);
        const nurl_med = medianI64(nurl_values);
        const polars_min = minI64(polars_values);
        const polars_med = medianI64(polars_values);

        if (polars_med > 0) {
            const ratio_tenths = @divTrunc((nurl_med * 10) + @divTrunc(polars_med, 2), polars_med);
            try block.writer.print(
                "| {s:<6} | {d:>8} | {d:>8} | {d:>10} | {d:>10} | {d}.{d}x |\n",
                .{ stage_name, nurl_min, nurl_med, polars_min, polars_med, @divTrunc(ratio_tenths, 10), @mod(ratio_tenths, 10) },
            );
        } else {
            try block.writer.print(
                "| {s:<6} | {d:>8} | {d:>8} | {d:>10} | {d:>10} | n/a |\n",
                .{ stage_name, nurl_min, nurl_med, polars_min, polars_med },
            );
        }
    }

    const prior = if (pathExists(io, history_path))
        try std.Io.Dir.cwd().readFileAlloc(io, history_path, gpa, .unlimited)
    else
        try gpa.dupe(u8, "");
    defer gpa.free(prior);

    try ensureDirPath(io, history_dir);
    var merged: std.ArrayList(u8) = .empty;
    defer merged.deinit(gpa);
    try merged.appendSlice(gpa, prior);
    try merged.appendSlice(gpa, block.written());
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = history_path,
        .data = merged.items,
    });
}

fn captureTrimmedCommandOutput(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    cwd: ?[]const u8,
) !?[]const u8 {
    const child_cwd: std.process.Child.Cwd = if (cwd) |path| .{ .path = path } else .inherit;
    const result = std.process.run(gpa, io, .{
        .argv = argv,
        .cwd = child_cwd,
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) return null;
        },
        else => return null,
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    const dup = try arena.dupe(u8, trimmed);
    return dup;
}

fn isGitDirty(gpa: std.mem.Allocator, io: std.Io, root_abs: []const u8) !bool {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "git", "-C", root_abs, "diff", "--quiet" },
    }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    return switch (result.term) {
        .exited => |code| code != 0,
        else => false,
    };
}

fn detectCpuDescription(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
) ![]const u8 {
    if (builtin.os.tag == .macos) {
        if (try captureTrimmedCommandOutput(arena, gpa, io, &.{ "sysctl", "-n", "machdep.cpu.brand_string" }, null)) |cpu| {
            return cpu;
        }
    }
    if (builtin.os.tag == .linux) {
        const cpuinfo = std.Io.Dir.cwd().readFileAlloc(io, "/proc/cpuinfo", gpa, .unlimited) catch null;
        if (cpuinfo) |bytes| {
            defer gpa.free(bytes);
            var lines = std.mem.splitScalar(u8, bytes, '\n');
            while (lines.next()) |line| {
                if (std.mem.startsWith(u8, line, "model name")) {
                    if (std.mem.indexOf(u8, line, ":")) |idx| {
                        return try arena.dupe(u8, std.mem.trim(u8, line[idx + 1 ..], " \t\r"));
                    }
                }
            }
        }
    }
    return @tagName(builtin.cpu.arch);
}

fn lessThanString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn collectFmtCandidateFiles(
    gpa: std.mem.Allocator,
    io: std.Io,
    root_abs: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    try appendNuFilesFromDir(gpa, io, root_abs, "stdlib", out);
    try appendNuFilesFromDir(gpa, io, root_abs, "examples", out);
    try appendNuFilesFromDir(gpa, io, root_abs, "compiler/tests", out);
    try appendNuFilesFromDir(gpa, io, root_abs, "tools/nurlfmt", out);
    try out.append(gpa, try gpa.dupe(u8, "compiler/nurlc.nu"));
    try out.append(gpa, try gpa.dupe(u8, "compiler/nurlc_lastgood.nu"));
}

fn appendNuFilesFromDir(
    gpa: std.mem.Allocator,
    io: std.Io,
    root_abs: []const u8,
    rel_dir: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var root_dir = try std.Io.Dir.openDirAbsolute(io, root_abs, .{});
    defer root_dir.close(io);
    var sub_dir = try root_dir.openDir(io, rel_dir, .{ .iterate = true });
    defer sub_dir.close(io);
    var walker = try sub_dir.walk(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".nu")) continue;
        try out.append(gpa, try std.fs.path.join(gpa, &.{ rel_dir, entry.path }));
    }
}

fn isFmtIrSkipPath(path: []const u8) bool {
    return pathEqNormalized(path, "tools/nurlfmt/tokenize.nu") or
        pathEqNormalized(path, "tools/nurlfmt/pretty.nu");
}

fn pathEqNormalized(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| {
        const na: u8 = if (a == '\\') '/' else a;
        const nb: u8 = if (b == '\\') '/' else b;
        if (na != nb) return false;
    }
    return true;
}

fn firstMismatchSummary(
    gpa: std.mem.Allocator,
    lhs: []const u8,
    rhs: []const u8,
    lhs_label: []const u8,
    rhs_label: []const u8,
) ![]u8 {
    var lhs_it = std.mem.splitScalar(u8, lhs, '\n');
    var rhs_it = std.mem.splitScalar(u8, rhs, '\n');
    var line_no: usize = 1;

    while (true) {
        const lhs_line_opt = lhs_it.next();
        const rhs_line_opt = rhs_it.next();
        if (lhs_line_opt == null and rhs_line_opt == null) break;

        const lhs_line = std.mem.trimEnd(u8, lhs_line_opt orelse "<EOF>", "\r");
        const rhs_line = std.mem.trimEnd(u8, rhs_line_opt orelse "<EOF>", "\r");
        if (!std.mem.eql(u8, lhs_line, rhs_line)) {
            return std.fmt.allocPrint(
                gpa,
                "    first differing line {d}\n    {s}: {s}\n    {s}: {s}\n",
                .{ line_no, lhs_label, lhs_line, rhs_label, rhs_line },
            );
        }
        line_no += 1;
    }

    return gpa.dupe(u8, "    buffers differ, but no line-oriented mismatch was found\n");
}

fn extractPinnedMcpVersionFromSource(source: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, source, "@ mcp_protocol_version") orelse return null;
    var lines = std.mem.splitScalar(u8, source[start..], '\n');
    _ = lines.next() orelse return null;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '}') break;
        if (trimmed[0] == '^') {
            return findFirstIsoDate(trimmed);
        }
    }
    return null;
}

fn extractCurrentMcpVersionFromHtml(html: []const u8) ?[]const u8 {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, html, start, "current")) |idx| {
        const end = @min(html.len, idx + 128);
        if (findFirstIsoDate(html[idx..end])) |date| return date;
        start = idx + "current".len;
    }
    start = 0;
    while (std.mem.indexOfPos(u8, html, start, "Current")) |idx| {
        const end = @min(html.len, idx + 128);
        if (findFirstIsoDate(html[idx..end])) |date| return date;
        start = idx + "Current".len;
    }
    return findFirstIsoDate(html);
}

fn findFirstIsoDate(input: []const u8) ?[]const u8 {
    if (input.len < 10) return null;
    var i: usize = 0;
    while (i + 10 <= input.len) : (i += 1) {
        if (isIsoDateAt(input, i)) {
            return input[i .. i + 10];
        }
    }
    return null;
}

fn isIsoDateAt(input: []const u8, start: usize) bool {
    if (start + 10 > input.len) return false;
    const s = input[start .. start + 10];
    return std.ascii.isDigit(s[0]) and
        std.ascii.isDigit(s[1]) and
        std.ascii.isDigit(s[2]) and
        std.ascii.isDigit(s[3]) and
        s[4] == '-' and
        std.ascii.isDigit(s[5]) and
        std.ascii.isDigit(s[6]) and
        s[7] == '-' and
        std.ascii.isDigit(s[8]) and
        std.ascii.isDigit(s[9]);
}

fn fetchUrlBody(init: std.process.Init, url: []const u8) ![]u8 {
    const gpa = init.gpa;
    const io = init.io;

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    var response_body: std.Io.Writer.Allocating = .init(gpa);
    defer response_body.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &response_body.writer,
    }) catch |err| {
        std.debug.print("ERROR: could not fetch {s}\n", .{url});
        return err;
    };
    if (result.status != .ok) {
        std.debug.print("ERROR: fetch {s} returned HTTP {d}\n", .{ url, @intFromEnum(result.status) });
        return error.UnexpectedHttpStatus;
    }

    return gpa.dupe(u8, response_body.written());
}

fn parseUserCompileArgs(init: std.process.Init, args: []const []const u8, flavor: CompileFlavor) !UserCompileConfig {
    const arena = init.arena.allocator();
    var i: usize = 0;
    var root: []const u8 = ".";
    var emit_ir = false;
    var emit_asm = false;
    var debug_info = false;
    var cli_opt: ?[]const u8 = null;

    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--emit-ir") or std.mem.eql(u8, arg, "--emit=ir")) {
            emit_ir = true;
        } else if (std.mem.eql(u8, arg, "--emit-asm") or std.mem.eql(u8, arg, "--emit=asm")) {
            emit_asm = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUserCompileUsage(flavor);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--debug")) {
            debug_info = true;
        } else if (std.mem.eql(u8, arg, "-O0") or std.mem.eql(u8, arg, "-O1") or std.mem.eql(u8, arg, "-O2") or std.mem.eql(u8, arg, "-O3")) {
            cli_opt = arg;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("nurl-build: unknown {s} arg: {s}\n", .{ @tagName(flavor), arg });
            return error.InvalidArgs;
        } else break;
        i += 1;
    }

    if (args.len - i == 0 or args.len - i > 2) {
        printUserCompileUsage(flavor);
        return error.InvalidArgs;
    }

    const srcfile = args[i];
    const outbase = if (args.len - i == 2)
        args[i + 1]
    else if (std.mem.endsWith(u8, srcfile, ".nu"))
        srcfile[0 .. srcfile.len - ".nu".len]
    else
        srcfile;

    return .{
        .root = try absolutePath(arena, root),
        .srcfile = srcfile,
        .outbase = outbase,
        .emit_ir = emit_ir,
        .emit_asm = emit_asm,
        .debug_info = debug_info,
        .opt = cli_opt orelse init.environ_map.get("NURL_OPT") orelse "-O2",
    };
}

fn printUserCompileUsage(flavor: CompileFlavor) void {
    switch (flavor) {
        .native => std.debug.print("usage: nurl-build nurl [--root <path>] [--emit-ir|--emit=ir] [--emit-asm|--emit=asm] [-O0|-O1|-O2|-O3] [-g|--debug] <file.nu> [output_name]\n", .{}),
        .wasm => std.debug.print("usage: nurl-build wasmnurl [--root <path>] [--emit-ir|--emit=ir] [--emit-asm|--emit=asm] [-O0|-O1|-O2|-O3] [-g|--debug] <file.nu> [output_name]\n", .{}),
    }
}

fn runUserCompile(init: std.process.Init, cfg: UserCompileConfig, flavor: CompileFlavor) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    try ensureExists(io, cfg.srcfile, "source file");

    const llfile = try std.fmt.allocPrint(arena, "{s}.ll", .{cfg.outbase});
    const sfile = try std.fmt.allocPrint(arena, "{s}.s", .{cfg.outbase});

    if (cfg.emit_ir) {
        std.debug.print("[1/1] {s} -> {s}\n", .{ cfg.srcfile, llfile });
    } else if (flavor == .wasm) {
        std.debug.print("[1/2] {s} -> {s}  (via nurlc.wasm)\n", .{ cfg.srcfile, llfile });
    } else {
        std.debug.print("[1/2] {s} -> {s}\n", .{ cfg.srcfile, llfile });
    }

    const ir_bytes = switch (flavor) {
        .native => try compileToLlViaNurlc(init, cfg),
        .wasm => try compileToLlViaWasm(init, cfg),
    };
    defer gpa.free(ir_bytes);

    try ensureParentDir(io, llfile);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = llfile,
        .data = ir_bytes,
    });

    if (cfg.emit_ir) {
        std.debug.print("\nDone: {s}\n", .{llfile});
        return;
    }

    const driver_override = init.environ_map.get("NURL_CC") orelse init.environ_map.get("CLANG") orelse "clang";

    if (cfg.emit_asm) {
        try emitAssembly(init, driver_override, cfg, llfile, sfile);
        std.debug.print("\nDone: {s}\n", .{sfile});
        return;
    }

    var extra_objs: std.ArrayList([]const u8) = .empty;
    defer extra_objs.deinit(gpa);
    var extra_libs: std.ArrayList([]const u8) = .empty;
    defer extra_libs.deinit(gpa);
    try collectCanvasLinkExtras(gpa, io, cfg.root, ir_bytes, &extra_objs, &extra_libs);

    var runtime_override: ?[]const u8 = null;
    if (cfg.debug_info and builtin.os.tag != .windows) {
        runtime_override = try ensureDebugRuntime(init, cfg.root, driver_override);
    }

    std.debug.print("[2/2] {s} -> {s}\n", .{ llfile, cfg.outbase });

    var link_args: std.ArrayList([]const u8) = .empty;
    defer link_args.deinit(gpa);
    try link_args.append(gpa, "--opt");
    try link_args.append(gpa, cfg.opt);
    if (runtime_override) |runtime| {
        try link_args.appendSlice(gpa, &.{ "--no-lto", "--runtime", runtime });
    }
    if (cfg.debug_info) {
        try link_args.appendSlice(gpa, &.{ "--flag", "-g" });
        if (builtin.os.tag != .windows) {
            try link_args.appendSlice(gpa, &.{ "--flag", "-rdynamic" });
        }
    }
    for (extra_objs.items) |obj| {
        try link_args.appendSlice(gpa, &.{ "--extra-obj", obj });
    }
    for (extra_libs.items) |lib| {
        try link_args.appendSlice(gpa, &.{ "--extra-lib", lib });
    }
    try link_args.appendSlice(gpa, &.{ "--driver", driver_override, cfg.root, llfile, cfg.outbase });
    try runLink(init, link_args.items);

    std.debug.print("\nDone: {s}\n", .{cfg.outbase});
}

fn compileToLlViaNurlc(init: std.process.Init, cfg: UserCompileConfig) ![]u8 {
    const gpa = init.gpa;
    const io = init.io;

    const nurlc_path = try resolveNurlc(init, cfg.root);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, nurlc_path);
    if (cfg.debug_info) try argv.append(gpa, "--g");
    try argv.append(gpa, cfg.srcfile);

    const result = try std.process.run(gpa, io, .{ .argv = argv.items });
    errdefer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }
    try ensureSuccessWithStderr(result, "NURL compilation failed");
    gpa.free(result.stderr);
    return result.stdout;
}

fn compileToLlViaWasm(init: std.process.Init, cfg: UserCompileConfig) ![]u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const wasmtime = try resolveWasmtime(init);
    const nurlc_wasm = try resolveNurlcWasm(init, cfg.root);
    const src_abs = try absolutePath(arena, cfg.srcfile);
    const src_dir = std.fs.path.dirname(src_abs) orelse ".";

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{ wasmtime, "run", "--dir=." });
    if (!std.mem.eql(u8, src_dir, ".")) {
        const cwd_abs = try std.fs.path.resolve(arena, &.{"."});
        if (!std.mem.eql(u8, src_dir, cwd_abs)) {
            try argv.append(gpa, try std.fmt.allocPrint(arena, "--dir={s}", .{src_dir}));
        }
    }
    try argv.appendSlice(gpa, &.{ nurlc_wasm, cfg.srcfile });

    const result = try std.process.run(gpa, io, .{ .argv = argv.items });
    errdefer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }
    try ensureSuccessWithStderr(result, "wasmtime nurlc.wasm failed");
    gpa.free(result.stderr);
    return result.stdout;
}

fn emitAssembly(
    init: std.process.Init,
    driver_override: []const u8,
    cfg: UserCompileConfig,
    llfile: []const u8,
    sfile: []const u8,
) !void {
    const gpa = init.gpa;
    const io = init.io;
    var driver_parts = try splitDriver(gpa, driver_override, init);
    defer driver_parts.deinit(gpa);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, driver_parts.items);
    try argv.appendSlice(gpa, &.{cfg.opt});
    if (cfg.debug_info) {
        try argv.append(gpa, "-g");
    }
    try argv.appendSlice(gpa, &.{ "-S", llfile, "-o", sfile });

    try ensureParentDir(io, sfile);

    const result = try std.process.run(gpa, io, .{ .argv = argv.items });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try ensureSuccessWithStderr(result, "clang -S failed");
}

fn resolveNurlc(init: std.process.Init, root: []const u8) ![]const u8 {
    return resolveBuildOrRootBinary(init, root, "nurlc");
}

fn resolveNurlcWasm(init: std.process.Init, root: []const u8) ![]const u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    if (init.environ_map.get("NURLC_WASM")) |path| {
        if (pathExists(io, path)) return path;
    }

    const root_wasm = try std.fs.path.join(arena, &.{ root, "nurlc.wasm" });
    if (pathExists(io, root_wasm)) return root_wasm;

    const build_wasm = try std.fs.path.join(arena, &.{ root, "build", "nurlc.wasm" });
    if (pathExists(io, build_wasm)) return build_wasm;

    std.debug.print("ERROR: nurlc.wasm not found under {s}\n", .{root});
    std.debug.print("       Run: zig build buildwasm\n", .{});
    return error.FileNotFound;
}

fn resolveWasmtime(init: std.process.Init) ![]const u8 {
    const arena = init.arena.allocator();

    if (init.environ_map.get("WASMTIME")) |path| {
        return path;
    }
    if (init.environ_map.get("HOME")) |home| {
        const fallback = try std.fs.path.join(arena, &.{ home, ".wasmtime", "bin", "wasmtime" });
        if (pathExists(init.io, fallback)) return fallback;
    }
    return "wasmtime";
}

fn collectCanvasLinkExtras(
    gpa: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    ir_bytes: []const u8,
    extra_objs: *std.ArrayList([]const u8),
    extra_libs: *std.ArrayList([]const u8),
) !void {
    if (!containsAny(ir_bytes, &.{
        "@canvas_open",
        "@canvas_present",
        "@canvas_sleep",
        "@canvas_should_close",
        "@canvas_close",
        "@canvas_mouse_x",
        "@canvas_mouse_y",
        "@canvas_mouse_btn",
    })) return;

    const canvas_o = try std.fs.path.join(std.heap.page_allocator, &.{ root, "stdlib", "canvas.o" });
    defer std.heap.page_allocator.free(canvas_o);
    if (!pathExists(io, canvas_o)) {
        std.debug.print("ERROR: program uses canvas FFI but {s} is missing.\n", .{canvas_o});
        std.debug.print("       Run zig build bootstrap first.\n", .{});
        return error.FileNotFound;
    }
    try extra_objs.append(gpa, try gpa.dupe(u8, canvas_o));

    const canvas_marker = try std.fs.path.join(std.heap.page_allocator, &.{ root, "stdlib", "canvas.sdl2" });
    defer std.heap.page_allocator.free(canvas_marker);
    if (pathExists(io, canvas_marker)) {
        try extra_libs.append(gpa, "-lSDL2");
    } else {
        std.debug.print("[info] canvas.o is a stub build (no SDL2 at build time).\n", .{});
    }
}

fn ensureDebugRuntime(init: std.process.Init, root: []const u8, driver_override: []const u8) ![]const u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const runtime_c = try std.fs.path.join(arena, &.{ root, "stdlib", "runtime.c" });
    const debug_runtime = try std.fs.path.join(arena, &.{ root, "stdlib", "runtime_debug.o" });

    const needs_rebuild = blk: {
        if (!pathExists(io, debug_runtime)) break :blk true;
        const runtime_stat = try std.Io.Dir.cwd().statFile(io, runtime_c, .{});
        const debug_stat = try std.Io.Dir.cwd().statFile(io, debug_runtime, .{});
        break :blk runtime_stat.mtime.nanoseconds > debug_stat.mtime.nanoseconds;
    };
    if (!needs_rebuild) return debug_runtime;

    var driver_parts = try splitDriver(gpa, driver_override, init);
    defer driver_parts.deinit(gpa);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, driver_parts.items);
    try argv.appendSlice(gpa, &.{ "-O0", "-g" });
    try appendRuntimeCompileFlags(gpa, arena, io, &argv, root);
    try argv.appendSlice(gpa, &.{ "-c", runtime_c, "-o", debug_runtime });

    const result = try std.process.run(gpa, io, .{ .argv = argv.items });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try ensureSuccessWithStderr(result, "runtime debug rebuild failed");
    return debug_runtime;
}

fn appendRuntimeCompileFlags(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    argv: *std.ArrayList([]const u8),
    root: []const u8,
) !void {
    const compile_specs = [_]struct {
        marker: []const u8,
        define_flag: []const u8,
        pkg: []const u8,
    }{
        .{ .marker = "runtime.curl", .define_flag = "-DNURL_HAVE_LIBCURL", .pkg = "libcurl" },
        .{ .marker = "runtime.openssl", .define_flag = "-DNURL_HAVE_OPENSSL", .pkg = "openssl" },
        .{ .marker = "runtime.sqlite3", .define_flag = "-DNURL_HAVE_SQLITE3", .pkg = "sqlite3" },
        .{ .marker = "runtime.z", .define_flag = "-DNURL_HAVE_ZLIB", .pkg = "zlib" },
    };

    const pkg_config = "pkg-config";
    for (compile_specs) |spec| {
        const marker_path = try std.fs.path.join(arena, &.{ root, "stdlib", spec.marker });
        if (!pathExists(io, marker_path)) continue;
        try argv.append(gpa, spec.define_flag);

        const result = std.process.run(gpa, io, .{
            .argv = &.{ pkg_config, "--cflags", spec.pkg },
        }) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        switch (result.term) {
            .exited => |code| {
                if (code != 0) continue;
                var it = std.mem.tokenizeAny(u8, result.stdout, " \t\r\n");
                while (it.next()) |token| {
                    try argv.append(gpa, try arena.dupe(u8, token));
                }
            },
            else => {},
        }
    }
}

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}

fn ensureSuccessWithStderr(result: std.process.RunResult, label: []const u8) !void {
    switch (result.term) {
        .exited => |code| {
            if (code == 0) return;
            if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
            if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
            std.debug.print("ERROR: {s}\n", .{label});
            return error.ChildProcessFailed;
        },
        else => {
            if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
            if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
            std.debug.print("ERROR: {s}\n", .{label});
            return error.ChildProcessFailed;
        },
    }
}

fn runLink(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var i: usize = 0;
    var opt: []const u8 = "-O2";
    var driver_override: ?[]const u8 = null;
    var target_override: ?[]const u8 = null;
    var runtime_override: ?[]const u8 = null;
    var force_no_lto = false;
    var marker_libs_enabled = true;

    var extra_flags: std.ArrayList([]const u8) = .empty;
    defer extra_flags.deinit(gpa);
    var extra_objs: std.ArrayList([]const u8) = .empty;
    defer extra_objs.deinit(gpa);
    var extra_libs: std.ArrayList([]const u8) = .empty;
    defer extra_libs.deinit(gpa);

    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--opt")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            opt = args[i];
        } else if (std.mem.eql(u8, arg, "--driver")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            driver_override = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            target_override = args[i];
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            runtime_override = args[i];
        } else if (std.mem.eql(u8, arg, "--flag")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            try extra_flags.append(gpa, args[i]);
        } else if (std.mem.eql(u8, arg, "--extra-obj")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            try extra_objs.append(gpa, args[i]);
        } else if (std.mem.eql(u8, arg, "--extra-lib")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            try extra_libs.append(gpa, args[i]);
        } else if (std.mem.eql(u8, arg, "--no-lto")) {
            force_no_lto = true;
        } else if (std.mem.eql(u8, arg, "--no-marker-libs")) {
            marker_libs_enabled = false;
        } else {
            std.debug.print("nurl-build: unknown arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len - i != 3) {
        std.debug.print(
            "usage: nurl-build link [--opt <flag>] [--driver <cmd>] [--target <triple>] [--runtime <path>] [--no-lto] [--no-marker-libs] [--flag <arg>] [--extra-obj <path>] [--extra-lib <arg>] <repo-root> <llvm-ir> <output-bin>\n",
            .{},
        );
        return error.InvalidArgs;
    }

    const root = args[i];
    const ll_path = args[i + 1];
    const output_path = args[i + 2];

    try ensureExists(io, ll_path, "LLVM IR");

    const runtime_path = runtime_override orelse try std.fs.path.join(arena, &.{ root, "stdlib", "runtime.o" });
    try ensureExists(io, runtime_path, "runtime.o");

    const nolto_marker_path = try std.fs.path.join(arena, &.{ root, "stdlib", "runtime.nolto" });
    const use_lto = !force_no_lto and builtin.os.tag != .windows and !pathExists(io, nolto_marker_path);

    var driver_parts = try splitDriver(gpa, driver_override, init);
    defer driver_parts.deinit(gpa);

    var child_argv: std.ArrayList([]const u8) = .empty;
    defer child_argv.deinit(gpa);

    try child_argv.appendSlice(gpa, driver_parts.items);
    if (target_override) |target| {
        try child_argv.append(gpa, try std.fmt.allocPrint(arena, "--target={s}", .{target}));
    }
    try child_argv.append(gpa, opt);
    if (use_lto) {
        try child_argv.append(gpa, "-flto");
    }
    try child_argv.appendSlice(gpa, extra_flags.items);
    try child_argv.append(gpa, ll_path);
    try child_argv.append(gpa, runtime_path);
    for (extra_objs.items) |extra_obj| {
        try ensureExists(io, extra_obj, "extra object");
        try child_argv.append(gpa, extra_obj);
    }
    try appendDefaultSystemLibs(gpa, &child_argv, inferSystemLibMode(target_override));

    const pkg_config_exe = init.environ_map.get("PKG_CONFIG") orelse "pkg-config";
    if (marker_libs_enabled) {
        for (library_specs) |lib| {
            const marker_path = try std.fs.path.join(arena, &.{ root, "stdlib", lib.marker });
            if (!pathExists(io, marker_path)) continue;
            try appendPkgConfigOrFallback(gpa, arena, io, &child_argv, pkg_config_exe, lib);
        }
    }
    try child_argv.appendSlice(gpa, extra_libs.items);

    try ensureParentDir(io, output_path);
    try child_argv.append(gpa, "-o");
    try child_argv.append(gpa, output_path);

    var child = std.process.spawn(io, .{
        .argv = child_argv.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("nurl-build: C driver not found: {s}\n", .{driver_parts.items[0]});
        }
        return err;
    };
    errdefer child.kill(io);

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) std.process.exit(code);
        },
        .signal => |sig| {
            std.debug.print("nurl-build: linker terminated by signal {d}\n", .{@intFromEnum(sig)});
            std.process.exit(128 + @as(u8, @intCast(@intFromEnum(sig))));
        },
        .stopped => |sig| {
            std.debug.print("nurl-build: linker stopped by signal {d}\n", .{@intFromEnum(sig)});
            std.process.exit(128 + @as(u8, @intCast(@intFromEnum(sig))));
        },
        .unknown => |status| {
            std.debug.print("nurl-build: linker exited with unknown status {d}\n", .{status});
            std.process.exit(1);
        },
    }
}

fn runMkdir(io: std.Io, args: []const []const u8) !void {
    if (args.len != 1) {
        std.debug.print("usage: nurl-build mkdir <path>\n", .{});
        return error.InvalidArgs;
    }
    try ensureDirPath(io, args[0]);
}

fn runCopy(gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var executable = false;
    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--exec")) {
            executable = true;
        } else {
            std.debug.print("nurl-build: unknown copy arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len - i != 2) {
        std.debug.print("usage: nurl-build copy [--exec] <src> <dest>\n", .{});
        return error.InvalidArgs;
    }

    const src_abs = try absolutePath(arena, args[i]);
    const dest_abs = try absolutePath(arena, args[i + 1]);
    try ensureParentDir(io, dest_abs);

    var src_file = try std.Io.Dir.cwd().openFile(io, src_abs, .{});
    defer src_file.close(io);
    var src_reader = src_file.reader(io, &.{});
    const bytes = try src_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(bytes);

    var dest_file = try std.Io.Dir.cwd().createFile(io, dest_abs, .{
        .truncate = true,
        .permissions = if (executable) .executable_file else .default_file,
    });
    defer dest_file.close(io);
    try dest_file.writeStreamingAll(io, bytes);
}

fn runSymlink(
    arena: std.mem.Allocator,
    init: std.process.Init,
    io: std.Io,
    args: []const []const u8,
) !void {
    if (args.len != 2) {
        std.debug.print("usage: nurl-build symlink <src> <dest>\n", .{});
        return error.InvalidArgs;
    }

    const src = args[0];
    const dest = args[1];
    const dest_parent = std.fs.path.dirname(dest) orelse ".";
    const src_abs = try absolutePath(arena, src);
    const dest_parent_abs = try absolutePath(arena, dest_parent);
    const rel_target = try std.fs.path.relative(arena, ".", init.environ_map, dest_parent_abs, src_abs);

    try ensureParentDir(io, dest);

    std.Io.Dir.cwd().deleteFile(io, dest) catch |err| switch (err) {
        error.FileNotFound => {},
        error.IsDir => {
            std.debug.print("nurl-build: refusing to replace directory symlink target at {s}\n", .{dest});
            return err;
        },
        else => |e| return e,
    };
    try std.Io.Dir.cwd().symLink(io, rel_target, dest, .{});
}

fn runMarker(io: std.Io, args: []const []const u8) !void {
    if (args.len != 2) {
        std.debug.print("usage: nurl-build marker <--on|--off> <path>\n", .{});
        return error.InvalidArgs;
    }

    const enable = if (std.mem.eql(u8, args[0], "--on"))
        true
    else if (std.mem.eql(u8, args[0], "--off"))
        false
    else {
        std.debug.print("nurl-build: unknown marker mode: {s}\n", .{args[0]});
        return error.InvalidArgs;
    };

    if (enable) {
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = args[1],
            .data = "1\n",
        });
    } else {
        std.Io.Dir.cwd().deleteFile(io, args[1]) catch |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return e,
        };
    }
}

fn runCompare(init: std.process.Init, io: std.Io, args: []const []const u8) !void {
    const gpa = init.gpa;

    if (args.len != 2) {
        std.debug.print("usage: nurl-build compare <lhs> <rhs>\n", .{});
        return error.InvalidArgs;
    }

    const lhs = try std.Io.Dir.cwd().readFileAlloc(io, args[0], gpa, .unlimited);
    defer gpa.free(lhs);
    const rhs = try std.Io.Dir.cwd().readFileAlloc(io, args[1], gpa, .unlimited);
    defer gpa.free(rhs);

    if (!std.mem.eql(u8, lhs, rhs)) {
        std.debug.print("Fixed point NOT reached - nurlc_self and nurlc_self2 differ.\n", .{});
        return error.FilesDiffer;
    }
}

fn runBuildWasm(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var api_url: ?[]const u8 = null;
    var src_path: ?[]const u8 = null;
    var out_path: ?[]const u8 = null;
    var positional_out: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--api-url")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            api_url = args[i];
        } else if (std.mem.eql(u8, arg, "--src")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            src_path = args[i];
        } else if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            out_path = args[i];
        } else {
            std.debug.print("nurl-build: unknown buildwasm arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len - i > 1) {
        std.debug.print("usage: nurl-build buildwasm [--api-url <url>] [--src <path>] [--out <path>] [output-path]\n", .{});
        return error.InvalidArgs;
    }
    if (args.len - i == 1) positional_out = args[i];

    const api_url_raw = api_url orelse init.environ_map.get("NURL_API_URL") orelse "http://localhost:8000";
    const normalized_api_url = trimTrailingSlashes(api_url_raw);
    const final_src_path = src_path orelse init.environ_map.get("NURL_SRC") orelse "compiler/nurlc.nu";
    const final_out_path = out_path orelse positional_out orelse "nurlc.wasm";

    try ensureExists(io, final_src_path, "source file");

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    const health_url = try std.fmt.allocPrint(arena, "{s}/health", .{normalized_api_url});
    const health_result = client.fetch(.{
        .location = .{ .url = health_url },
    }) catch {
        std.debug.print("ERROR: NURL API not reachable at {s}\n", .{normalized_api_url});
        std.debug.print("       Start it first: zig build startdev\n", .{});
        std.debug.print("       (or set NURL_API_URL to a running instance)\n", .{});
        return error.ConnectionRefused;
    };
    if (health_result.status != .ok) {
        std.debug.print("ERROR: NURL API health probe returned HTTP {d} at {s}\n", .{ @intFromEnum(health_result.status), health_url });
        return error.UnexpectedHttpStatus;
    }

    const src_bytes = try std.Io.Dir.cwd().readFileAlloc(io, final_src_path, gpa, .unlimited);
    defer gpa.free(src_bytes);

    const RequestPayload = struct {
        source: []const u8,
        filename: []const u8,
        return_format: []const u8,
    };

    var request_json: std.Io.Writer.Allocating = .init(gpa);
    defer request_json.deinit();
    try std.json.Stringify.value(RequestPayload{
        .source = src_bytes,
        .filename = std.fs.path.basename(final_src_path),
        .return_format = "binary",
    }, .{}, &request_json.writer);

    var response_body: std.Io.Writer.Allocating = .init(gpa);
    defer response_body.deinit();

    std.debug.print("[1/1] {s} -> {s}  (via {s}/build_wasm)\n", .{ final_src_path, final_out_path, normalized_api_url });

    const build_url = try std.fmt.allocPrint(arena, "{s}/build_wasm", .{normalized_api_url});
    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/wasm" },
    };
    const build_result = try client.fetch(.{
        .location = .{ .url = build_url },
        .method = .POST,
        .payload = request_json.written(),
        .extra_headers = &headers,
        .response_writer = &response_body.writer,
    });

    const response_bytes = response_body.written();
    if (build_result.status != .ok) {
        std.debug.print("ERROR: build failed (HTTP {d})\n", .{@intFromEnum(build_result.status)});
        emitJsonOrRaw(io, gpa, response_bytes);
        return error.UnexpectedHttpStatus;
    }
    if (response_bytes.len < 4 or !std.mem.eql(u8, response_bytes[0..4], "\x00asm")) {
        std.debug.print("ERROR: response is not a wasm module\n", .{});
        emitJsonOrRaw(io, gpa, response_bytes[0..@min(response_bytes.len, 512)]);
        return error.InvalidData;
    }

    try ensureParentDir(io, final_out_path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = final_out_path,
        .data = response_bytes,
    });

    std.debug.print("\nDone: {s}  ({d} bytes)\n", .{ final_out_path, response_bytes.len });
    std.debug.print("\nTry:\n  zig build wasmnurl -- examples/showcase.nu\n", .{});
}

fn runClean(init: std.process.Init, args: []const []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;

    if (args.len != 0) {
        std.debug.print("usage: nurl-build clean\n", .{});
        return error.InvalidArgs;
    }

    std.debug.print("Cleaning NURL build artifacts...\n", .{});

    deleteTreeIfExists(io, "build") catch |err| return err;

    var root_files: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &root_files);
    var pyc_files: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &pyc_files);
    var pycache_dirs: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &pycache_dirs);

    var root_dir = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer root_dir.close(io);
    var walker = try root_dir.walk(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory and std.mem.eql(u8, entry.basename, "__pycache__")) {
            try pycache_dirs.append(gpa, try gpa.dupe(u8, entry.path));
            continue;
        }

        if (entry.kind != .directory and std.mem.endsWith(u8, entry.basename, ".pyc")) {
            try pyc_files.append(gpa, try gpa.dupe(u8, entry.path));
        }

        if (entry.depth() == 1 and entry.kind != .directory and shouldRemoveLegacyRootArtifact(entry.basename)) {
            try root_files.append(gpa, try gpa.dupe(u8, entry.path));
        }
    }

    for (root_files.items) |path| {
        deleteFileIfExists(io, path) catch |err| return err;
    }
    for (pyc_files.items) |path| {
        deleteFileIfExists(io, path) catch |err| return err;
    }
    for (pycache_dirs.items) |path| {
        deleteTreeIfExists(io, path) catch |err| return err;
    }

    std.debug.print("Clean complete!\n", .{});
}

fn runStartDev(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();

    var docker_cmd: []const u8 = init.environ_map.get("DOCKER") orelse "docker";
    var image: []const u8 = "hindurable/nurl:latest";
    var dockerfile: []const u8 = "api/Dockerfile";
    var host_port: []const u8 = "8000";
    var container_port: []const u8 = "8000";
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--docker")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            docker_cmd = args[i];
        } else if (std.mem.eql(u8, arg, "--image")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            image = args[i];
        } else if (std.mem.eql(u8, arg, "--dockerfile")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            dockerfile = args[i];
        } else if (std.mem.eql(u8, arg, "--host-port")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            host_port = args[i];
        } else if (std.mem.eql(u8, arg, "--container-port")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            container_port = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else {
            std.debug.print("nurl-build: unknown startdev arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len != i) {
        std.debug.print(
            "usage: nurl-build startdev [--docker <cmd>] [--image <name>] [--dockerfile <path>] [--host-port <port>] [--container-port <port>] [--dry-run]\n",
            .{},
        );
        return error.InvalidArgs;
    }

    const port_mapping = try std.fmt.allocPrint(arena, "{s}:{s}", .{ host_port, container_port });

    const build_argv = [_][]const u8{ docker_cmd, "build", "-f", dockerfile, "-t", image, "." };
    const run_argv = [_][]const u8{ docker_cmd, "run", "--rm", "-p", port_mapping, image };

    if (dry_run) {
        printCommand("build", &build_argv);
        printCommand("run", &run_argv);
        return;
    }

    try runInherited(init, &build_argv);
    try runInherited(init, &run_argv);
}

fn runDockerPush(init: std.process.Init, args: []const []const u8) !void {
    var docker_cmd: []const u8 = init.environ_map.get("DOCKER") orelse "docker";
    var image: []const u8 = "hindurable/nurl:latest";
    var dockerfile: []const u8 = "api/Dockerfile";
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--docker")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            docker_cmd = args[i];
        } else if (std.mem.eql(u8, arg, "--image")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            image = args[i];
        } else if (std.mem.eql(u8, arg, "--dockerfile")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            dockerfile = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else {
            std.debug.print("nurl-build: unknown dockerpush arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len != i) {
        std.debug.print(
            "usage: nurl-build dockerpush [--docker <cmd>] [--image <name>] [--dockerfile <path>] [--dry-run]\n",
            .{},
        );
        return error.InvalidArgs;
    }

    const build_argv = [_][]const u8{ docker_cmd, "build", "-f", dockerfile, "-t", image, "." };
    const push_argv = [_][]const u8{ docker_cmd, "push", image };

    if (dry_run) {
        printCommand("build", &build_argv);
        printCommand("push", &push_argv);
        return;
    }

    try runInherited(init, &build_argv);
    try runInherited(init, &push_argv);
}

fn absolutePath(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(path)) return arena.dupe(u8, path);
    return std.fs.path.resolve(arena, &.{ ".", path });
}

fn resolvePathFromRoot(arena: std.mem.Allocator, root: []const u8, path: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(path)) return arena.dupe(u8, path);
    return std.fs.path.join(arena, &.{ root, path });
}

fn resolveBuildOrRootBinary(init: std.process.Init, root: []const u8, base_name: []const u8) ![]const u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const binary_name = if (builtin.os.tag == .windows)
        try std.fmt.allocPrint(arena, "{s}.exe", .{base_name})
    else
        base_name;

    const build_path = try std.fs.path.join(arena, &.{ root, "build", binary_name });
    if (pathExists(io, build_path)) return build_path;

    const root_path = try std.fs.path.join(arena, &.{ root, binary_name });
    if (pathExists(io, root_path)) return root_path;

    return binary_name;
}

fn ensureParentDir(io: std.Io, file_path: []const u8) !void {
    const parent = std.fs.path.dirname(file_path) orelse return;
    try ensureDirPath(io, parent);
}

fn ensureDirPath(io: std.Io, path: []const u8) !void {
    if (path.len == 0 or std.mem.eql(u8, path, ".")) return;
    if (pathExists(io, path)) return;

    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len != 0 and !std.mem.eql(u8, parent, path)) {
            try ensureDirPath(io, parent);
        }
    }

    if (std.fs.path.isAbsolute(path)) {
        std.Io.Dir.createDirAbsolute(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
    } else {
        std.Io.Dir.cwd().createDir(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
    }
}

fn trimTrailingSlashes(input: []const u8) []const u8 {
    var end = input.len;
    while (end > 0 and input[end - 1] == '/') : (end -= 1) {}
    return if (end == 0) input else input[0..end];
}

fn emitJsonOrRaw(io: std.Io, gpa: std.mem.Allocator, body: []const u8) void {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (trimmed.len == 0) return;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    defer stderr_writer.flush() catch {};

    if (std.json.parseFromSlice(std.json.Value, gpa, trimmed, .{})) |parsed| {
        defer parsed.deinit();
        std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &stderr_writer.interface) catch {
            stderr_writer.interface.writeAll(trimmed) catch {};
        };
    } else |_| {
        stderr_writer.interface.writeAll(trimmed) catch {};
    }
    stderr_writer.interface.writeByte('\n') catch {};
}

fn shouldRemoveLegacyRootArtifact(name: []const u8) bool {
    if (std.mem.endsWith(u8, name, ".ll")) return true;
    if (std.mem.endsWith(u8, name, ".tmp")) return true;
    if (std.mem.eql(u8, name, "nurlc")) return true;
    if (std.mem.eql(u8, name, "nurlc.exe")) return true;
    if (std.mem.startsWith(u8, name, "nurlc_py")) return true;
    if (std.mem.startsWith(u8, name, "nurlc_self")) return true;
    return false;
}

fn deleteFileIfExists(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };
}

fn deleteTreeIfExists(io: std.Io, path: []const u8) !void {
    if (!pathExists(io, path)) return;
    try std.Io.Dir.cwd().deleteTree(io, path);
}

fn freePathList(gpa: std.mem.Allocator, paths: *std.ArrayList([]const u8)) void {
    for (paths.items) |path| gpa.free(path);
    paths.deinit(gpa);
}

fn runResultSucceeded(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn printCommand(label: []const u8, argv: []const []const u8) void {
    std.debug.print("[{s}]", .{label});
    for (argv) |arg| {
        std.debug.print(" {s}", .{arg});
    }
    std.debug.print("\n", .{});
}

fn runInherited(init: std.process.Init, argv: []const []const u8) !void {
    var child = std.process.spawn(init.io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("nurl-build: command not found: {s}\n", .{argv[0]});
        }
        return err;
    };
    errdefer child.kill(init.io);

    const term = try child.wait(init.io);
    switch (term) {
        .exited => |code| {
            if (code != 0) std.process.exit(code);
        },
        .signal => |sig| {
            std.debug.print("nurl-build: child terminated by signal {d}\n", .{@intFromEnum(sig)});
            std.process.exit(128 + @as(u8, @intCast(@intFromEnum(sig))));
        },
        .stopped => |sig| {
            std.debug.print("nurl-build: child stopped by signal {d}\n", .{@intFromEnum(sig)});
            std.process.exit(128 + @as(u8, @intCast(@intFromEnum(sig))));
        },
        .unknown => |status| {
            std.debug.print("nurl-build: child exited with unknown status {d}\n", .{status});
            std.process.exit(1);
        },
    }
}

fn splitDriver(
    gpa: std.mem.Allocator,
    driver_override: ?[]const u8,
    init: std.process.Init,
) !std.ArrayList([]const u8) {
    const env_driver = blk: {
        if (driver_override) |val| {
            if (val.len != 0) break :blk val;
        }
        if (init.environ_map.get("NURL_CC")) |val| {
            if (val.len != 0) break :blk val;
        }
        if (init.environ_map.get("CLANG")) |val| {
            if (val.len != 0) break :blk val;
        }
        break :blk "clang";
    };

    var parts: std.ArrayList([]const u8) = .empty;
    errdefer parts.deinit(gpa);

    var it = std.mem.tokenizeAny(u8, env_driver, " \t\r\n");
    while (it.next()) |part| {
        try parts.append(gpa, part);
    }
    if (parts.items.len == 0) {
        try parts.append(gpa, "clang");
    }
    return parts;
}

fn appendPkgConfigOrFallback(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    argv: *std.ArrayList([]const u8),
    pkg_config_exe: []const u8,
    lib: LibrarySpec,
) !void {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ pkg_config_exe, "--libs", lib.pkg_config },
    }) catch |err| {
        if (err == error.FileNotFound) {
            return appendFallback(argv, gpa, lib.fallback);
        }
        return err;
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) {
                var it = std.mem.tokenizeAny(u8, result.stdout, " \t\r\n");
                var appended_any = false;
                while (it.next()) |token| {
                    appended_any = true;
                    try argv.append(gpa, try arena.dupe(u8, token));
                }
                if (appended_any) return;
            }
        },
        else => {},
    }

    try appendFallback(argv, gpa, lib.fallback);
}

fn appendFallback(
    argv: *std.ArrayList([]const u8),
    gpa: std.mem.Allocator,
    fallback: []const []const u8,
) !void {
    for (fallback) |arg| {
        try argv.append(gpa, arg);
    }
}

fn appendDefaultSystemLibs(
    gpa: std.mem.Allocator,
    argv: *std.ArrayList([]const u8),
    mode: SystemLibMode,
) !void {
    switch (mode) {
        .windows => {
            try argv.append(gpa, "-lwinhttp");
        },
        .native => {
            try argv.append(gpa, "-lm");
            try argv.append(gpa, "-lpthread");
        },
        .none => {},
    }
}

fn inferSystemLibMode(target_override: ?[]const u8) SystemLibMode {
    const target = target_override orelse return switch (builtin.os.tag) {
        .windows => .windows,
        else => .native,
    };

    if (std.mem.indexOf(u8, target, "windows") != null) return .windows;
    if (std.mem.startsWith(u8, target, "wasm32-")) return .none;
    if (std.mem.indexOf(u8, target, "macos") != null) return .none;
    if (std.mem.indexOf(u8, target, "darwin") != null) return .none;
    return .native;
}

fn ensureExists(io: std.Io, absolute_path: []const u8, label: []const u8) !void {
    if (!pathExists(io, absolute_path)) {
        std.debug.print("nurl-build: missing {s} at {s}\n", .{ label, absolute_path });
        return error.FileNotFound;
    }
}

fn pathExists(io: std.Io, absolute_path: []const u8) bool {
    if (std.fs.path.isAbsolute(absolute_path)) {
        std.Io.Dir.accessAbsolute(io, absolute_path, .{}) catch return false;
        return true;
    }
    std.Io.Dir.cwd().access(io, absolute_path, .{}) catch return false;
    return true;
}
