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
    api_build,
    api_build_wasm,
    api_runtime_objs,
    nurl,
    wasmnurl,
    fmt,
    fmt_idempotent,
    test_42,
    san_test,
    snapshot_test,
    dwarf_test,
    mkdir,
    copy,
    symlink,
    marker,
    compare,
    buildwasm,
    bench_csv,
    sort_csv,
    install,
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
            .api_build => runApiBuild(init, args[2..]),
            .api_build_wasm => runApiBuildWasm(init, args[2..]),
            .api_runtime_objs => runApiRuntimeObjs(init, args[2..]),
            .nurl => runNurl(init, args[2..]),
            .wasmnurl => runWasmNurl(init, args[2..]),
            .fmt => runFmt(init, args[2..]),
            .fmt_idempotent => runFmtIdempotent(init, args[2..]),
            .test_42 => runTest42(init, args[2..]),
            .san_test => runSanTest(init, args[2..]),
            .snapshot_test => runSnapshotTest(init, args[2..]),
            .dwarf_test => runDwarfTest(init, args[2..]),
            .mkdir => runMkdir(io, args[2..]),
            .copy => runCopy(init.gpa, arena, io, args[2..]),
            .symlink => runSymlink(arena, init, io, args[2..]),
            .marker => runMarker(io, args[2..]),
            .compare => runCompare(init, io, args[2..]),
            .buildwasm => runBuildWasm(init, args[2..]),
            .bench_csv => runBenchCsv(init, args[2..]),
            .sort_csv => runSortCsv(init, args[2..]),
            .install => runInstall(init, args[2..]),
            .mcp_spec_drift => runMcpSpecDrift(init, args[2..]),
            .clean => runClean(init, args[2..]),
            .startdev => runStartDev(init, args[2..]),
            .dockerpush => runDockerPush(init, args[2..]),
        };
    }

    return runLink(init, args[1..]);
}

fn parseCommand(name: []const u8) ?Command {
    if (std.mem.eql(u8, name, "api-build")) return .api_build;
    if (std.mem.eql(u8, name, "api-build-wasm")) return .api_build_wasm;
    if (std.mem.eql(u8, name, "api-runtime-objs")) return .api_runtime_objs;
    if (std.mem.eql(u8, name, "fmt-idempotent")) return .fmt_idempotent;
    if (std.mem.eql(u8, name, "test-42")) return .test_42;
    if (std.mem.eql(u8, name, "san-test")) return .san_test;
    if (std.mem.eql(u8, name, "snapshot-test")) return .snapshot_test;
    if (std.mem.eql(u8, name, "dwarf-test")) return .dwarf_test;
    if (std.mem.eql(u8, name, "bench-csv")) return .bench_csv;
    if (std.mem.eql(u8, name, "sort-csv")) return .sort_csv;
    if (std.mem.eql(u8, name, "mcp-spec-drift")) return .mcp_spec_drift;
    return std.meta.stringToEnum(Command, name);
}

const CompileFlavor = enum {
    native,
    wasm,
};

const ApiBuildKind = enum {
    native,
    windows,
    macos,
};

const ApiBuildWasmConfig = struct {
    root: []const u8,
    src_path: []const u8,
    build_dir: []const u8,
    filename: ?[]const u8,
    target: []const u8,
    runtime: []const u8,
    canvas_obj: []const u8,
    audio_obj: []const u8,
    zig_driver: []const u8,
    wasm_opt: []const u8,
};

const ApiBuildConfig = struct {
    kind: ApiBuildKind,
    root: []const u8,
    src_path: []const u8,
    build_dir: []const u8,
    filename: ?[]const u8,
    opt: []const u8,
    driver: []const u8,
    target: ?[]const u8,
    runtime: []const u8,
    canvas_obj: ?[]const u8,
    canvas_sdl2_marker: ?[]const u8,
};

const ApiBuildPayload = struct {
    http_status: u16 = 200,
    fatal_detail: ?[]const u8 = null,
    status: []const u8,
    message: []const u8,
    filename: ?[]const u8,
    uses_canvas: bool,
    uses_audio: bool,
    nurlc_returncode: i32,
    nurlc_stdout_bytes: usize,
    nurlc_stderr: []const u8,
    clang_returncode: ?i32,
    clang_stdout: ?[]const u8,
    clang_stderr: ?[]const u8,
    stdout: []const u8,
    stderr: []const u8,
    ll_path: ?[]const u8,
    binary_path: ?[]const u8,
};

const ApiBuildWasmPayload = struct {
    http_status: u16 = 200,
    error_message: ?[]const u8 = null,
    error_stage: ?[]const u8 = null,
    error_returncode: ?i32 = null,
    error_stderr: ?[]const u8 = null,
    error_nurlc_stderr: ?[]const u8 = null,
    status: []const u8,
    message: []const u8,
    filename: ?[]const u8,
    uses_canvas: bool,
    uses_audio: bool,
    nurlc_stderr: ?[]const u8,
    clang_stderr: ?[]const u8,
    raw_ll_path: ?[]const u8,
    prepared_ll_path: ?[]const u8,
    wasm_path: ?[]const u8,
};

const WasmAbiEntry = struct {
    name: []const u8,
    ret: u8,
    params: []const u8,
};

const wasm_target_triple = "target triple = \"wasm32-unknown-wasi\"\n";

const wasm_abi_entries = [_]WasmAbiEntry{
    .{ .name = "malloc", .ret = 'p', .params = "s" },
    .{ .name = "calloc", .ret = 'p', .params = "ss" },
    .{ .name = "realloc", .ret = 'p', .params = "ps" },
    .{ .name = "free", .ret = 'v', .params = "p" },
    .{ .name = "puts", .ret = 'i', .params = "p" },
    .{ .name = "putchar", .ret = 'i', .params = "i" },
    .{ .name = "getchar", .ret = 'i', .params = "" },
    .{ .name = "strlen", .ret = 's', .params = "p" },
    .{ .name = "strcmp", .ret = 'i', .params = "pp" },
    .{ .name = "strncmp", .ret = 'i', .params = "pps" },
    .{ .name = "strcpy", .ret = 'p', .params = "pp" },
    .{ .name = "strncpy", .ret = 'p', .params = "pps" },
    .{ .name = "strcat", .ret = 'p', .params = "pp" },
    .{ .name = "strdup", .ret = 'p', .params = "p" },
    .{ .name = "memcpy", .ret = 'p', .params = "pps" },
    .{ .name = "memmove", .ret = 'p', .params = "pps" },
    .{ .name = "memset", .ret = 'p', .params = "pis" },
    .{ .name = "memcmp", .ret = 'i', .params = "pps" },
    .{ .name = "atoi", .ret = 'i', .params = "p" },
    .{ .name = "abs", .ret = 'i', .params = "i" },
    .{ .name = "exit", .ret = 'v', .params = "i" },
    .{ .name = "rand", .ret = 'i', .params = "" },
    .{ .name = "srand", .ret = 'v', .params = "s" },
    .{ .name = "system", .ret = 'i', .params = "p" },
    .{ .name = "write", .ret = 'i', .params = "ips" },
    .{ .name = "read", .ret = 'i', .params = "ips" },
    .{ .name = "open", .ret = 'i', .params = "pii" },
    .{ .name = "close", .ret = 'i', .params = "i" },
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

const Test42Expectation = union(enum) {
    run_contains: []const []const u8,
    compile_error_contains: []const u8,
};

const Test42Case = struct {
    label: []const u8,
    source: []const u8,
    expectation: Test42Expectation,
};

const test_42_cases = [_]Test42Case{
    .{
        .label = "R1",
        .source = "compiler/tests/result_multifield.nu",
        .expectation = .{ .run_contains = &.{
            "pt: x=3 y=4",
            "pt-neg: err",
            "quad: 7 11 13 17",
            "tagged: hello count=42",
        } },
    },
    .{
        .label = "R2",
        .source = "compiler/tests/result_multifield_try.nu",
        .expectation = .{ .run_contains = &.{
            "pt: 13 24",
            "pt-neg: propagated",
            "tag: hello/7",
        } },
    },
    .{
        .label = "E1",
        .source = "compiler/tests/should_fail_t14_try_non_result.nu",
        .expectation = .{ .compile_error_contains = "try operator" },
    },
    .{
        .label = "E2",
        .source = "compiler/tests/should_fail_t15_result_type_mismatch.nu",
        .expectation = .{ .compile_error_contains = "try propagation type mismatch" },
    },
};

fn runTest42(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var driver: ?[]const u8 = null;
    var runtime_override: ?[]const u8 = null;
    var opt: []const u8 = "-O2";
    var disable_lto = true;

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--driver")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            driver = args[i];
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            runtime_override = args[i];
        } else if (std.mem.eql(u8, arg, "--opt")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            opt = args[i];
        } else if (std.mem.eql(u8, arg, "--lto")) {
            disable_lto = false;
        } else if (std.mem.eql(u8, arg, "--no-lto")) {
            disable_lto = true;
        } else {
            std.debug.print("nurl-build: unknown test-42 arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len != i) {
        std.debug.print(
            "usage: nurl-build test-42 [--root <path>] [--driver <cmd>] [--runtime <path>] [--opt <-O2>] [--lto|--no-lto]\n",
            .{},
        );
        return error.InvalidArgs;
    }

    const root_abs = try absolutePath(arena, root);
    const nurlc_path = try resolveNurlc(init, root_abs);
    const runtime_path = runtime_override orelse try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.o" });
    const workdir = try std.fs.path.join(arena, &.{ root_abs, "build", "test-42" });
    try ensureExists(io, nurlc_path, "nurlc");
    try ensureExists(io, runtime_path, "runtime.o");
    try ensureDirPath(io, workdir);

    var pass_count: usize = 0;
    var fail_count: usize = 0;

    std.debug.print("============================================\n", .{});
    std.debug.print("  4.2 Result-type and try-propagation tests\n", .{});
    std.debug.print("============================================\n\n", .{});

    for (test_42_cases) |case| {
        const basename = std.fs.path.basename(case.source);
        const stem = basename[0 .. basename.len - ".nu".len];
        const ll_name = try std.fmt.allocPrint(arena, "{s}.ll", .{stem});
        const stderr_name = try std.fmt.allocPrint(arena, "{s}.stderr", .{stem});
        const stdout_name = try std.fmt.allocPrint(arena, "{s}.stdout", .{stem});
        const ll_path = try std.fs.path.join(arena, &.{ workdir, ll_name });
        const bin_path = try testBinaryPath(arena, workdir, stem);
        const stdout_log = try std.fs.path.join(arena, &.{ workdir, stdout_name });
        const stderr_log = try std.fs.path.join(arena, &.{ workdir, stderr_name });

        std.debug.print("[{s}] {s}\n", .{ case.label, basename });

        const compile_result = try std.process.run(gpa, io, .{
            .argv = &.{ nurlc_path, case.source },
            .cwd = .{ .path = root_abs },
        });
        defer {
            gpa.free(compile_result.stdout);
            gpa.free(compile_result.stderr);
        }
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = stderr_log,
            .data = compile_result.stderr,
        });

        switch (case.expectation) {
            .compile_error_contains => |needle| {
                if (runResultSucceeded(compile_result.term) or std.mem.indexOf(u8, compile_result.stderr, needle) == null) {
                    std.debug.print("  FAIL: wrong compiler error\n", .{});
                    if (compile_result.stderr.len != 0) std.debug.print("{s}\n", .{compile_result.stderr});
                    fail_count += 1;
                } else {
                    std.debug.print("  PASS\n", .{});
                    pass_count += 1;
                }
            },
            .run_contains => |needles| {
                if (!runResultSucceeded(compile_result.term)) {
                    std.debug.print("  FAIL: compilation failed\n", .{});
                    if (compile_result.stderr.len != 0) std.debug.print("{s}\n", .{compile_result.stderr});
                    fail_count += 1;
                    continue;
                }

                try std.Io.Dir.cwd().writeFile(io, .{
                    .sub_path = ll_path,
                    .data = compile_result.stdout,
                });

                var link_args: std.ArrayList([]const u8) = .empty;
                defer link_args.deinit(gpa);
                try link_args.appendSlice(gpa, &.{ "--opt", opt, "--runtime", runtime_path });
                if (driver) |driver_override| {
                    try link_args.appendSlice(gpa, &.{ "--driver", driver_override });
                }
                if (disable_lto) {
                    try link_args.append(gpa, "--no-lto");
                }
                try link_args.appendSlice(gpa, &.{ root_abs, ll_path, bin_path });

                const link_result = try runLinkCapture(init, link_args.items);
                defer {
                    gpa.free(link_result.stdout);
                    gpa.free(link_result.stderr);
                }
                if (!runResultSucceeded(link_result.term)) {
                    std.debug.print("  FAIL: link failed\n", .{});
                    if (link_result.stderr.len != 0) std.debug.print("{s}\n", .{link_result.stderr});
                    fail_count += 1;
                    continue;
                }

                const run_result = try std.process.run(gpa, io, .{
                    .argv = &.{bin_path},
                    .cwd = .{ .path = workdir },
                });
                defer {
                    gpa.free(run_result.stdout);
                    gpa.free(run_result.stderr);
                }
                try std.Io.Dir.cwd().writeFile(io, .{
                    .sub_path = stdout_log,
                    .data = run_result.stdout,
                });
                try std.Io.Dir.cwd().writeFile(io, .{
                    .sub_path = stderr_log,
                    .data = run_result.stderr,
                });

                if (!runResultSucceeded(run_result.term) or !containsAll(run_result.stdout, needles)) {
                    std.debug.print("  FAIL: wrong output\n", .{});
                    if (run_result.stdout.len != 0) std.debug.print("{s}\n", .{run_result.stdout});
                    if (run_result.stderr.len != 0) std.debug.print("{s}\n", .{run_result.stderr});
                    fail_count += 1;
                    continue;
                }

                std.debug.print("  PASS\n", .{});
                pass_count += 1;
            },
        }
    }

    std.debug.print("\n============================================\n", .{});
    std.debug.print("  Results: {d} PASS  /  {d} FAIL  (of {d})\n", .{ pass_count, fail_count, test_42_cases.len });
    std.debug.print("============================================\n", .{});

    if (fail_count != 0) return error.ChildProcessFailed;
}

fn runSanTest(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var timeout_seconds: u32 = 30;
    var driver = try resolveSanTestDriver(init);

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            timeout_seconds = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--driver")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            driver = args[i];
        } else {
            std.debug.print("nurl-build: unknown san-test arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len != i) {
        std.debug.print("usage: nurl-build san-test [--root <path>] [--timeout <seconds>] [--driver <cmd>]\n", .{});
        return error.InvalidArgs;
    }

    if (init.environ_map.get("TIMEOUT")) |timeout_env| {
        timeout_seconds = std.fmt.parseInt(u32, timeout_env, 10) catch timeout_seconds;
    }

    const root_abs = try absolutePath(arena, root);
    const nurlc_path = try resolveNurlc(init, root_abs);
    const runtime_path = try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.o" });
    const pq_marker_path = try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.pq" });
    const workdir = try std.fs.path.join(arena, &.{ root_abs, "build", "tests-san" });
    const logdir = try std.fs.path.join(arena, &.{ workdir, "logs" });
    const summary_path = try std.fs.path.join(arena, &.{ workdir, "SUMMARY.txt" });

    try ensureExists(io, nurlc_path, "nurlc");
    try ensureExists(io, runtime_path, "runtime.o");
    try ensureDirPath(io, logdir);
    try ensureSanitizedRuntime(init, runtime_path);

    var test_files: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &test_files);
    try appendNuFilesFromDir(gpa, io, root_abs, "compiler/tests", &test_files);
    std.sort.heap([]const u8, test_files.items, {}, lessThanString);

    var summary: std.ArrayList(u8) = .empty;
    defer summary.deinit(gpa);
    var san_fails: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &san_fails);

    var san_env = try buildSanTestEnv(init);
    defer san_env.deinit();

    var n_total: usize = 0;
    var n_pass: usize = 0;
    var n_san_fail: usize = 0;
    var n_compile_fail: usize = 0;
    var n_link_fail: usize = 0;

    std.debug.print("{s: <44} {s}\n", .{ "TEST", "VERDICT" });
    std.debug.print("{s: <44} {s}\n", .{ "----", "-------" });

    for (test_files.items) |rel_src| {
        const basename = std.fs.path.basename(rel_src);
        const name = basename[0 .. basename.len - ".nu".len];
        n_total += 1;

        if (isSanSkipName(name) or (std.mem.eql(u8, name, "postgres_basic") and !pathExists(io, pq_marker_path))) {
            std.debug.print("{s: <44} SKIP\n", .{name});
            continue;
        }

        const ll_name = try std.fmt.allocPrint(arena, "{s}.ll", .{name});
        const stdout_name = try std.fmt.allocPrint(arena, "{s}.stdout", .{name});
        const stderr_name = try std.fmt.allocPrint(arena, "{s}.stderr", .{name});
        const ll_path = try std.fs.path.join(arena, &.{ workdir, ll_name });
        const bin_path = try testBinaryPath(arena, workdir, name);
        const stdout_log = try std.fs.path.join(arena, &.{ logdir, stdout_name });
        const stderr_log = try std.fs.path.join(arena, &.{ logdir, stderr_name });

        const compile_result = try std.process.run(gpa, io, .{
            .argv = &.{ nurlc_path, rel_src },
            .cwd = .{ .path = root_abs },
        });
        defer {
            gpa.free(compile_result.stdout);
            gpa.free(compile_result.stderr);
        }
        if (!runResultSucceeded(compile_result.term)) {
            std.debug.print("{s: <44} COMPILE_FAIL\n", .{name});
            try appendSummaryLine(gpa, &summary, "COMPILE_FAIL {s}\n", .{name});
            n_compile_fail += 1;
            continue;
        }

        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = ll_path,
            .data = compile_result.stdout,
        });

        var link_args: std.ArrayList([]const u8) = .empty;
        defer link_args.deinit(gpa);
        try link_args.appendSlice(gpa, &.{
            "--opt",
            "-O1",
            "--driver",
            driver,
            "--runtime",
            runtime_path,
            "--flag",
            "-fsanitize=address,undefined",
            "--flag",
            "-fno-omit-frame-pointer",
            "--no-lto",
            root_abs,
            ll_path,
            bin_path,
        });

        const link_result = try runLinkCapture(init, link_args.items);
        defer {
            gpa.free(link_result.stdout);
            gpa.free(link_result.stderr);
        }
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = stderr_log,
            .data = link_result.stderr,
        });
        if (!runResultSucceeded(link_result.term)) {
            std.debug.print("{s: <44} LINK_FAIL\n", .{name});
            try appendSummaryLine(gpa, &summary, "LINK_FAIL {s}\n", .{name});
            n_link_fail += 1;
            continue;
        }

        const run_result = std.process.run(gpa, io, .{
            .argv = &.{bin_path},
            .cwd = .{ .path = workdir },
            .environ_map = &san_env,
            .timeout = .{ .duration = .{
                .clock = .boot,
                .raw = .fromSeconds(timeout_seconds),
            } },
        }) catch |err| switch (err) {
            error.Timeout => {
                try std.Io.Dir.cwd().writeFile(io, .{
                    .sub_path = stderr_log,
                    .data = "timeout\n",
                });
                std.debug.print("{s: <44} PASS (exit=124, no sanitizer report)\n", .{name});
                n_pass += 1;
                continue;
            },
            else => return err,
        };
        defer {
            gpa.free(run_result.stdout);
            gpa.free(run_result.stderr);
        }
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = stdout_log,
            .data = run_result.stdout,
        });
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = stderr_log,
            .data = run_result.stderr,
        });

        if (containsSanitizerMarker(run_result.stderr)) {
            const exit_code = childExitCodeOr(run_result.term, 1);
            std.debug.print("{s: <44} SAN_FAIL (exit={d})\n", .{ name, exit_code });
            try appendSummaryLine(gpa, &summary, "SAN_FAIL {s} exit={d}\n", .{ name, exit_code });
            try san_fails.append(gpa, try gpa.dupe(u8, name));
            n_san_fail += 1;
            continue;
        }

        const exit_code = childExitCodeOr(run_result.term, 1);
        if (exit_code != 0) {
            std.debug.print("{s: <44} PASS (exit={d}, no sanitizer report)\n", .{ name, exit_code });
        } else {
            std.debug.print("{s: <44} PASS\n", .{name});
        }
        n_pass += 1;
    }

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = summary_path,
        .data = summary.items,
    });

    std.debug.print("\n── Sanitized run summary ──\n", .{});
    std.debug.print("  total      : {d}\n", .{n_total});
    std.debug.print("  PASS       : {d}     (includes tests with non-zero deliberate exit)\n", .{n_pass});
    std.debug.print("  SAN_FAIL   : {d}     (AddressSanitizer / UBSan / LSan caught a problem)\n", .{n_san_fail});
    std.debug.print("  COMPILE    : {d}\n", .{n_compile_fail});
    std.debug.print("  LINK       : {d}\n", .{n_link_fail});
    std.debug.print("  logs       : {s}\n\n", .{logdir});

    if (n_san_fail != 0) {
        std.debug.print("── First sanitizer report from each SAN_FAIL test ──\n", .{});
        for (san_fails.items) |name| {
            const stderr_name = try std.fmt.allocPrint(arena, "{s}.stderr", .{name});
            const stderr_log = try std.fs.path.join(arena, &.{ logdir, stderr_name });
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, stderr_log, gpa, .unlimited);
            defer gpa.free(bytes);
            std.debug.print("\n▶ {s}\n", .{name});
            printFirstLines(bytes, 40);
            std.debug.print("  …(see {s} for the full report)\n", .{stderr_log});
        }
        return error.ChildProcessFailed;
    }
}

fn runSnapshotTest(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var baseline_override: ?[]const u8 = null;
    var results_override: ?[]const u8 = null;
    var workdir_override: ?[]const u8 = null;
    var timeout_seconds: u32 = 10;
    var max_output_lines: usize = 200;
    var opt: []const u8 = "-O2";

    var i: usize = 0;
    while (i < args.len and std.mem.startsWith(u8, args[i], "--")) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--baseline")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            baseline_override = args[i];
        } else if (std.mem.eql(u8, arg, "--results")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            results_override = args[i];
        } else if (std.mem.eql(u8, arg, "--workdir")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            workdir_override = args[i];
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            timeout_seconds = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--max-output-lines")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            max_output_lines = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--opt")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            opt = args[i];
        } else {
            std.debug.print("nurl-build: unknown snapshot-test arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    if (args.len != i) {
        std.debug.print(
            "usage: nurl-build snapshot-test [--root <path>] [--baseline <path>] [--results <path>] [--workdir <path>] [--timeout <seconds>] [--max-output-lines <n>] [--opt <-O2>]\n",
            .{},
        );
        return error.InvalidArgs;
    }

    if (init.environ_map.get("TIMEOUT")) |timeout_env| {
        timeout_seconds = std.fmt.parseInt(u32, timeout_env, 10) catch timeout_seconds;
    }
    if (init.environ_map.get("MAX_OUT_LINES")) |max_out_env| {
        max_output_lines = std.fmt.parseInt(usize, max_out_env, 10) catch max_output_lines;
    }
    if (init.environ_map.get("NURL_SAN")) |san_mode| {
        if (std.mem.eql(u8, san_mode, "1")) {
            std.debug.print("NURL_SAN=1 set — use: zig build san-test -Dsan=true\n", .{});
            std.process.exit(2);
        }
    }

    const root_abs = try absolutePath(arena, root);
    const workdir = try resolvePathFromRoot(arena, root_abs, workdir_override orelse "build/tests");
    const results_path = try resolvePathFromRoot(arena, root_abs, results_override orelse "compiler/tests/testresults.txt");
    const baseline_path = try resolvePathFromRoot(arena, root_abs, baseline_override orelse "compiler/tests/correct.txt");
    const nurlc_path = init.environ_map.get("NURLC") orelse try resolveNurlc(init, root_abs);
    const runtime_path = init.environ_map.get("NURL_RUNTIME") orelse try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.o" });
    const enable_http_tests = init.environ_map.get("NURL_HTTP_TESTS") orelse "0";
    const enable_net_tests = init.environ_map.get("NURL_NET_TESTS") orelse "0";
    const pq_marker_path = try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.pq" });

    try ensureExists(io, nurlc_path, "nurlc");
    try ensureExists(io, runtime_path, "runtime.o");
    try ensureDirPath(io, workdir);

    var test_files: std.ArrayList([]const u8) = .empty;
    defer freePathList(gpa, &test_files);
    try appendNuFilesFromDir(gpa, io, root_abs, "compiler/tests", &test_files);
    std.sort.heap([]const u8, test_files.items, {}, lessThanString);

    var results: std.ArrayList(u8) = .empty;
    defer results.deinit(gpa);

    for (test_files.items) |rel_src| {
        const basename = std.fs.path.basename(rel_src);
        const name = basename[0 .. basename.len - ".nu".len];
        if (isSnapshotHelperModule(name)) continue;
        if (shouldSkipSnapshotTest(name, enable_http_tests, enable_net_tests, pathExists(io, pq_marker_path))) continue;

        const ll_name = try std.fmt.allocPrint(arena, "{s}.ll", .{name});
        const out_name = try std.fmt.allocPrint(arena, "{s}.out", .{name});
        const warn_name = try std.fmt.allocPrint(arena, "{s}.werr", .{name});
        const ll_path = try std.fs.path.join(arena, &.{ workdir, ll_name });
        const bin_path = try testBinaryPath(arena, workdir, name);
        const out_path = try std.fs.path.join(arena, &.{ workdir, out_name });
        const warn_path = try std.fs.path.join(arena, &.{ workdir, warn_name });

        try deleteFileIfExists(io, ll_path);
        try deleteFileIfExists(io, bin_path);
        try deleteFileIfExists(io, out_path);
        try deleteFileIfExists(io, warn_path);

        try appendSummaryLine(gpa, &results, "=== {s} ===\n", .{name});

        const compile_result = if (std.mem.startsWith(u8, name, "borrow_"))
            try std.process.run(gpa, io, .{
                .argv = &.{ nurlc_path, "--borrowck", rel_src },
                .cwd = .{ .path = root_abs },
            })
        else
            try std.process.run(gpa, io, .{
                .argv = &.{ nurlc_path, rel_src },
                .cwd = .{ .path = root_abs },
            });
        defer {
            gpa.free(compile_result.stdout);
            gpa.free(compile_result.stderr);
        }

        if (!runResultSucceeded(compile_result.term)) {
            try appendSummaryLine(gpa, &results, "COMPILE FAIL\n\n", .{});
            continue;
        }

        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = ll_path,
            .data = compile_result.stdout,
        });
        try appendSummaryLine(gpa, &results, "COMPILE OK\n", .{});

        if (std.mem.startsWith(u8, name, "borrow_")) {
            if (compile_result.stderr.len != 0) {
                const stripped = try stripRepoPrefixAlloc(gpa, compile_result.stderr, root_abs);
                defer gpa.free(stripped);
                try appendSummaryLine(gpa, &results, "WARNINGS\n", .{});
                try appendOutputCapped(gpa, &results, stripped, max_output_lines);
            }
            try appendSummaryLine(gpa, &results, "\n", .{});
            continue;
        }

        if (std.mem.startsWith(u8, name, "should_warn_") and compile_result.stderr.len != 0) {
            const stripped = try stripRepoPrefixAlloc(gpa, compile_result.stderr, root_abs);
            defer gpa.free(stripped);
            try appendSummaryLine(gpa, &results, "WARNINGS\n", .{});
            try appendOutputCapped(gpa, &results, stripped, max_output_lines);
        }

        var link_args: std.ArrayList([]const u8) = .empty;
        defer link_args.deinit(gpa);
        try link_args.appendSlice(gpa, &.{ "--opt", opt, "--runtime", runtime_path, root_abs, ll_path, bin_path });

        const link_result = try runLinkCapture(init, link_args.items);
        defer {
            gpa.free(link_result.stdout);
            gpa.free(link_result.stderr);
        }
        if (!runResultSucceeded(link_result.term)) {
            try appendSummaryLine(gpa, &results, "LINK FAIL\n\n", .{});
            continue;
        }

        try appendSummaryLine(gpa, &results, "LINK OK\n", .{});

        const run_result = try runSnapshotBinary(init, workdir, name, timeout_seconds);
        defer gpa.free(run_result.output);
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = out_path,
            .data = run_result.output,
        });

        try appendSummaryLine(gpa, &results, "EXIT {d}\n", .{childExitCodeOr(run_result.term, 1)});
        try appendSummaryLine(gpa, &results, "OUTPUT\n", .{});
        try appendOutputCapped(gpa, &results, run_result.output, max_output_lines);
        try appendSummaryLine(gpa, &results, "\n", .{});
    }

    try ensureParentDir(io, results_path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = results_path,
        .data = results.items,
    });

    if (!pathExists(io, baseline_path)) {
        try ensureParentDir(io, baseline_path);
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = baseline_path,
            .data = results.items,
        });
        std.debug.print("No baseline found — created correct.txt from current results.\n", .{});
        std.debug.print("Review it and commit if it reflects the expected state.\n", .{});
        return;
    }

    const baseline_bytes = try std.Io.Dir.cwd().readFileAlloc(io, baseline_path, gpa, .unlimited);
    defer gpa.free(baseline_bytes);

    if (std.mem.eql(u8, results.items, baseline_bytes)) {
        std.debug.print("TESTS PASSED\n", .{});
        return;
    }

    std.debug.print("TESTS FAILED — testresults.txt differs from correct.txt:\n\n", .{});
    try printBaselineDiff(init, baseline_path, results_path);
    return error.FilesDiffer;
}

const SnapshotRunResult = struct {
    term: std.process.Child.Term,
    output: []u8,
};

fn runSnapshotBinary(
    init: std.process.Init,
    workdir: []const u8,
    name: []const u8,
    timeout_seconds: u32,
) !SnapshotRunResult {
    const gpa = init.gpa;
    const io = init.io;
    const timeout: std.Io.Timeout = .{ .duration = .{
        .clock = .boot,
        .raw = .fromSeconds(timeout_seconds),
    } };

    if (builtin.os.tag == .windows) {
        const rel_bin = try std.fmt.allocPrint(gpa, ".\\{s}.exe", .{name});
        defer gpa.free(rel_bin);

        const run_result: std.process.RunResult = std.process.run(gpa, io, .{
            .argv = &.{rel_bin},
            .cwd = .{ .path = workdir },
            .timeout = timeout,
        }) catch |err| switch (err) {
            error.Timeout => return .{
                .term = .{ .exited = 124 },
                .output = try gpa.dupe(u8, ""),
            },
            else => return err,
        };
        defer {
            gpa.free(run_result.stdout);
            gpa.free(run_result.stderr);
        }

        return .{
            .term = run_result.term,
            .output = try std.mem.concat(gpa, u8, &.{ run_result.stdout, run_result.stderr }),
        };
    }

    const shell_command = try std.fmt.allocPrint(gpa, "exec ./{s} 2>&1", .{name});
    defer gpa.free(shell_command);

    const run_result: std.process.RunResult = std.process.run(gpa, io, .{
        .argv = &.{ "sh", "-c", shell_command },
        .cwd = .{ .path = workdir },
        .timeout = timeout,
    }) catch |err| switch (err) {
        error.Timeout => return .{
            .term = .{ .exited = 124 },
            .output = try gpa.dupe(u8, ""),
        },
        else => return err,
    };
    defer {
        gpa.free(run_result.stdout);
        gpa.free(run_result.stderr);
    }

    return .{
        .term = run_result.term,
        .output = try std.mem.concat(gpa, u8, &.{ run_result.stdout, run_result.stderr }),
    };
}

fn runDwarfTest(init: std.process.Init, args: []const []const u8) !void {
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
            std.debug.print("usage: nurl-build dwarf-test [--root <path>]\n", .{});
            std.process.exit(0);
        } else {
            std.debug.print("nurl-build: unknown dwarf-test arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }
    if (i != args.len) return error.InvalidArgs;

    const gdb = try firstAvailableCommand(arena, gpa, io, &.{"gdb"}, &.{"--version"});
    if (gdb == null) {
        std.debug.print("SKIP: gdb not found on PATH — DWARF behavioural test skipped\n", .{});
        return;
    }

    const root_abs = try absolutePath(arena, root);
    const basic_src = try std.fs.path.join(arena, &.{ root_abs, "compiler", "tests", "dwarf_basic.nu" });
    const basic_bin = try std.fs.path.join(arena, &.{ root_abs, "build", "dwarf_basic_dbg" });
    const struct_src = try std.fs.path.join(arena, &.{ root_abs, "compiler", "tests", "dwarf_struct.nu" });
    const struct_bin = try std.fs.path.join(arena, &.{ root_abs, "build", "dwarf_struct_dbg" });

    try ensureExists(io, basic_src, "compiler/tests/dwarf_basic.nu");

    std.debug.print("[1/5] building {s} with --debug\n", .{basic_src});
    try compileDwarfFixture(init, root_abs, basic_src, basic_bin);

    std.debug.print("[2/5] checking DWARF debug info is present\n", .{});
    try verifyDwarfDebugInfo(init, basic_bin);
    std.debug.print("  ok: debug info present\n", .{});

    std.debug.print("[3/5] gdb-batch: break + run + info locals + print\n", .{});
    const basic_gdb = try runCombinedCapture(init, &.{
        gdb.?,
        "-batch",
        "-ex",
        "set debuginfod enabled off",
        "-ex",
        "break square",
        "-ex",
        "run",
        "-ex",
        "info args",
        "-ex",
        "info locals",
        "-ex",
        "next",
        "-ex",
        "print sq",
        "-ex",
        "backtrace",
        "-ex",
        "quit",
        basic_bin,
    }, null);
    defer gpa.free(basic_gdb);

    if (std.mem.indexOf(u8, basic_gdb, "Breakpoint 1") == null or std.mem.indexOf(u8, basic_gdb, "square") == null) {
        return dwarfFail("breakpoint did not resolve to function 'square'");
    }
    std.debug.print("  ok: break square resolved to source\n", .{});

    if (std.mem.indexOf(u8, basic_gdb, "dwarf_basic.nu") == null) {
        return dwarfFail("gdb did not associate frames with dwarf_basic.nu");
    }
    std.debug.print("  ok: frames carry source-file association\n", .{});

    if (std.mem.indexOf(u8, basic_gdb, "sq = 49") == null and std.mem.indexOf(u8, basic_gdb, "sq = 0x31") == null) {
        return dwarfFail("print sq did not return 49 (expected square(7) = 49)");
    }
    std.debug.print("  ok: print sq returned 49\n", .{});

    std.debug.print("[4/5] llvm-dwarfdump (optional)\n", .{});
    if (try firstAvailableCommand(arena, gpa, io, &.{"llvm-dwarfdump"}, &.{"--version"})) |llvm_dwarfdump| {
        const result = try std.process.run(gpa, io, .{
            .argv = &.{ llvm_dwarfdump, "--verify", basic_bin },
        });
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        if (!runResultSucceeded(result.term)) {
            if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
            if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
            return dwarfFail("llvm-dwarfdump --verify rejected the binary");
        }
        std.debug.print("  ok: llvm-dwarfdump --verify clean\n", .{});
    } else {
        std.debug.print("  skip: llvm-dwarfdump not on PATH\n", .{});
    }

    if (!pathExists(io, struct_src)) {
        std.debug.print("WARN: {s} not present — skipping struct phase\n", .{struct_src});
    } else {
        std.debug.print("[5/5] Phase 6 composite types — ptype + print over %Point\n", .{});
        try compileDwarfFixture(init, root_abs, struct_src, struct_bin);
        std.debug.print("  ok: dwarf_struct.nu built with --debug\n", .{});

        const struct_gdb = try runCombinedCapture(init, &.{
            gdb.?,
            "-batch",
            "-ex",
            "set debuginfod enabled off",
            "-ex",
            "break _nurl_main",
            "-ex",
            "run",
            "-ex",
            "next",
            "-ex",
            "print p",
            "-ex",
            "print p.x",
            "-ex",
            "print p.y",
            "-ex",
            "ptype p",
            "-ex",
            "quit",
            struct_bin,
        }, null);
        defer gpa.free(struct_gdb);

        if (std.mem.indexOf(u8, struct_gdb, "x = 3") == null or std.mem.indexOf(u8, struct_gdb, "y = 7") == null) {
            return dwarfFail("print p did not show {x = 3, y = 7}");
        }
        std.debug.print("  ok: print p renders composite as {{x = 3, y = 7}}\n", .{});

        if (std.mem.indexOf(u8, struct_gdb, "= 3") == null) {
            return dwarfFail("print p.x did not return 3");
        }
        std.debug.print("  ok: print p.x resolved to 3\n", .{});

        if (std.mem.indexOf(u8, struct_gdb, "struct Point") == null) {
            return dwarfFail("ptype p did not show 'struct Point'");
        }
        std.debug.print("  ok: ptype p shows 'struct Point'\n", .{});

        if (std.mem.indexOf(u8, struct_gdb, "\tx;") == null and std.mem.indexOf(u8, struct_gdb, " x;") == null and std.mem.indexOf(u8, struct_gdb, "\tx =") == null and std.mem.indexOf(u8, struct_gdb, " x =") == null) {
            return dwarfFail("ptype p did not list field 'x'");
        }
        if (std.mem.indexOf(u8, struct_gdb, "\ty;") == null and std.mem.indexOf(u8, struct_gdb, " y;") == null and std.mem.indexOf(u8, struct_gdb, "\ty =") == null and std.mem.indexOf(u8, struct_gdb, " y =") == null) {
            return dwarfFail("ptype p did not list field 'y'");
        }
        std.debug.print("  ok: ptype p lists fields x and y by name\n", .{});
    }

    std.debug.print("\nDWARF TEST PASSED\n", .{});
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

const CsvSortRow = struct {
    index: usize,
    line: []const u8,
    fields: [8][]const u8,
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

fn runSortCsv(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var input_path_arg: ?[]const u8 = null;
    var output_path_arg: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--input")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            input_path_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            output_path_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                "usage: nurl-build sort-csv [--root <path>] [--input <path>] [--output <path>]\n",
                .{},
            );
            std.process.exit(0);
        } else {
            std.debug.print("nurl-build: unknown sort-csv arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    const root_abs = try absolutePath(arena, root);
    const compare_dir = try std.fs.path.join(arena, &.{ root_abs, "compare" });
    const input_path = if (input_path_arg) |path|
        try resolvePathFromRoot(arena, root_abs, path)
    else
        try std.fs.path.join(arena, &.{ compare_dir, "test_data.csv" });
    const output_path = if (output_path_arg) |path|
        try resolvePathFromRoot(arena, root_abs, path)
    else
        try std.fs.path.join(arena, &.{ compare_dir, "sorted_data.csv" });

    try ensureExists(io, input_path, "compare/test_data.csv");

    const removed_existing = pathExists(io, output_path);
    try deleteFileIfExists(io, output_path);
    if (removed_existing) {
        std.debug.print("Removed existing {s}\n", .{output_path});
    }

    const total_start = std.Io.Clock.Timestamp.now(io, .boot);
    std.debug.print("Starting sort process\n", .{});

    const csv_bytes = try std.Io.Dir.cwd().readFileAlloc(io, input_path, gpa, .unlimited);
    defer gpa.free(csv_bytes);
    const read_done = std.Io.Clock.Timestamp.now(io, .boot);
    const read_ms = total_start.durationTo(read_done).raw.toMilliseconds();

    const first_newline = std.mem.indexOfScalar(u8, csv_bytes, '\n') orelse return error.InvalidData;
    const header_line = csv_bytes[0..first_newline];
    const body = csv_bytes[first_newline + 1 ..];

    var rows: std.ArrayList(CsvSortRow) = .empty;
    defer rows.deinit(gpa);

    var row_start: usize = 0;
    var row_index: usize = 0;
    while (row_start < body.len) {
        const rel_end = std.mem.indexOfScalarPos(u8, body, row_start, '\n') orelse body.len;
        const raw_line = body[row_start..rel_end];
        if (raw_line.len != 0) {
            try rows.append(gpa, try parseCsvSortRow(raw_line, row_index));
            row_index += 1;
        }
        if (rel_end == body.len) break;
        row_start = rel_end + 1;
    }

    std.debug.print("Read {d} rows in {d}ms.\n", .{ rows.items.len, read_ms });

    const sort_start = std.Io.Clock.Timestamp.now(io, .boot);
    std.sort.heap(CsvSortRow, rows.items, {}, lessThanCsvSortRow);
    const sort_ms = sort_start.durationTo(std.Io.Clock.Timestamp.now(io, .boot)).raw.toMilliseconds();
    std.debug.print("Sort completed in {d}ms.\n", .{sort_ms});

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, header_line);
    try out.append(gpa, '\n');
    for (rows.items) |row| {
        try out.appendSlice(gpa, row.line);
        try out.append(gpa, '\n');
    }

    const write_start = std.Io.Clock.Timestamp.now(io, .boot);
    try ensureParentDir(io, output_path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = out.items,
    });
    const write_ms = write_start.durationTo(std.Io.Clock.Timestamp.now(io, .boot)).raw.toMilliseconds();
    std.debug.print("Write completed in {d}ms.\n", .{write_ms});
    std.debug.print("\nTotal time elapsed: {d}ms\n", .{total_start.durationTo(std.Io.Clock.Timestamp.now(io, .boot)).raw.toMilliseconds()});
    std.debug.print("Finished: {s}\n", .{output_path});
}

fn parseCsvSortRow(line: []const u8, index: usize) !CsvSortRow {
    var fields: [8][]const u8 = undefined;
    var field_idx: usize = 0;
    var start: usize = 0;

    for (line, 0..) |ch, pos| {
        if (ch != ',') continue;
        if (field_idx >= fields.len) return error.InvalidData;
        fields[field_idx] = line[start..pos];
        field_idx += 1;
        start = pos + 1;
    }
    if (field_idx != fields.len - 1) return error.InvalidData;
    fields[field_idx] = std.mem.trim(u8, line[start..], "\r");

    return .{
        .index = index,
        .line = line,
        .fields = fields,
    };
}

fn lessThanCsvSortRow(_: void, lhs: CsvSortRow, rhs: CsvSortRow) bool {
    const order = [_]usize{ 7, 6, 5, 4, 3, 2, 1, 0 };
    inline for (order) |field_idx| {
        switch (std.mem.order(u8, lhs.fields[field_idx], rhs.fields[field_idx])) {
            .lt => return false,
            .gt => return true,
            .eq => {},
        }
    }
    return lhs.index < rhs.index;
}

fn runInstall(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    var root: []const u8 = ".";
    var no_vscode = false;
    var no_path = false;
    var force = false;
    var uninstall = false;
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--no-vscode")) {
            no_vscode = true;
        } else if (std.mem.eql(u8, arg, "--no-path")) {
            no_path = true;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--uninstall")) {
            uninstall = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printInstallUsage();
            std.process.exit(0);
        } else {
            std.debug.print("nurl-build: unknown install arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        i += 1;
    }

    const root_abs = try absolutePath(arena, root);
    const zig_bin = init.environ_map.get("NURL_ZIG") orelse "zig";
    const compiler_name = if (builtin.os.tag == .windows) "nurlc.exe" else "nurlc";
    const lsp_name = if (builtin.os.tag == .windows) "nurl-lsp.exe" else "nurl-lsp";
    const compiler_path = try std.fs.path.join(arena, &.{ root_abs, "build", compiler_name });
    const lsp_path = try std.fs.path.join(arena, &.{ root_abs, "build", lsp_name });
    const home = try resolveHomeDir(init);
    const bindir = if (builtin.os.tag == .windows)
        try std.fs.path.join(arena, &.{ home, ".local", "bin" })
    else
        try std.fs.path.join(arena, &.{ home, ".local", "bin" });
    const path_dest = try std.fs.path.join(arena, &.{ bindir, lsp_name });
    const editor_cli = try detectEditorCli(arena, gpa, io);

    if (uninstall) {
        std.debug.print("== Uninstall ==\n", .{});
        if (pathExists(io, path_dest)) {
            if (dry_run) {
                std.debug.print("DRY-RUN delete {s}\n", .{path_dest});
            } else {
                try std.Io.Dir.deleteFileAbsolute(io, path_dest);
                std.debug.print("removed {s}\n", .{path_dest});
            }
        } else {
            std.debug.print("skip missing {s}\n", .{path_dest});
        }

        if (editor_cli) |editor| {
            if (dry_run) {
                std.debug.print("DRY-RUN {s} --uninstall-extension nurl-lang.nurl\n", .{editor});
            } else if ((try installedExtensionVersion(arena, gpa, io, editor)) != null) {
                try runMaybeDry(init, false, root_abs, &.{ editor, "--uninstall-extension", "nurl-lang.nurl" });
            } else {
                std.debug.print("skip extension uninstall; nurl-lang.nurl not present\n", .{});
            }
        } else {
            std.debug.print("skip extension uninstall; no editor CLI found\n", .{});
        }
        return;
    }

    std.debug.print("== 1/4 Compiler bootstrap ==\n", .{});
    if (force or !pathExists(io, compiler_path)) {
        try runMaybeDry(init, dry_run, root_abs, &.{ zig_bin, "build", "bootstrap" });
    } else {
        std.debug.print("build/{s} already present\n", .{compiler_name});
    }

    std.debug.print("\n== 2/4 Language Server ==\n", .{});
    if (force or !pathExists(io, lsp_path)) {
        try runMaybeDry(init, dry_run, root_abs, &.{ zig_bin, "build", "nurl-lsp" });
    } else {
        std.debug.print("build/{s} already present\n", .{lsp_name});
    }

    if (!no_path) {
        std.debug.print("\n== 3/4 PATH install ==\n", .{});
        if (dry_run) {
            std.debug.print("DRY-RUN ensure dir {s}\n", .{bindir});
        } else {
            try ensureDirPath(io, bindir);
        }
        if (builtin.os.tag == .windows) {
            if (dry_run) {
                std.debug.print("DRY-RUN copy {s} -> {s}\n", .{ lsp_path, path_dest });
            } else {
                try std.Io.Dir.copyFileAbsolute(lsp_path, path_dest, io, .{
                    .permissions = .executable_file,
                    .make_path = true,
                    .replace = true,
                });
                std.debug.print("copied {s} -> {s}\n", .{ lsp_path, path_dest });
            }
        } else {
            if (dry_run) {
                std.debug.print("DRY-RUN symlink {s} -> {s}\n", .{ path_dest, lsp_path });
            } else {
                std.Io.Dir.deleteFileAbsolute(io, path_dest) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => |e| return e,
                };
                try std.Io.Dir.symLinkAbsolute(io, lsp_path, path_dest, .{});
                std.debug.print("linked {s} -> {s}\n", .{ path_dest, lsp_path });
            }
        }

        if (pathEnvContains(init, bindir)) {
            std.debug.print("{s} is already on PATH\n", .{bindir});
        } else if (builtin.os.tag == .windows) {
            std.debug.print("{s} is not on PATH; add it with setx PATH \"%%PATH%%;{s}\"\n", .{ bindir, bindir });
        } else {
            std.debug.print("{s} is not on PATH; add: export PATH=\"$HOME/.local/bin:$PATH\"\n", .{bindir});
        }
    } else {
        std.debug.print("\n== 3/4 PATH install skipped (--no-path) ==\n", .{});
    }

    if (no_vscode) {
        std.debug.print("\n== 4/4 VS Code extension skipped (--no-vscode) ==\n", .{});
        return;
    }

    std.debug.print("\n== 4/4 VS Code extension ==\n", .{});
    const editor = editor_cli orelse {
        std.debug.print("skip extension install; no editor CLI found\n", .{});
        return;
    };
    if (!try commandAvailable(gpa, io, "npx", &.{"--version"})) {
        std.debug.print("skip extension install; npx not found\n", .{});
        return;
    }

    const package_json_path = try std.fs.path.join(arena, &.{ root_abs, "tooling", "vscode-nurl", "package.json" });
    const package_json = try std.Io.Dir.cwd().readFileAlloc(io, package_json_path, gpa, .unlimited);
    defer gpa.free(package_json);
    const version = extractJsonStringField(package_json, "version") orelse {
        std.debug.print("nurl-build: failed to parse version from {s}\n", .{package_json_path});
        return error.InvalidData;
    };
    const vsix_name = try std.fmt.allocPrint(arena, "nurl-{s}.vsix", .{version});
    const vscode_dir = try std.fs.path.join(arena, &.{ root_abs, "tooling", "vscode-nurl" });
    const vsix_path = try std.fs.path.join(arena, &.{ vscode_dir, vsix_name });
    const node_modules_path = try std.fs.path.join(arena, &.{ vscode_dir, "node_modules" });

    if (force or !pathExists(io, vsix_path)) {
        if (!pathExists(io, node_modules_path)) {
            if (try commandAvailable(gpa, io, "npm", &.{"--version"})) {
                try runMaybeDry(init, dry_run, vscode_dir, &.{ "npm", "install", "--silent" });
            } else {
                std.debug.print("skip VSIX packaging; npm not found and node_modules missing\n", .{});
                return;
            }
        }
        try runMaybeDry(init, dry_run, vscode_dir, &.{ "npx", "--yes", "vsce", "package", "-o", vsix_name });
    } else {
        std.debug.print("{s} already present\n", .{vsix_path});
    }

    const installed = if (dry_run) null else try installedExtensionVersion(arena, gpa, io, editor);
    if (!force and installed != null and std.mem.eql(u8, installed.?, version)) {
        std.debug.print("{s} already has nurl-lang.nurl@{s}\n", .{ editor, version });
        return;
    }
    try runMaybeDry(init, dry_run, root_abs, &.{ editor, "--install-extension", vsix_path, "--force" });
}

fn printInstallUsage() void {
    std.debug.print(
        "usage: nurl-build install [--root <path>] [--no-vscode] [--no-path] [--force] [--uninstall] [--dry-run]\n",
        .{},
    );
}

fn resolveHomeDir(init: std.process.Init) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (init.environ_map.get("USERPROFILE")) |home| return home;
    }
    if (init.environ_map.get("HOME")) |home| return home;
    return error.EnvironmentVariableMissing;
}

fn runMaybeDry(init: std.process.Init, dry_run: bool, cwd: []const u8, argv: []const []const u8) !void {
    if (dry_run) {
        std.debug.print("DRY-RUN", .{});
        if (cwd.len != 0) std.debug.print(" [cwd={s}]", .{cwd});
        for (argv) |arg| std.debug.print(" {s}", .{arg});
        std.debug.print("\n", .{});
        return;
    }
    try runInheritedInCwd(init, cwd, argv);
}

fn runInheritedInCwd(init: std.process.Init, cwd: []const u8, argv: []const []const u8) !void {
    var child = std.process.spawn(init.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
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

fn commandAvailable(gpa: std.mem.Allocator, io: std.Io, name: []const u8, probe_args: []const []const u8) !bool {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, name);
    try argv.appendSlice(gpa, probe_args);

    const result = std.process.run(gpa, io, .{ .argv = argv.items }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return true;
}

fn detectEditorCli(arena: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io) !?[]const u8 {
    const candidates = [_][]const u8{ "code", "cursor", "windsurf" };
    for (candidates) |candidate| {
        if (try commandAvailable(gpa, io, candidate, &.{"--version"})) {
            const dup = try arena.dupe(u8, candidate);
            return dup;
        }
    }
    return null;
}

fn installedExtensionVersion(arena: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io, editor: []const u8) !?[]const u8 {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ editor, "--list-extensions", "--show-versions" },
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "nurl-lang.nurl@")) {
            const dup = try arena.dupe(u8, trimmed["nurl-lang.nurl@".len..]);
            return dup;
        }
    }
    return null;
}

fn extractJsonStringField(source: []const u8, key: []const u8) ?[]const u8 {
    const needle = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\"", .{key}) catch return null;
    defer std.heap.page_allocator.free(needle);
    const start = std.mem.indexOf(u8, source, needle) orelse return null;
    const after_key = source[start + needle.len ..];
    const colon = std.mem.indexOfScalar(u8, after_key, ':') orelse return null;
    const after_colon = std.mem.trim(u8, after_key[colon + 1 ..], " \t\r\n");
    if (after_colon.len < 2 or after_colon[0] != '"') return null;
    const rest = after_colon[1..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end];
}

fn pathEnvContains(init: std.process.Init, target: []const u8) bool {
    const path_env = init.environ_map.get("PATH") orelse return false;
    const separator: u8 = if (builtin.os.tag == .windows) ';' else ':';
    var it = std.mem.splitScalar(u8, path_env, separator);
    while (it.next()) |entry| {
        const trimmed = std.mem.trim(u8, entry, " \t");
        if (trimmed.len == 0) continue;
        if (builtin.os.tag == .windows) {
            if (std.ascii.eqlIgnoreCase(trimmed, target)) return true;
        } else if (std.mem.eql(u8, trimmed, target)) {
            return true;
        }
    }
    return false;
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
    const gpa = init.gpa;
    const io = init.io;

    var child_argv = try buildLinkArgv(init, args);
    defer child_argv.deinit(gpa);

    var child = std.process.spawn(io, .{
        .argv = child_argv.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("nurl-build: C driver not found: {s}\n", .{child_argv.items[0]});
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

fn runLinkCapture(init: std.process.Init, args: []const []const u8) !std.process.RunResult {
    const gpa = init.gpa;
    const io = init.io;

    var child_argv = try buildLinkArgv(init, args);
    defer child_argv.deinit(gpa);

    return std.process.run(gpa, io, .{
        .argv = child_argv.items,
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("nurl-build: C driver not found: {s}\n", .{child_argv.items[0]});
        }
        return err;
    };
}

fn buildLinkArgv(init: std.process.Init, args: []const []const u8) !std.ArrayList([]const u8) {
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
    return child_argv;
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

fn runApiBuild(init: std.process.Init, args: []const []const u8) !void {
    const payload = try executeApiBuild(init, args);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout_writer.flush() catch {};

    try std.json.Stringify.value(payload, .{}, stdout);
    try stdout.writeByte('\n');
}

fn runApiBuildWasm(init: std.process.Init, args: []const []const u8) !void {
    const payload = try executeApiBuildWasm(init, args);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout_writer.flush() catch {};

    try std.json.Stringify.value(payload, .{}, stdout);
    try stdout.writeByte('\n');
}

fn runApiRuntimeObjs(init: std.process.Init, args: []const []const u8) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var root: []const u8 = ".";
    var zig_bin: []const u8 = init.environ_map.get("NURL_ZIG") orelse "zig";
    var curl_prefix: []const u8 = init.environ_map.get("NURL_MINGW_CURL_PREFIX") orelse "/opt/curl-mingw";
    var wasm_target: []const u8 = init.environ_map.get("NURL_WASM_TARGET") orelse "wasm32-wasi";
    var windows_target: []const u8 = init.environ_map.get("NURL_WINDOWS_TARGET") orelse "x86_64-windows-gnu";
    var macos_target: []const u8 = init.environ_map.get("NURL_MACOS_TARGET") orelse "x86_64-macos-none";
    var skip_wasm = false;
    var skip_windows = false;
    var skip_macos = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--zig")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            zig_bin = args[i];
        } else if (std.mem.eql(u8, arg, "--curl-prefix")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            curl_prefix = args[i];
        } else if (std.mem.eql(u8, arg, "--wasm-target")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            wasm_target = args[i];
        } else if (std.mem.eql(u8, arg, "--windows-target")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            windows_target = args[i];
        } else if (std.mem.eql(u8, arg, "--macos-target")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            macos_target = args[i];
        } else if (std.mem.eql(u8, arg, "--skip-wasm")) {
            skip_wasm = true;
        } else if (std.mem.eql(u8, arg, "--skip-windows")) {
            skip_windows = true;
        } else if (std.mem.eql(u8, arg, "--skip-macos")) {
            skip_macos = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                "usage: nurl-build api-runtime-objs [--root <path>] [--zig <path>] [--curl-prefix <path>] [--wasm-target <triple>] [--windows-target <triple>] [--macos-target <triple>] [--skip-wasm] [--skip-windows] [--skip-macos]\n",
                .{},
            );
            std.process.exit(0);
        } else {
            std.debug.print("nurl-build: unknown api-runtime-objs arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
    }

    if (i != args.len) return error.InvalidArgs;

    const root_abs = try absolutePath(arena, root);
    try ensureExists(io, root_abs, "repo root");

    const runtime_c = try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.c" });
    try ensureExists(io, runtime_c, "stdlib/runtime.c");

    if (!skip_wasm) {
        std.debug.print("[wasm] compiling runtime.wasm.o, canvas.wasm.o, audio.wasm.o\n", .{});
        try runInheritedInCwd(init, root_abs, &.{ zig_bin, "cc", "-target", wasm_target, "-O2", "-c", "stdlib/runtime.c", "-o", "stdlib/runtime.wasm.o" });
        try runInheritedInCwd(init, root_abs, &.{ zig_bin, "cc", "-target", wasm_target, "-O2", "-c", "stdlib/canvas_wasm.c", "-o", "stdlib/canvas.wasm.o" });
        try runInheritedInCwd(init, root_abs, &.{ zig_bin, "cc", "-target", wasm_target, "-O2", "-c", "stdlib/audio_wasm.c", "-o", "stdlib/audio.wasm.o" });
    }

    if (!skip_windows) {
        const curl_include = try std.fmt.allocPrint(arena, "-I{s}/include", .{curl_prefix});
        std.debug.print("[windows] compiling runtime.win.o\n", .{});
        try runInheritedInCwd(init, root_abs, &.{
            zig_bin,
            "cc",
            "-target",
            windows_target,
            "-O2",
            "-DNURL_HAVE_LIBCURL",
            "-DCURL_STATICLIB",
            curl_include,
            "-c",
            "stdlib/runtime.c",
            "-o",
            "stdlib/runtime.win.o",
        });
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = try std.fs.path.join(arena, &.{ root_abs, "stdlib", "runtime.win.curl" }),
            .data = "1\n",
        });
    }

    if (!skip_macos) {
        std.debug.print("[macos] compiling runtime.mac.o\n", .{});
        try runInheritedInCwd(init, root_abs, &.{ zig_bin, "cc", "-target", macos_target, "-O2", "-c", "stdlib/runtime.c", "-o", "stdlib/runtime.mac.o" });
    }
}

fn executeApiBuildWasm(init: std.process.Init, args: []const []const u8) !ApiBuildWasmPayload {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const cfg = try parseApiBuildWasmArgs(arena, args);
    try ensureExists(io, cfg.src_path, "source file");
    try ensureExists(io, cfg.runtime, "runtime object");
    try ensureDirPath(io, cfg.build_dir);

    const basename = try sanitizeBasename(gpa, cfg.filename orelse cfg.src_path);
    const raw_ll_name = try std.fmt.allocPrint(gpa, "{s}.raw.ll", .{basename});
    const ll_name = try std.fmt.allocPrint(gpa, "{s}.ll", .{basename});
    const wasm_name = try std.fmt.allocPrint(gpa, "{s}.wasm", .{basename});
    const async_name = try std.fmt.allocPrint(gpa, "{s}.async.wasm", .{basename});
    const raw_ll_path = try std.fs.path.join(gpa, &.{ cfg.build_dir, raw_ll_name });
    const ll_path = try std.fs.path.join(gpa, &.{ cfg.build_dir, ll_name });
    const wasm_path = try std.fs.path.join(gpa, &.{ cfg.build_dir, wasm_name });
    const async_wasm_path = try std.fs.path.join(gpa, &.{ cfg.build_dir, async_name });

    const nurlc_path = try resolveNurlc(init, cfg.root);
    try ensureExists(io, nurlc_path, "nurlc");

    const nurlc_result = try std.process.run(gpa, io, .{
        .argv = &.{ nurlc_path, cfg.src_path },
        .cwd = .{ .path = cfg.root },
    });
    const nurlc_stderr = std.mem.trimEnd(u8, nurlc_result.stderr, "\r\n");
    const nurlc_rc = runResultExitCode(nurlc_result.term);
    if (nurlc_rc != 0 or nurlc_result.stdout.len == 0) {
        return .{
            .http_status = 422,
            .error_stage = "nurlc",
            .error_returncode = nurlc_rc,
            .error_stderr = nurlc_stderr,
            .error_nurlc_stderr = nurlc_stderr,
            .status = "error",
            .message = "nurlc failed",
            .filename = cfg.filename,
            .uses_canvas = false,
            .uses_audio = false,
            .nurlc_stderr = nurlc_stderr,
            .clang_stderr = null,
            .raw_ll_path = null,
            .prepared_ll_path = null,
            .wasm_path = null,
        };
    }

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = raw_ll_path,
        .data = nurlc_result.stdout,
    });

    const prepared_ir = prepareIrForWasi(gpa, nurlc_result.stdout) catch {
        return .{
            .http_status = 422,
            .error_message = "failed to rewrite LLVM IR for wasm32-wasi",
            .status = "error",
            .message = "ir rewrite failed",
            .filename = cfg.filename,
            .uses_canvas = false,
            .uses_audio = false,
            .nurlc_stderr = nurlc_stderr,
            .clang_stderr = null,
            .raw_ll_path = raw_ll_path,
            .prepared_ll_path = null,
            .wasm_path = null,
        };
    };

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = ll_path,
        .data = prepared_ir,
    });

    const uses_canvas = containsAny(prepared_ir, &.{
        "@canvas_open",
        "@canvas_present",
        "@canvas_sleep",
        "@canvas_should_close",
        "@canvas_close",
        "@canvas_mouse_x",
        "@canvas_mouse_y",
        "@canvas_mouse_btn",
    });
    const uses_audio = containsAny(prepared_ir, &.{
        "@audio_level",
        "@audio_bin",
        "@audio_bin_count",
        "@audio_peak_bin",
        "@audio_centroid",
        "@audio_freq_of",
        "@audio_sample_rate",
        "@audio_is_silent",
        "@audio_ready",
    });

    if (uses_canvas and !pathExists(io, cfg.canvas_obj)) {
        return .{
            .http_status = 500,
            .error_message = try std.fmt.allocPrint(gpa, "canvas FFI used but {s} not present. Rebuild the container with canvas_wasm.c compiled.", .{cfg.canvas_obj}),
            .status = "fatal",
            .message = "canvas runtime unavailable",
            .filename = cfg.filename,
            .uses_canvas = true,
            .uses_audio = uses_audio,
            .nurlc_stderr = nurlc_stderr,
            .clang_stderr = null,
            .raw_ll_path = raw_ll_path,
            .prepared_ll_path = ll_path,
            .wasm_path = null,
        };
    }
    if (uses_audio and !pathExists(io, cfg.audio_obj)) {
        return .{
            .http_status = 500,
            .error_message = try std.fmt.allocPrint(gpa, "audio FFI used but {s} not present. Rebuild the container with audio_wasm.c compiled.", .{cfg.audio_obj}),
            .status = "fatal",
            .message = "audio runtime unavailable",
            .filename = cfg.filename,
            .uses_canvas = uses_canvas,
            .uses_audio = true,
            .nurlc_stderr = nurlc_stderr,
            .clang_stderr = null,
            .raw_ll_path = raw_ll_path,
            .prepared_ll_path = ll_path,
            .wasm_path = null,
        };
    }

    var link_args: std.ArrayList([]const u8) = .empty;
    defer link_args.deinit(gpa);
    try link_args.appendSlice(gpa, &.{
        "--driver",
        cfg.zig_driver,
        "--target",
        cfg.target,
        "--opt",
        "-O2",
        "--runtime",
        cfg.runtime,
        "--no-lto",
        "--no-marker-libs",
        "--flag",
        "-Wno-override-module",
    });
    if (uses_canvas) try link_args.appendSlice(gpa, &.{ "--extra-obj", cfg.canvas_obj });
    if (uses_audio) try link_args.appendSlice(gpa, &.{ "--extra-obj", cfg.audio_obj });
    if (uses_canvas or uses_audio) {
        try link_args.appendSlice(gpa, &.{ "--flag", "-Wl,--allow-undefined" });
    }
    try link_args.appendSlice(gpa, &.{ "--extra-lib", "-lm", cfg.root, ll_path, wasm_path });

    const link_result = try runLinkCapture(init, link_args.items);
    const link_stderr = std.mem.trimEnd(u8, link_result.stderr, "\r\n");
    const link_rc = runResultExitCode(link_result.term);
    if (link_rc != 0 or !pathExists(io, wasm_path)) {
        return .{
            .http_status = 422,
            .error_stage = "nurl-build-wasm",
            .error_returncode = link_rc,
            .error_stderr = link_stderr,
            .error_nurlc_stderr = nurlc_stderr,
            .status = "error",
            .message = "wasm link failed",
            .filename = cfg.filename,
            .uses_canvas = uses_canvas,
            .uses_audio = uses_audio,
            .nurlc_stderr = nurlc_stderr,
            .clang_stderr = link_stderr,
            .raw_ll_path = raw_ll_path,
            .prepared_ll_path = ll_path,
            .wasm_path = null,
        };
    }

    var final_wasm_path = wasm_path;
    var final_clang_stderr = link_stderr;

    if (uses_canvas) {
        const opt_result = std.process.run(gpa, io, .{
            .argv = &.{
                cfg.wasm_opt,
                "--asyncify",
                "--pass-arg=asyncify-imports@canvas.sleep",
                "-O2",
                wasm_path,
                "-o",
                async_wasm_path,
            },
        }) catch |err| switch (err) {
            error.FileNotFound => {
                return .{
                    .http_status = 500,
                    .error_message = try std.fmt.allocPrint(gpa, "wasm-opt not found at '{s}'. Canvas programs require binaryen.", .{cfg.wasm_opt}),
                    .status = "fatal",
                    .message = "wasm-opt unavailable",
                    .filename = cfg.filename,
                    .uses_canvas = true,
                    .uses_audio = uses_audio,
                    .nurlc_stderr = nurlc_stderr,
                    .clang_stderr = link_stderr,
                    .raw_ll_path = raw_ll_path,
                    .prepared_ll_path = ll_path,
                    .wasm_path = wasm_path,
                };
            },
            else => |e| return e,
        };
        const opt_stderr = std.mem.trimEnd(u8, opt_result.stderr, "\r\n");
        const opt_rc = runResultExitCode(opt_result.term);
        if (opt_rc != 0 or !pathExists(io, async_wasm_path)) {
            return .{
                .http_status = 422,
                .error_stage = "wasm-opt asyncify",
                .error_returncode = opt_rc,
                .error_stderr = opt_stderr,
                .status = "error",
                .message = "wasm asyncify failed",
                .filename = cfg.filename,
                .uses_canvas = true,
                .uses_audio = uses_audio,
                .nurlc_stderr = nurlc_stderr,
                .clang_stderr = joinNonEmpty(gpa, &.{ link_stderr, opt_stderr }) catch link_stderr,
                .raw_ll_path = raw_ll_path,
                .prepared_ll_path = ll_path,
                .wasm_path = wasm_path,
            };
        }
        final_wasm_path = async_wasm_path;
        final_clang_stderr = joinNonEmpty(gpa, &.{ link_stderr, opt_stderr }) catch link_stderr;
    }

    return .{
        .status = "ok",
        .message = try std.fmt.allocPrint(
            gpa,
            "compiled nurl → wasm32-wasi{s}{s}",
            .{
                if (uses_canvas) " (asyncified for canvas)" else "",
                if (uses_audio) " [+audio]" else "",
            },
        ),
        .filename = cfg.filename,
        .uses_canvas = uses_canvas,
        .uses_audio = uses_audio,
        .nurlc_stderr = if (nurlc_stderr.len == 0) null else nurlc_stderr,
        .clang_stderr = if (final_clang_stderr.len == 0) null else final_clang_stderr,
        .raw_ll_path = raw_ll_path,
        .prepared_ll_path = ll_path,
        .wasm_path = final_wasm_path,
    };
}

fn parseApiBuildWasmArgs(arena: std.mem.Allocator, args: []const []const u8) !ApiBuildWasmConfig {
    var root: ?[]const u8 = null;
    var src_path: ?[]const u8 = null;
    var build_dir: ?[]const u8 = null;
    var filename: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var runtime: ?[]const u8 = null;
    var canvas_obj: ?[]const u8 = null;
    var audio_obj: ?[]const u8 = null;
    var zig_driver: ?[]const u8 = null;
    var wasm_opt: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--src")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            src_path = args[i];
        } else if (std.mem.eql(u8, arg, "--build-dir")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            build_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--filename")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            filename = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            target = args[i];
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            runtime = args[i];
        } else if (std.mem.eql(u8, arg, "--canvas-obj")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            canvas_obj = args[i];
        } else if (std.mem.eql(u8, arg, "--audio-obj")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            audio_obj = args[i];
        } else if (std.mem.eql(u8, arg, "--zig-driver")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            zig_driver = args[i];
        } else if (std.mem.eql(u8, arg, "--wasm-opt")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            wasm_opt = args[i];
        } else {
            std.debug.print("nurl-build: unknown api-build-wasm arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
    }

    if (root == null or src_path == null or build_dir == null or target == null or runtime == null or canvas_obj == null or audio_obj == null or zig_driver == null or wasm_opt == null) {
        std.debug.print(
            "usage: nurl-build api-build-wasm --root <path> --src <path> --build-dir <path> --target <triple> --runtime <path> --canvas-obj <path> --audio-obj <path> --zig-driver <cmd> --wasm-opt <path> [--filename <name>]\n",
            .{},
        );
        return error.InvalidArgs;
    }

    return .{
        .root = try absolutePath(arena, root.?),
        .src_path = try absolutePath(arena, src_path.?),
        .build_dir = try absolutePath(arena, build_dir.?),
        .filename = filename,
        .target = target.?,
        .runtime = try absolutePath(arena, runtime.?),
        .canvas_obj = try absolutePath(arena, canvas_obj.?),
        .audio_obj = try absolutePath(arena, audio_obj.?),
        .zig_driver = zig_driver.?,
        .wasm_opt = wasm_opt.?,
    };
}

fn executeApiBuild(init: std.process.Init, args: []const []const u8) !ApiBuildPayload {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const cfg = try parseApiBuildArgs(arena, args);
    try ensureExists(io, cfg.src_path, "source file");
    try ensureExists(io, cfg.runtime, "runtime object");
    try ensureDirPath(io, cfg.build_dir);

    const basename = try sanitizeBasename(gpa, cfg.filename orelse cfg.src_path);
    const ll_name = try std.fmt.allocPrint(gpa, "{s}.ll", .{basename});
    const bin_name = switch (cfg.kind) {
        .native, .macos => basename,
        .windows => try std.fmt.allocPrint(gpa, "{s}.exe", .{basename}),
    };
    const ll_path = try std.fs.path.join(gpa, &.{ cfg.build_dir, ll_name });
    const bin_path = try std.fs.path.join(gpa, &.{ cfg.build_dir, bin_name });

    const nurlc_path = try resolveNurlc(init, cfg.root);
    try ensureExists(io, nurlc_path, "nurlc");

    const nurlc_cwd = if (pathExists(io, cfg.root))
        cfg.root
    else
        std.fs.path.dirname(cfg.src_path) orelse ".";

    const nurlc_result = try std.process.run(gpa, io, .{
        .argv = &.{ nurlc_path, cfg.src_path },
        .cwd = .{ .path = nurlc_cwd },
    });

    const nurlc_stderr = std.mem.trimEnd(u8, nurlc_result.stderr, "\r\n");
    const nurlc_stdout_bytes = nurlc_result.stdout.len;
    const nurlc_rc = runResultExitCode(nurlc_result.term);

    var stdout_log: std.Io.Writer.Allocating = .init(gpa);
    var stderr_log: std.Io.Writer.Allocating = .init(gpa);
    try appendPrefixedLog(&stderr_log, "nurlc", nurlc_stderr);

    if (nurlc_rc != 0 or nurlc_result.stdout.len == 0) {
        return .{
            .status = "error",
            .message = "nurlc failed",
            .filename = cfg.filename,
            .uses_canvas = false,
            .uses_audio = false,
            .nurlc_returncode = nurlc_rc,
            .nurlc_stdout_bytes = nurlc_stdout_bytes,
            .nurlc_stderr = nurlc_stderr,
            .clang_returncode = null,
            .clang_stdout = null,
            .clang_stderr = null,
            .stdout = "",
            .stderr = stderr_log.written(),
            .ll_path = null,
            .binary_path = null,
        };
    }

    if (!containsMainDefinition(nurlc_result.stdout)) {
        try appendPrefixedLog(
            &stderr_log,
            "nurl",
            switch (cfg.kind) {
                .native => "nurlc produced IR without an `@main` definition. NURL's entry point is `@ main → i { ... }` — not `fn main() -> i { ... }`. See /examples for working sources.",
                .windows, .macos => "nurlc produced IR without an `@main` definition. NURL's entry point is `@ main → i { ... }`.",
            },
        );
        return .{
            .status = "error",
            .message = "no @main in generated IR",
            .filename = cfg.filename,
            .uses_canvas = false,
            .uses_audio = false,
            .nurlc_returncode = nurlc_rc,
            .nurlc_stdout_bytes = nurlc_stdout_bytes,
            .nurlc_stderr = nurlc_stderr,
            .clang_returncode = null,
            .clang_stdout = null,
            .clang_stderr = null,
            .stdout = "",
            .stderr = stderr_log.written(),
            .ll_path = null,
            .binary_path = null,
        };
    }

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = ll_path,
        .data = nurlc_result.stdout,
    });

    const uses_canvas = containsAny(nurlc_result.stdout, &.{
        "@canvas_open",
        "@canvas_present",
        "@canvas_sleep",
        "@canvas_should_close",
        "@canvas_close",
        "@canvas_mouse_x",
        "@canvas_mouse_y",
        "@canvas_mouse_btn",
    });
    const uses_audio = containsAny(nurlc_result.stdout, &.{
        "@audio_level",
        "@audio_bin",
        "@audio_bin_count",
        "@audio_peak_bin",
        "@audio_centroid",
        "@audio_freq_of",
        "@audio_sample_rate",
        "@audio_is_silent",
        "@audio_ready",
    });

    switch (cfg.kind) {
        .native => {
            if (uses_canvas) {
                const canvas_obj = cfg.canvas_obj orelse {
                    return .{
                        .http_status = 500,
                        .fatal_detail = "canvas FFI used but no canvas object was configured for api-build",
                        .status = "fatal",
                        .message = "canvas runtime unavailable",
                        .filename = cfg.filename,
                        .uses_canvas = true,
                        .uses_audio = uses_audio,
                        .nurlc_returncode = nurlc_rc,
                        .nurlc_stdout_bytes = nurlc_stdout_bytes,
                        .nurlc_stderr = nurlc_stderr,
                        .clang_returncode = null,
                        .clang_stdout = null,
                        .clang_stderr = null,
                        .stdout = stdout_log.written(),
                        .stderr = stderr_log.written(),
                        .ll_path = null,
                        .binary_path = null,
                    };
                };
                if (!pathExists(io, canvas_obj)) {
                    return .{
                        .http_status = 500,
                        .fatal_detail = try std.fmt.allocPrint(gpa, "canvas FFI used but {s} not present. Rebuild the container with canvas.c compiled.", .{canvas_obj}),
                        .status = "fatal",
                        .message = "canvas runtime unavailable",
                        .filename = cfg.filename,
                        .uses_canvas = true,
                        .uses_audio = uses_audio,
                        .nurlc_returncode = nurlc_rc,
                        .nurlc_stdout_bytes = nurlc_stdout_bytes,
                        .nurlc_stderr = nurlc_stderr,
                        .clang_returncode = null,
                        .clang_stdout = null,
                        .clang_stderr = null,
                        .stdout = stdout_log.written(),
                        .stderr = stderr_log.written(),
                        .ll_path = null,
                        .binary_path = null,
                    };
                }
            }
        },
        .windows, .macos => {
            if (uses_canvas or uses_audio) {
                const target_name = switch (cfg.kind) {
                    .windows => "Windows",
                    .macos => "macOS",
                    .native => unreachable,
                };
                var unsupported: std.Io.Writer.Allocating = .init(gpa);
                defer unsupported.deinit();
                if (uses_canvas) try unsupported.writer.writeAll("canvas");
                if (uses_audio) {
                    if (uses_canvas) try unsupported.writer.writeAll(", ");
                    try unsupported.writer.writeAll("audio");
                }
                return .{
                    .http_status = 400,
                    .fatal_detail = try std.fmt.allocPrint(gpa, "{s} build does not support FFI: {s}. Use Build WASM for canvas/audio programs.", .{ target_name, unsupported.written() }),
                    .status = "fatal",
                    .message = "unsupported ffi",
                    .filename = cfg.filename,
                    .uses_canvas = false,
                    .uses_audio = uses_audio,
                    .nurlc_returncode = nurlc_rc,
                    .nurlc_stdout_bytes = nurlc_stdout_bytes,
                    .nurlc_stderr = nurlc_stderr,
                    .clang_returncode = null,
                    .clang_stdout = null,
                    .clang_stderr = null,
                    .stdout = stdout_log.written(),
                    .stderr = stderr_log.written(),
                    .ll_path = null,
                    .binary_path = null,
                };
            }
        },
    }

    var link_args: std.ArrayList([]const u8) = .empty;
    defer link_args.deinit(gpa);
    try link_args.appendSlice(gpa, &.{
        "--opt",
        cfg.opt,
        "--runtime",
        cfg.runtime,
        "--no-lto",
        "--flag",
        "-Wno-override-module",
        "--driver",
        cfg.driver,
    });
    if (cfg.target) |target| {
        try link_args.appendSlice(gpa, &.{ "--target", target });
    }
    if (cfg.kind == .native and uses_canvas) {
        try link_args.appendSlice(gpa, &.{ "--extra-obj", cfg.canvas_obj.? });
        if (cfg.canvas_sdl2_marker) |marker| {
            if (pathExists(io, marker)) {
                try link_args.appendSlice(gpa, &.{ "--extra-lib", "-lSDL2" });
            }
        }
    }
    if (cfg.kind == .windows) {
        const runtime_dir = std.fs.path.dirname(cfg.runtime) orelse ".";
        const win_curl_marker = try std.fs.path.join(gpa, &.{ runtime_dir, "runtime.win.curl" });
        if (pathExists(io, win_curl_marker)) {
            const mingw_prefix = init.environ_map.get("NURL_MINGW_CURL_PREFIX") orelse "/opt/curl-mingw";
            try link_args.appendSlice(gpa, &.{
                "--extra-lib", try std.fmt.allocPrint(gpa, "-L{s}/lib", .{mingw_prefix}),
                "--extra-lib", "-lcurl",
                "--extra-lib", "-lws2_32",
                "--extra-lib", "-lcrypt32",
                "--extra-lib", "-lbcrypt",
                "--extra-lib", "-lncrypt",
                "--extra-lib", "-lsecur32",
                "--extra-lib", "-ladvapi32",
            });
        }
    }
    try link_args.appendSlice(gpa, &.{ cfg.root, ll_path, bin_path });

    const link_result = try runLinkCapture(init, link_args.items);

    const clang_stdout = std.mem.trimEnd(u8, link_result.stdout, "\r\n");
    const clang_stderr = std.mem.trimEnd(u8, link_result.stderr, "\r\n");
    const link_label = switch (cfg.kind) {
        .native => "link",
        .windows, .macos => "zig cc",
    };
    try appendPrefixedLog(&stdout_log, link_label, clang_stdout);
    try appendPrefixedLog(&stderr_log, link_label, clang_stderr);

    const clang_rc = runResultExitCode(link_result.term);
    const binary_exists = pathExists(io, bin_path);
    const ok = clang_rc == 0 and binary_exists;

    return .{
        .status = if (ok) "ok" else "error",
        .message = switch (cfg.kind) {
            .native => if (ok) "compiled nurl → native binary" else "build failed (see stderr)",
            .windows => if (ok) "compiled nurl → Windows .exe (zig cc)" else "windows build failed (see stderr)",
            .macos => if (ok) try std.fmt.allocPrint(gpa, "compiled nurl → macOS Mach-O ({s})", .{cfg.target orelse "unknown-target"}) else "macos build failed (see stderr)",
        },
        .filename = cfg.filename,
        .uses_canvas = uses_canvas and cfg.kind == .native,
        .uses_audio = uses_audio,
        .nurlc_returncode = nurlc_rc,
        .nurlc_stdout_bytes = nurlc_stdout_bytes,
        .nurlc_stderr = nurlc_stderr,
        .clang_returncode = clang_rc,
        .clang_stdout = if (clang_stdout.len == 0) null else clang_stdout,
        .clang_stderr = if (clang_stderr.len == 0) null else clang_stderr,
        .stdout = stdout_log.written(),
        .stderr = stderr_log.written(),
        .ll_path = ll_path,
        .binary_path = if (binary_exists) bin_path else null,
    };
}

fn parseApiBuildArgs(arena: std.mem.Allocator, args: []const []const u8) !ApiBuildConfig {
    var kind: ?ApiBuildKind = null;
    var root: ?[]const u8 = null;
    var src_path: ?[]const u8 = null;
    var build_dir: ?[]const u8 = null;
    var filename: ?[]const u8 = null;
    var opt: []const u8 = "-O2";
    var driver: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var runtime: ?[]const u8 = null;
    var canvas_obj: ?[]const u8 = null;
    var canvas_sdl2_marker: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--kind")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            kind = std.meta.stringToEnum(ApiBuildKind, args[i]) orelse return error.InvalidArgs;
        } else if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            root = args[i];
        } else if (std.mem.eql(u8, arg, "--src")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            src_path = args[i];
        } else if (std.mem.eql(u8, arg, "--build-dir")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            build_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--filename")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            filename = args[i];
        } else if (std.mem.eql(u8, arg, "--opt")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            opt = args[i];
        } else if (std.mem.eql(u8, arg, "--driver")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            driver = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            target = args[i];
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            runtime = args[i];
        } else if (std.mem.eql(u8, arg, "--canvas-obj")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            canvas_obj = args[i];
        } else if (std.mem.eql(u8, arg, "--canvas-sdl2-marker")) {
            i += 1;
            if (i >= args.len) return error.InvalidArgs;
            canvas_sdl2_marker = args[i];
        } else {
            std.debug.print("nurl-build: unknown api-build arg: {s}\n", .{arg});
            return error.InvalidArgs;
        }
    }

    if (kind == null or root == null or src_path == null or build_dir == null or driver == null or runtime == null) {
        std.debug.print(
            "usage: nurl-build api-build --kind <native|windows|macos> --root <path> --src <path> --build-dir <path> --driver <cmd> --runtime <path> [--filename <name>] [--opt <-O2>] [--target <triple>] [--canvas-obj <path>] [--canvas-sdl2-marker <path>]\n",
            .{},
        );
        return error.InvalidArgs;
    }

    return .{
        .kind = kind.?,
        .root = try absolutePath(arena, root.?),
        .src_path = try absolutePath(arena, src_path.?),
        .build_dir = try absolutePath(arena, build_dir.?),
        .filename = filename,
        .opt = opt,
        .driver = driver.?,
        .target = target,
        .runtime = try absolutePath(arena, runtime.?),
        .canvas_obj = if (canvas_obj) |path| try absolutePath(arena, path) else null,
        .canvas_sdl2_marker = if (canvas_sdl2_marker) |path| try absolutePath(arena, path) else null,
    };
}

fn sanitizeBasename(gpa: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const base = std.fs.path.basename(raw);
    const ext = std.fs.path.extension(base);
    const stem = if (ext.len != 0) base[0 .. base.len - ext.len] else base;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (stem) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-') {
            try out.append(gpa, c);
        }
    }
    if (out.items.len == 0) {
        return try gpa.dupe(u8, "main");
    }
    return try gpa.dupe(u8, out.items);
}

fn appendPrefixedLog(block: *std.Io.Writer.Allocating, prefix: []const u8, content: []const u8) !void {
    if (content.len == 0) return;
    if (block.written().len != 0) try block.writer.writeByte('\n');
    try block.writer.print("[{s}] {s}", .{ prefix, content });
}

fn containsMainDefinition(ir: []const u8) bool {
    return std.mem.indexOf(u8, ir, "define i32 @main(") != null or
        std.mem.indexOf(u8, ir, "define  i32 @main(") != null or
        std.mem.indexOf(u8, ir, "\ndefine i32 @main(") != null or
        std.mem.indexOf(u8, ir, "\ndefine  i32 @main(") != null;
}

fn runResultExitCode(term: std.process.Child.Term) i32 {
    return switch (term) {
        .exited => |code| @intCast(code),
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => |status| @intCast(status),
    };
}

fn joinNonEmpty(gpa: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    for (parts) |part| {
        if (part.len == 0) continue;
        if (out.written().len != 0) try out.writer.writeByte('\n');
        try out.writer.writeAll(part);
    }
    return out.written();
}

fn prepareIrForWasi(gpa: std.mem.Allocator, ir_bytes: []const u8) ![]u8 {
    var text = try gpa.dupe(u8, ir_bytes);
    text = try renameMainForWasi(gpa, text);

    var masked = try maskLlvmCStrings(gpa, text);
    defer masked.saved.deinit(gpa);

    var shims: std.ArrayList([]const u8) = .empty;
    defer shims.deinit(gpa);

    var rewritten = masked.text;
    for (wasm_abi_entries) |entry| {
        if (std.mem.indexOf(u8, rewritten, try std.fmt.allocPrint(gpa, "@{s}", .{entry.name})) == null) {
            continue;
        }
        if (!wasmNeedsShim(entry)) continue;

        rewritten = try stripDeclareLine(gpa, rewritten, entry.name);
        rewritten = try rewriteCallLikeUses(gpa, rewritten, entry.name);
        try shims.append(gpa, try emitWasmShim(gpa, entry));
    }

    var unmasked = try unmaskLlvmCStrings(gpa, rewritten, masked.saved.items);
    if (shims.items.len != 0) {
        var extra: std.Io.Writer.Allocating = .init(gpa);
        try extra.writer.writeAll(unmasked);
        try extra.writer.writeAll("\n; -- wasm32 libc ABI shims --\n");
        for (shims.items) |shim| try extra.writer.writeAll(shim);
        unmasked = extra.written();
    }

    return try insertWasmTargetTriple(gpa, unmasked);
}

const MaskedCStrings = struct {
    text: []u8,
    saved: std.ArrayList([]const u8),
};

fn maskLlvmCStrings(gpa: std.mem.Allocator, text: []const u8) !MaskedCStrings {
    var out: std.Io.Writer.Allocating = .init(gpa);
    var saved: std.ArrayList([]const u8) = .empty;

    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 'c' and i + 1 < text.len and text[i + 1] == '"') {
            var j = i + 2;
            while (j < text.len) {
                if (text[j] == '\\' and j + 1 < text.len) {
                    j += 2;
                    continue;
                }
                if (text[j] == '"') {
                    j += 1;
                    break;
                }
                j += 1;
            }
            const literal = try gpa.dupe(u8, text[i..@min(j, text.len)]);
            try saved.append(gpa, literal);
            try out.writer.print("\x00CSTR{d}\x00", .{saved.items.len - 1});
            i = @min(j, text.len);
            continue;
        }
        try out.writer.writeByte(text[i]);
        i += 1;
    }

    return .{
        .text = out.written(),
        .saved = saved,
    };
}

fn unmaskLlvmCStrings(gpa: std.mem.Allocator, text: []const u8, saved: []const []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0 and std.mem.startsWith(u8, text[i..], "\x00CSTR")) {
            var j = i + 5;
            var idx: usize = 0;
            while (j < text.len and text[j] >= '0' and text[j] <= '9') : (j += 1) {
                idx = idx * 10 + (text[j] - '0');
            }
            if (j < text.len and text[j] == 0 and idx < saved.len) {
                try out.writer.writeAll(saved[idx]);
                i = j + 1;
                continue;
            }
        }
        try out.writer.writeByte(text[i]);
        i += 1;
    }
    return out.written();
}

fn renameMainForWasi(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    var replaced = false;

    var line_start: usize = 0;
    while (line_start < text.len) {
        const maybe_nl = std.mem.indexOfScalarPos(u8, text, line_start, '\n');
        const line_end = maybe_nl orelse text.len;
        const line = text[line_start..line_end];

        if (!replaced and isMainDefLine(line)) {
            const main_idx = std.mem.indexOf(u8, line, "@main") orelse unreachable;
            try out.writer.writeAll(line[0..main_idx]);
            try out.writer.writeAll("@__main_argc_argv");
            try out.writer.writeAll(line[main_idx + "@main".len ..]);
            replaced = true;
        } else {
            try out.writer.writeAll(line);
        }

        if (maybe_nl != null) try out.writer.writeByte('\n');
        line_start = if (maybe_nl) |idx| idx + 1 else text.len;
    }

    return out.written();
}

fn isMainDefLine(line: []const u8) bool {
    var i: usize = 0;
    while (i < line.len and isSpaceByte(line[i])) : (i += 1) {}
    if (!std.mem.startsWith(u8, line[i..], "define")) return false;
    const main_idx = std.mem.indexOf(u8, line, "@main") orelse return false;
    var j = main_idx + "@main".len;
    while (j < line.len and isSpaceByte(line[j])) : (j += 1) {}
    return j < line.len and line[j] == '(';
}

fn stripDeclareLine(gpa: std.mem.Allocator, text: []const u8, name: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    var removed = false;
    const needle = try std.fmt.allocPrint(gpa, "@{s}", .{name});

    var line_start: usize = 0;
    while (line_start < text.len) {
        const maybe_nl = std.mem.indexOfScalarPos(u8, text, line_start, '\n');
        const line_end = maybe_nl orelse text.len;
        const line = text[line_start..line_end];

        var skip = false;
        if (!removed) {
            var i: usize = 0;
            while (i < line.len and isSpaceByte(line[i])) : (i += 1) {}
            if (std.mem.startsWith(u8, line[i..], "declare") and std.mem.indexOf(u8, line, needle) != null) {
                const idx = std.mem.indexOf(u8, line, needle).?;
                var j = idx + needle.len;
                while (j < line.len and isSpaceByte(line[j])) : (j += 1) {}
                if (j < line.len and line[j] == '(') {
                    skip = true;
                    removed = true;
                }
            }
        }

        if (!skip) {
            try out.writer.writeAll(line);
            if (maybe_nl != null) try out.writer.writeByte('\n');
        }

        line_start = if (maybe_nl) |idx| idx + 1 else text.len;
    }
    return out.written();
}

fn rewriteCallLikeUses(gpa: std.mem.Allocator, text: []const u8, name: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const needle = try std.fmt.allocPrint(gpa, "@{s}", .{name});
    const replacement = try std.fmt.allocPrint(gpa, "@__nurl_{s}_shim", .{name});

    var i: usize = 0;
    while (i < text.len) {
        if (i + needle.len <= text.len and std.mem.eql(u8, text[i .. i + needle.len], needle)) {
            var j = i + needle.len;
            while (j < text.len and isSpaceByte(text[j])) : (j += 1) {}
            if (j < text.len and text[j] == '(') {
                try out.writer.writeAll(replacement);
                i += needle.len;
                continue;
            }
        }
        try out.writer.writeByte(text[i]);
        i += 1;
    }
    return out.written();
}

fn emitWasmShim(gpa: std.mem.Allocator, entry: WasmAbiEntry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);

    try out.writer.print("declare {s} @{s}(", .{ realTy(entry.ret), entry.name });
    for (entry.params, 0..) |param, idx| {
        if (idx != 0) try out.writer.writeAll(", ");
        try out.writer.writeAll(realTy(param));
    }
    try out.writer.writeAll(")\n\n");

    try out.writer.print("define internal {s} @__nurl_{s}_shim(", .{ nurlTy(entry.ret), entry.name });
    for (entry.params, 0..) |param, idx| {
        if (idx != 0) try out.writer.writeAll(", ");
        try out.writer.print("{s} %a{d}", .{ nurlTy(param), idx });
    }
    try out.writer.writeAll(") {\n");

    var first_call_arg = true;
    for (entry.params, 0..) |param, idx| {
        const nt = nurlTy(param);
        const rt = realTy(param);
        if (!std.mem.eql(u8, nt, rt)) {
            try out.writer.print("  %t{d} = trunc {s} %a{d} to {s}\n", .{ idx, nt, idx, rt });
        }
        if (first_call_arg) {
            first_call_arg = false;
        }
    }

    if (entry.ret == 'v') {
        try out.writer.print("  tail call {s} @{s}(", .{ realTy(entry.ret), entry.name });
    } else {
        try out.writer.print("  %r = tail call {s} @{s}(", .{ realTy(entry.ret), entry.name });
    }
    for (entry.params, 0..) |param, idx| {
        if (idx != 0) try out.writer.writeAll(", ");
        const nt = nurlTy(param);
        const rt = realTy(param);
        if (std.mem.eql(u8, nt, rt)) {
            try out.writer.print("{s} %a{d}", .{ rt, idx });
        } else {
            try out.writer.print("{s} %t{d}", .{ rt, idx });
        }
    }
    try out.writer.writeAll(")\n");

    if (entry.ret == 'v') {
        try out.writer.writeAll("  ret void\n");
    } else if (std.mem.eql(u8, realTy(entry.ret), nurlTy(entry.ret))) {
        try out.writer.print("  ret {s} %r\n", .{nurlTy(entry.ret)});
    } else {
        const widen_op = if (entry.ret == 's') "zext" else "sext";
        try out.writer.print("  %rw = {s} {s} %r to {s}\n", .{ widen_op, realTy(entry.ret), nurlTy(entry.ret) });
        try out.writer.print("  ret {s} %rw\n", .{nurlTy(entry.ret)});
    }

    try out.writer.writeAll("}\n\n");
    return out.written();
}

fn insertWasmTargetTriple(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, text, "target triple") != null) {
        return try gpa.dupe(u8, text);
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    var inserted = false;
    var line_start: usize = 0;
    while (line_start < text.len) {
        const maybe_nl = std.mem.indexOfScalarPos(u8, text, line_start, '\n');
        const line_end = maybe_nl orelse text.len;
        const line = text[line_start..line_end];
        if (!inserted) {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (!(trimmed.len == 0 or std.mem.startsWith(u8, trimmed, ";"))) {
                try out.writer.writeAll(wasm_target_triple);
                inserted = true;
            }
        }
        try out.writer.writeAll(line);
        if (maybe_nl != null) try out.writer.writeByte('\n');
        line_start = if (maybe_nl) |idx| idx + 1 else text.len;
    }
    if (!inserted) {
        try out.writer.writeAll(wasm_target_triple);
    }
    return out.written();
}

fn wasmNeedsShim(entry: WasmAbiEntry) bool {
    if (!std.mem.eql(u8, realTy(entry.ret), nurlTy(entry.ret))) return true;
    for (entry.params) |param| {
        if (!std.mem.eql(u8, realTy(param), nurlTy(param))) return true;
    }
    return false;
}

fn realTy(code: u8) []const u8 {
    return switch (code) {
        'i', 's' => "i32",
        'p' => "i8*",
        'v' => "void",
        else => unreachable,
    };
}

fn nurlTy(code: u8) []const u8 {
    return switch (code) {
        'i', 's' => "i64",
        'p' => "i8*",
        'v' => "void",
        else => unreachable,
    };
}

fn isSpaceByte(b: u8) bool {
    return b == ' ' or b == '\t' or b == '\r';
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
    const cwd = try std.process.currentPathAlloc(std.Io.Threaded.global_single_threaded.io(), arena);
    return std.fs.path.resolve(arena, &.{ cwd, path });
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

fn isSnapshotHelperModule(name: []const u8) bool {
    return std.mem.endsWith(u8, name, "_mod") or
        std.mem.endsWith(u8, name, "_helper") or
        std.mem.endsWith(u8, name, "_lib");
}

fn shouldSkipSnapshotTest(
    name: []const u8,
    enable_http_tests: []const u8,
    enable_net_tests: []const u8,
    has_pq_marker: bool,
) bool {
    if (std.mem.startsWith(u8, name, "http_") and
        !pathEqNormalized(name, "http_request_parser") and
        !pathEqNormalized(name, "http_response_builder") and
        !pathEqNormalized(name, "http_router") and
        !pathEqNormalized(name, "http_extras") and
        !pathEqNormalized(name, "http_middleware") and
        !pathEqNormalized(name, "http_form") and
        !pathEqNormalized(name, "http_multipart") and
        !pathEqNormalized(name, "http_proxy") and
        !pathEqNormalized(name, "http_server_seq") and
        !pathEqNormalized(name, "http_server_pipelined") and
        !pathEqNormalized(name, "http_server_limits") and
        !pathEqNormalized(name, "http_server_tls") and
        !pathEqNormalized(name, "http_server_panic") and
        !std.mem.eql(u8, enable_http_tests, "1"))
    {
        return true;
    }

    if ((pathEqNormalized(name, "http_server_seq") or
        pathEqNormalized(name, "http_server_pipelined") or
        pathEqNormalized(name, "http_server_limits") or
        pathEqNormalized(name, "http_server_tls") or
        pathEqNormalized(name, "http_server_panic")) and
        !std.mem.eql(u8, enable_net_tests, "1"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, name, "net_") and
        !pathEqNormalized(name, "net_basic") and
        !std.mem.eql(u8, enable_net_tests, "1"))
    {
        return true;
    }

    if (pathEqNormalized(name, "postgres_basic") and !has_pq_marker) return true;
    if (pathEqNormalized(name, "variadic_ffi") and builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) return true;
    return false;
}

fn stripRepoPrefixAlloc(gpa: std.mem.Allocator, bytes: []const u8, root_abs: []const u8) ![]u8 {
    const unix_prefix = try std.fmt.allocPrint(gpa, "{s}/", .{root_abs});
    defer gpa.free(unix_prefix);
    var stripped = try std.mem.replaceOwned(u8, gpa, bytes, unix_prefix, "");

    if (builtin.os.tag == .windows) {
        const windows_prefix = try std.fmt.allocPrint(gpa, "{s}\\", .{root_abs});
        defer gpa.free(windows_prefix);
        const replaced = try std.mem.replaceOwned(u8, gpa, stripped, windows_prefix, "");
        gpa.free(stripped);
        stripped = replaced;
    }

    return stripped;
}

fn appendOutputCapped(
    gpa: std.mem.Allocator,
    results: *std.ArrayList(u8),
    bytes: []const u8,
    max_output_lines: usize,
) !void {
    if (bytes.len == 0) return;

    var total_lines: usize = 0;
    for (bytes) |ch| {
        if (ch == '\n') total_lines += 1;
    }

    if (total_lines <= max_output_lines) {
        try results.appendSlice(gpa, bytes);
        return;
    }

    var seen_lines: usize = 0;
    var cutoff: usize = bytes.len;
    for (bytes, 0..) |ch, idx| {
        if (ch == '\n') {
            seen_lines += 1;
            if (seen_lines == max_output_lines) {
                cutoff = idx + 1;
                break;
            }
        }
    }

    try results.appendSlice(gpa, bytes[0..cutoff]);
    try appendSummaryLine(gpa, results, "[... {d} more lines truncated ...]\n", .{total_lines - max_output_lines});
}

fn printBaselineDiff(init: std.process.Init, baseline_path: []const u8, results_path: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;

    if (builtin.os.tag == .windows) {
        const cmd_exe = "cmd.exe";
        const result = std.process.run(gpa, io, .{
            .argv = &.{ cmd_exe, "/c", "fc", baseline_path, results_path },
        }) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("baseline: {s}\nresults : {s}\n", .{ baseline_path, results_path });
                return;
            },
            else => return err,
        };
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
        return;
    }

    const result = std.process.run(gpa, io, .{
        .argv = &.{ "diff", "-u", baseline_path, results_path },
    }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("baseline: {s}\nresults : {s}\n", .{ baseline_path, results_path });
            return;
        },
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
    if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
}

fn testBinaryPath(arena: std.mem.Allocator, workdir: []const u8, stem: []const u8) ![]const u8 {
    const name = if (builtin.os.tag == .windows)
        try std.fmt.allocPrint(arena, "{s}.exe", .{stem})
    else
        try arena.dupe(u8, stem);
    return std.fs.path.join(arena, &.{ workdir, name });
}

fn resolveSanTestDriver(init: std.process.Init) ![]const u8 {
    const gpa = init.gpa;
    const io = init.io;

    if (init.environ_map.get("CLANG")) |path| {
        if (path.len != 0) return path;
    }
    if (init.environ_map.get("NURL_CC")) |path| {
        if (path.len != 0) return path;
    }
    if (try commandAvailable(gpa, io, "clang", &.{"--version"})) return "clang";

    const fallbacks = [_][]const u8{
        "/usr/lib/llvm/bin/clang",
        "/usr/local/bin/clang",
    };
    for (fallbacks) |path| {
        if (pathExists(io, path)) return path;
    }

    std.debug.print("ERROR: clang not found\n", .{});
    return error.FileNotFound;
}

fn ensureSanitizedRuntime(init: std.process.Init, runtime_path: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;

    const result = std.process.run(gpa, io, .{
        .argv = &.{ "nm", runtime_path },
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("ERROR: nm not found\n", .{});
        }
        return err;
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    if (std.mem.indexOf(u8, result.stdout, "__asan_init") != null) return;
    if (std.mem.indexOf(u8, result.stdout, "asan_init") != null) return;

    std.debug.print("ERROR: {s} was not built with -fsanitize=address.\n", .{runtime_path});
    std.debug.print("       Run zig build -Dsan=true bootstrap to rebuild it.\n", .{});
    return error.InvalidData;
}

fn buildSanTestEnv(init: std.process.Init) !std.process.Environ.Map {
    const arena = init.arena.allocator();
    const gpa = init.gpa;

    var env_map = try init.environ_map.clone(gpa);
    if (env_map.get("ASAN_OPTIONS") == null) {
        const detect_leaks = init.environ_map.get("LSAN_DETECT_LEAKS") orelse "0";
        const asan_options = try std.fmt.allocPrint(
            arena,
            "detect_leaks={s}:abort_on_error=0:halt_on_error=0:print_stacktrace=1",
            .{detect_leaks},
        );
        try env_map.put("ASAN_OPTIONS", asan_options);
    }
    if (env_map.get("UBSAN_OPTIONS") == null) {
        try env_map.put("UBSAN_OPTIONS", "print_stacktrace=1:halt_on_error=0");
    }
    return env_map;
}

fn isSanSkipName(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "should_fail_") != null or
        std.mem.indexOf(u8, name, "nurlfmt_idempotent") != null or
        std.mem.indexOf(u8, name, "alias_rewrite_types_mod") != null;
}

fn appendSummaryLine(
    gpa: std.mem.Allocator,
    summary: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const line = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(line);
    try summary.appendSlice(gpa, line);
}

fn containsAll(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) == null) return false;
    }
    return true;
}

fn containsSanitizerMarker(stderr_bytes: []const u8) bool {
    return std.mem.indexOf(u8, stderr_bytes, "AddressSanitizer") != null or
        std.mem.indexOf(u8, stderr_bytes, "UndefinedBehaviorSanitizer") != null or
        std.mem.indexOf(u8, stderr_bytes, "runtime error:") != null or
        std.mem.indexOf(u8, stderr_bytes, "LeakSanitizer") != null;
}

fn childExitCodeOr(term: std.process.Child.Term, fallback: u8) u8 {
    return switch (term) {
        .exited => |code| code,
        else => fallback,
    };
}

fn printFirstLines(bytes: []const u8, max_lines: usize) void {
    var it = std.mem.splitScalar(u8, bytes, '\n');
    var lines: usize = 0;
    while (it.next()) |line| {
        if (lines >= max_lines) break;
        std.debug.print("{s}\n", .{line});
        lines += 1;
    }
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

fn firstAvailableCommand(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    candidates: []const []const u8,
    probe_args: []const []const u8,
) !?[]const u8 {
    for (candidates) |candidate| {
        if (try commandAvailable(gpa, io, candidate, probe_args)) {
            const dup: []const u8 = try arena.dupe(u8, candidate);
            return dup;
        }
    }
    return null;
}

fn compileDwarfFixture(
    init: std.process.Init,
    root_abs: []const u8,
    src_path: []const u8,
    out_path: []const u8,
) !void {
    try runUserCompile(init, .{
        .root = root_abs,
        .srcfile = src_path,
        .outbase = out_path,
        .emit_ir = false,
        .emit_asm = false,
        .debug_info = true,
        .opt = "-O0",
    }, .native);
}

fn verifyDwarfDebugInfo(init: std.process.Init, bin_path: []const u8) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    if (try firstAvailableCommand(arena, gpa, io, &.{ "readelf", "llvm-readelf" }, &.{"--version"})) |reader| {
        const result = try std.process.run(gpa, io, .{
            .argv = &.{ reader, "-S", bin_path },
        });
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        if (!runResultSucceeded(result.term)) {
            if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
            if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
            return dwarfFail("failed to inspect binary sections");
        }
        if (std.mem.indexOf(u8, result.stdout, ".debug_info") == null) {
            return dwarfFail("binary has no .debug_info section");
        }
        return;
    }

    if (try firstAvailableCommand(arena, gpa, io, &.{ "dwarfdump", "llvm-dwarfdump" }, &.{"--help"})) |dwarfdump| {
        const result = try std.process.run(gpa, io, .{
            .argv = &.{ dwarfdump, "--debug-info", bin_path },
        });
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        if (!runResultSucceeded(result.term)) {
            if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
            if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
            return dwarfFail("dwarfdump could not read debug info");
        }
        if (std.mem.indexOf(u8, result.stdout, "DW_TAG_compile_unit") == null and
            std.mem.indexOf(u8, result.stdout, "Compile Unit") == null)
        {
            return dwarfFail("debug info dump did not contain a compile unit");
        }
        return;
    }

    return dwarfFail("no readelf/dwarfdump tool available to verify debug info");
}

fn runCombinedCapture(
    init: std.process.Init,
    argv: []const []const u8,
    cwd: ?[]const u8,
) ![]u8 {
    const gpa = init.gpa;
    const io = init.io;
    const child_cwd: std.process.Child.Cwd = if (cwd) |path| .{ .path = path } else .inherit;
    const result = try std.process.run(gpa, io, .{
        .argv = argv,
        .cwd = child_cwd,
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    if (!runResultSucceeded(result.term)) {
        if (result.stdout.len != 0) std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
        std.debug.print("FAIL: command failed\n", .{});
        return error.TestFailed;
    }
    return std.mem.concat(gpa, u8, &.{ result.stdout, result.stderr });
}

fn dwarfFail(message: []const u8) !void {
    std.debug.print("FAIL: {s}\n", .{message});
    return error.TestFailed;
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
