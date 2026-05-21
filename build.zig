const std = @import("std");

const FeatureState = struct {
    enabled: bool,
    cflags: []const []const u8,
};

const RuntimeConfig = struct {
    python: []const u8,
    env_exe: []const u8,
    root_path: []const u8,
    san: bool,
    use_lto: bool,
    curl: FeatureState,
    openssl: FeatureState,
    sqlite3: FeatureState,
    zlib: FeatureState,
    pq_enabled: bool,
    zstd_enabled: bool,
    sdl2_include: ?[]const u8,
    cc_tokens: []const []const u8,
};

const py_mkdir =
    \\import os, sys
    \\os.makedirs(sys.argv[1], exist_ok=True)
;

const py_copy_file =
    \\import shutil, sys
    \\shutil.copyfile(sys.argv[1], sys.argv[2])
;

const py_copy_exec =
    \\import os, shutil, sys
    \\shutil.copyfile(sys.argv[1], sys.argv[2])
    \\os.chmod(sys.argv[2], 0o755)
;

const py_symlink =
    \\from pathlib import Path
    \\import os, sys
    \\src = Path(sys.argv[1])
    \\dest = Path(sys.argv[2])
    \\target = os.path.relpath(src, dest.parent)
    \\try:
    \\    dest.unlink(missing_ok=True)
    \\except IsADirectoryError:
    \\    raise SystemExit(f"{dest} is a directory; refusing to replace it")
    \\try:
    \\    dest.symlink_to(target)
    \\except FileExistsError:
    \\    dest.unlink(missing_ok=True)
    \\    dest.symlink_to(target)
;

const py_marker_on =
    \\from pathlib import Path
    \\import sys
    \\Path(sys.argv[1]).write_text("1\n")
;

const py_marker_off =
    \\from pathlib import Path
    \\import sys
    \\Path(sys.argv[1]).unlink(missing_ok=True)
;

const py_compare_files =
    \\from pathlib import Path
    \\import sys
    \\lhs = Path(sys.argv[1]).read_bytes()
    \\rhs = Path(sys.argv[2]).read_bytes()
    \\if lhs != rhs:
    \\    print("Fixed point NOT reached - nurlc_self and nurlc_self2 differ.", file=sys.stderr)
    \\    sys.exit(1)
;

pub fn build(b: *std.Build) !void {
    const san = b.option(bool, "san", "Build the compiler/runtime with AddressSanitizer + UBSan") orelse false;
    const cfg = detectRuntimeConfig(b, san);
    const nurl_build_exe = b.addExecutable(.{
        .name = "nurl-build",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/nurl-build/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    const ensure_build_dir = addPythonStep(b, cfg.python, py_mkdir, &.{"build"}, true);
    const helper_copy = addPythonCopyLazyStep(b, cfg.python, nurl_build_exe.getEmittedBin(), "build/nurl-build", true);
    helper_copy.step.dependOn(&ensure_build_dir.step);
    helper_copy.step.dependOn(&nurl_build_exe.step);
    const sync_runtime_nolto = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.nolto", !cfg.use_lto);
    const sync_runtime_curl = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.curl", cfg.curl.enabled);
    const sync_runtime_openssl = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.openssl", cfg.openssl.enabled);
    const sync_runtime_sqlite3 = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.sqlite3", cfg.sqlite3.enabled);
    const sync_runtime_pq = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.pq", cfg.pq_enabled);
    const sync_runtime_z = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.z", cfg.zlib.enabled);
    const sync_runtime_zstd = addMarkerSyncStep(b, cfg.python, "stdlib/runtime.zstd", cfg.zstd_enabled);
    const sync_canvas_sdl2 = addMarkerSyncStep(b, cfg.python, "stdlib/canvas.sdl2", cfg.sdl2_include != null);

    const runtime_cmd = addCcCommand(b, cfg.cc_tokens);
    runtime_cmd.setCwd(b.path("."));
    runtime_cmd.has_side_effects = true;
    runtime_cmd.step.dependOn(&sync_runtime_nolto.step);
    runtime_cmd.step.dependOn(&sync_runtime_curl.step);
    runtime_cmd.step.dependOn(&sync_runtime_openssl.step);
    runtime_cmd.step.dependOn(&sync_runtime_sqlite3.step);
    runtime_cmd.step.dependOn(&sync_runtime_pq.step);
    runtime_cmd.step.dependOn(&sync_runtime_z.step);
    runtime_cmd.step.dependOn(&sync_runtime_zstd.step);
    runtime_cmd.addArg("-O2");
    if (cfg.use_lto) runtime_cmd.addArg("-flto");
    if (cfg.san) runtime_cmd.addArgs(&.{
        "-fsanitize=address,undefined",
        "-fsanitize-address-use-after-scope",
        "-fno-omit-frame-pointer",
        "-fno-sanitize-recover=all",
    });
    runtime_cmd.addArgs(cfg.curl.cflags);
    runtime_cmd.addArgs(cfg.openssl.cflags);
    runtime_cmd.addArgs(cfg.sqlite3.cflags);
    runtime_cmd.addArgs(cfg.zlib.cflags);
    runtime_cmd.addArgs(&.{ "-c", "stdlib/runtime.c", "-o", "stdlib/runtime.o" });

    const runtime_native_cmd = if (cfg.use_lto) blk: {
        const cmd = addCcCommand(b, cfg.cc_tokens);
        cmd.setCwd(b.path("."));
        cmd.has_side_effects = true;
        cmd.step.dependOn(&runtime_cmd.step);
        cmd.addArgs(&.{ "-O2", "-c", "-x", "ir", "stdlib/runtime.o", "-o", "stdlib/runtime.native.o" });
        break :blk cmd;
    } else blk: {
        const cmd = addPythonCopyStep(b, cfg.python, "stdlib/runtime.o", "stdlib/runtime.native.o", false);
        cmd.step.dependOn(&runtime_cmd.step);
        break :blk cmd;
    };

    const canvas_cmd = addCcCommand(b, cfg.cc_tokens);
    canvas_cmd.setCwd(b.path("."));
    canvas_cmd.has_side_effects = true;
    canvas_cmd.step.dependOn(&sync_canvas_sdl2.step);
    canvas_cmd.addArgs(&.{ "-c", "stdlib/canvas.c" });
    if (cfg.sdl2_include) |include_dir| {
        canvas_cmd.addArg("-DNURL_HAVE_SDL2");
        canvas_cmd.addArg(b.fmt("-I{s}", .{include_dir}));
    }
    canvas_cmd.addArgs(&.{ "-o", "stdlib/canvas.o" });

    const stage0_ir = b.addSystemCommand(&.{ cfg.python, "compiler/nurlc.py", "--llvm", "compiler/nurlc.nu" });
    stage0_ir.setCwd(b.path("."));
    const stage0_ll = stage0_ir.captureStdOut(.{ .basename = "nurlc_py.ll" });
    const stage0_ll_copy = addPythonCopyLazyStep(b, cfg.python, stage0_ll, "build/nurlc_py.ll", false);
    stage0_ll_copy.step.dependOn(&ensure_build_dir.step);
    stage0_ll_copy.step.dependOn(&stage0_ir.step);

    const stage0_link = addLinkStep(b, cfg, nurl_build_exe, stage0_ll, "build/nurlc_py", .{});
    stage0_link.step.dependOn(&ensure_build_dir.step);
    stage0_link.step.dependOn(&runtime_cmd.step);
    stage0_link.step.dependOn(&stage0_ir.step);

    const stage1_ir = b.addSystemCommand(&.{ cfg.env_exe, "./build/nurlc_py", "compiler/nurlc.nu" });
    stage1_ir.setCwd(b.path("."));
    stage1_ir.step.dependOn(&stage0_link.step);
    applySanBuildEnv(stage1_ir, cfg.san);
    const stage1_ll = stage1_ir.captureStdOut(.{ .basename = "nurlc_self.ll" });
    const stage1_ll_copy = addPythonCopyLazyStep(b, cfg.python, stage1_ll, "build/nurlc_self.ll", false);
    stage1_ll_copy.step.dependOn(&ensure_build_dir.step);
    stage1_ll_copy.step.dependOn(&stage1_ir.step);

    const stage1_link = addLinkStep(b, cfg, nurl_build_exe, stage1_ll, "build/nurlc_self", .{});
    stage1_link.step.dependOn(&ensure_build_dir.step);
    stage1_link.step.dependOn(&runtime_cmd.step);
    stage1_link.step.dependOn(&stage1_ir.step);

    const stage2_ir = b.addSystemCommand(&.{ cfg.env_exe, "./build/nurlc_self", "compiler/nurlc.nu" });
    stage2_ir.setCwd(b.path("."));
    stage2_ir.step.dependOn(&stage1_link.step);
    applySanBuildEnv(stage2_ir, cfg.san);
    const stage2_ll = stage2_ir.captureStdOut(.{ .basename = "nurlc_self2.ll" });
    const stage2_ll_copy = addPythonCopyLazyStep(b, cfg.python, stage2_ll, "build/nurlc_self2.ll", false);
    stage2_ll_copy.step.dependOn(&ensure_build_dir.step);
    stage2_ll_copy.step.dependOn(&stage2_ir.step);

    const stage2_link = addLinkStep(b, cfg, nurl_build_exe, stage2_ll, "build/nurlc_self2", .{});
    stage2_link.step.dependOn(&ensure_build_dir.step);
    stage2_link.step.dependOn(&runtime_cmd.step);
    stage2_link.step.dependOn(&stage2_ir.step);

    const fixed_point = b.addSystemCommand(&.{ cfg.python, "-c", py_compare_files });
    fixed_point.setCwd(b.path("."));
    fixed_point.step.dependOn(&stage1_ir.step);
    fixed_point.step.dependOn(&stage2_ir.step);
    fixed_point.addFileArg(stage1_ll);
    fixed_point.addFileArg(stage2_ll);

    const final_compiler_copy = addPythonCopyStep(b, cfg.python, "build/nurlc_self2", "build/nurlc", true);
    final_compiler_copy.step.dependOn(&stage2_link.step);
    final_compiler_copy.step.dependOn(&fixed_point.step);

    const root_compiler_copy = addPythonSymlinkStep(b, cfg.python, "build/nurlc", "nurlc");
    root_compiler_copy.step.dependOn(&final_compiler_copy.step);

    const bootstrap_step = b.step("bootstrap", "Build the runtime and self-hosted compiler");
    bootstrap_step.dependOn(&helper_copy.step);
    bootstrap_step.dependOn(&runtime_native_cmd.step);
    bootstrap_step.dependOn(&canvas_cmd.step);
    bootstrap_step.dependOn(&stage0_ll_copy.step);
    bootstrap_step.dependOn(&stage1_ll_copy.step);
    bootstrap_step.dependOn(&stage2_ll_copy.step);
    bootstrap_step.dependOn(&root_compiler_copy.step);

    const helper_step = b.step("nurl-build", "Build build/nurl-build");
    helper_step.dependOn(&helper_copy.step);

    const nurlfmt_link = addToolBuildStep(
        b,
        cfg,
        nurl_build_exe,
        &root_compiler_copy.step,
        &ensure_build_dir.step,
        &runtime_cmd.step,
        "tools/nurlfmt/nurlfmt.nu",
        "build/nurlfmt.ll",
        "build/nurlfmt",
        "nurlfmt.ll",
    );
    const nurlpkg_link = addToolBuildStep(
        b,
        cfg,
        nurl_build_exe,
        &root_compiler_copy.step,
        &ensure_build_dir.step,
        &runtime_cmd.step,
        "tools/nurlpkg/main.nu",
        "build/nurlpkg.ll",
        "build/nurlpkg",
        "nurlpkg.ll",
    );
    const nurllsp_link = addToolBuildStep(
        b,
        cfg,
        nurl_build_exe,
        &root_compiler_copy.step,
        &ensure_build_dir.step,
        &runtime_cmd.step,
        "tools/nurl-lsp/main.nu",
        "build/nurl-lsp.ll",
        "build/nurl-lsp",
        "nurl-lsp.ll",
    );

    const fmt_step = b.step("nurlfmt", "Build build/nurlfmt");
    fmt_step.dependOn(&nurlfmt_link.step);

    const pkg_step = b.step("nurlpkg", "Build build/nurlpkg");
    pkg_step.dependOn(&nurlpkg_link.step);

    const lsp_step = b.step("nurl-lsp", "Build build/nurl-lsp");
    lsp_step.dependOn(&nurllsp_link.step);

    const tools_step = b.step("tools", "Build nurlfmt, nurlpkg, and nurl-lsp");
    tools_step.dependOn(&helper_copy.step);
    tools_step.dependOn(&nurlfmt_link.step);
    tools_step.dependOn(&nurlpkg_link.step);
    tools_step.dependOn(&nurllsp_link.step);

    b.getInstallStep().dependOn(tools_step);

    const tests = b.addSystemCommand(&.{ b.path("compiler/tests/run_tests.sh").getPath(b) });
    tests.setCwd(b.path("."));
    tests.has_side_effects = true;
    tests.step.dependOn(tools_step);

    const update_lastgood = addPythonCopyStep(b, cfg.python, "compiler/nurlc.nu", "compiler/nurlc_lastgood.nu", false);
    update_lastgood.step.dependOn(&tests.step);

    const check_step = b.step("check", "Bootstrap the project, build tools, and run compiler/tests/run_tests.sh");
    check_step.dependOn(&update_lastgood.step);

    const san_tests = b.addSystemCommand(&.{ b.path("compiler/tests/run_san_tests.sh").getPath(b) });
    san_tests.setCwd(b.path("."));
    san_tests.has_side_effects = true;
    san_tests.step.dependOn(tools_step);
    const san_test_step = b.step("san-test", "Run compiler/tests/run_san_tests.sh after a sanitized build (-Dsan=true)");
    san_test_step.dependOn(&san_tests.step);
}

fn detectRuntimeConfig(b: *std.Build, san: bool) RuntimeConfig {
    const python = resolvePython(b);
    const env_exe = resolveProgram(b, null, &.{ "env" }, &.{ "/usr/bin", "/bin" });
    const root_path = b.build_root.path orelse ".";
    const cc_tokens = resolveCcTokens(b);
    const host_is_macos = b.graph.host.result.os.tag == .macos;
    const use_lto = !san and !isNativeMacZigCc(cc_tokens, host_is_macos);

    return .{
        .python = python,
        .env_exe = env_exe,
        .root_path = root_path,
        .san = san,
        .use_lto = use_lto,
        .curl = detectCompileFeature(b, "libcurl", "-DNURL_HAVE_LIBCURL"),
        .openssl = detectCompileFeature(b, "openssl", "-DNURL_HAVE_OPENSSL"),
        .sqlite3 = detectCompileFeature(b, "sqlite3", "-DNURL_HAVE_SQLITE3"),
        .zlib = detectCompileFeature(b, "zlib", "-DNURL_HAVE_ZLIB"),
        .pq_enabled = pkgConfigExists(b, "libpq"),
        .zstd_enabled = pkgConfigExists(b, "libzstd"),
        .sdl2_include = detectSdl2Include(b),
        .cc_tokens = cc_tokens,
    };
}

fn resolvePython(b: *std.Build) []const u8 {
    return resolveProgram(b, b.graph.environ_map.get("PYTHON"), &.{ "python3", "python" }, &.{});
}

fn resolveProgram(
    b: *std.Build,
    explicit: ?[]const u8,
    defaults: []const []const u8,
    extra_paths: []const []const u8,
) []const u8 {
    if (explicit) |value| {
        return b.findProgram(&.{value}, extra_paths) catch fail("required program not found: {s}", .{value});
    }
    return b.findProgram(defaults, extra_paths) catch fail("required program not found: {s}", .{defaults[0]});
}

fn resolveCcTokens(b: *std.Build) []const []const u8 {
    const raw = b.graph.environ_map.get("NURL_CC") orelse b.graph.environ_map.get("CLANG") orelse "clang";
    const parts = splitWhitespaceDup(b.allocator, raw);
    const driver = if (parts.len == 0) "clang" else parts[0];
    const resolved = b.findProgram(&.{driver}, &.{ "/usr/lib/llvm/bin", "/usr/local/bin" }) catch fail("C driver not found: {s}", .{driver});

    var out: std.ArrayList([]const u8) = .empty;
    out.append(b.allocator, resolved) catch @panic("OOM");
    for (parts[1..]) |part| {
        out.append(b.allocator, part) catch @panic("OOM");
    }
    return out.toOwnedSlice(b.allocator) catch @panic("OOM");
}

fn splitWhitespaceDup(allocator: std.mem.Allocator, text: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (it.next()) |part| {
        out.append(allocator, allocator.dupe(u8, part) catch @panic("OOM")) catch @panic("OOM");
    }
    return out.toOwnedSlice(allocator) catch @panic("OOM");
}

fn isNativeMacZigCc(cc_tokens: []const []const u8, host_is_macos: bool) bool {
    if (!host_is_macos) return false;
    if (cc_tokens.len < 2) return false;
    return std.mem.eql(u8, std.fs.path.basename(cc_tokens[0]), "zig") and std.mem.eql(u8, cc_tokens[1], "cc");
}

fn detectCompileFeature(b: *std.Build, pkg: []const u8, define_flag: []const u8) FeatureState {
    if (!pkgConfigExists(b, pkg)) return .{ .enabled = false, .cflags = &.{} };

    const pkg_cflags = pkgConfigTokens(b, &.{ "--cflags", pkg });
    var all: std.ArrayList([]const u8) = .empty;
    all.append(b.allocator, define_flag) catch @panic("OOM");
    for (pkg_cflags) |arg| {
        all.append(b.allocator, arg) catch @panic("OOM");
    }
    return .{
        .enabled = true,
        .cflags = all.toOwnedSlice(b.allocator) catch @panic("OOM"),
    };
}

fn pkgConfigExists(b: *std.Build, pkg: []const u8) bool {
    var code: u8 = 0;
    _ = b.runAllowFail(&.{ "pkg-config", "--exists", pkg }, &code, .ignore) catch |err| switch (err) {
        error.FileNotFound, error.ExitCodeFailure, error.ProcessTerminated => return false,
        else => fail("pkg-config probe failed for {s}: {t}", .{ pkg, err }),
    };
    return true;
}

fn pkgConfigTokens(b: *std.Build, argv_tail: []const []const u8) []const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    argv.append(b.allocator, "pkg-config") catch @panic("OOM");
    for (argv_tail) |arg| {
        argv.append(b.allocator, arg) catch @panic("OOM");
    }
    const output = b.run(argv.items);
    return splitWhitespaceDup(b.allocator, std.mem.trim(u8, output, " \t\r\n"));
}

fn detectSdl2Include(b: *std.Build) ?[]const u8 {
    const builtin_header = "/usr/include/SDL2/SDL.h";
    const io = std.Io.Threaded.global_single_threaded.io();
    if (std.Io.Dir.accessAbsolute(io, builtin_header, .{})) |_| {
        return "/usr/include";
    } else |_| {}

    if (!pkgConfigExists(b, "sdl2")) return null;

    const includes = pkgConfigTokens(b, &.{ "--cflags-only-I", "sdl2" });
    if (includes.len == 0) return null;
    var include_dir = includes[0];
    if (!std.mem.startsWith(u8, include_dir, "-I")) return null;
    include_dir = include_dir[2..];
    if (std.mem.endsWith(u8, include_dir, "/SDL2")) {
        include_dir = include_dir[0 .. include_dir.len - "/SDL2".len];
    }
    return b.allocator.dupe(u8, include_dir) catch @panic("OOM");
}

fn addCcCommand(b: *std.Build, cc_tokens: []const []const u8) *std.Build.Step.Run {
    const cmd = b.addSystemCommand(cc_tokens);
    return cmd;
}

fn addPythonStep(
    b: *std.Build,
    python: []const u8,
    script: []const u8,
    args: []const []const u8,
    side_effects: bool,
) *std.Build.Step.Run {
    const cmd = b.addSystemCommand(&.{ python, "-c", script });
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = side_effects;
    cmd.addArgs(args);
    return cmd;
}

fn addMarkerSyncStep(
    b: *std.Build,
    python: []const u8,
    path: []const u8,
    enabled: bool,
) *std.Build.Step.Run {
    return addPythonStep(b, python, if (enabled) py_marker_on else py_marker_off, &.{path}, true);
}

fn addPythonCopyStep(
    b: *std.Build,
    python: []const u8,
    src: []const u8,
    dest: []const u8,
    executable: bool,
) *std.Build.Step.Run {
    return addPythonStep(b, python, if (executable) py_copy_exec else py_copy_file, &.{ src, dest }, true);
}

fn addPythonSymlinkStep(
    b: *std.Build,
    python: []const u8,
    src: []const u8,
    dest: []const u8,
) *std.Build.Step.Run {
    return addPythonStep(b, python, py_symlink, &.{ src, dest }, true);
}

fn addPythonCopyLazyStep(
    b: *std.Build,
    python: []const u8,
    src: std.Build.LazyPath,
    dest: []const u8,
    executable: bool,
) *std.Build.Step.Run {
    const cmd = b.addSystemCommand(&.{ python, "-c", if (executable) py_copy_exec else py_copy_file });
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = true;
    cmd.addFileArg(src);
    cmd.addArg(dest);
    return cmd;
}

fn addLinkStep(
    b: *std.Build,
    cfg: RuntimeConfig,
    helper_exe: *std.Build.Step.Compile,
    llvm_ir: std.Build.LazyPath,
    output_path: []const u8,
    opts: struct {
        extra_obj: ?[]const u8 = null,
        extra_libs: []const []const u8 = &.{},
        opt_flag: []const u8 = "-O2",
    },
) *std.Build.Step.Run {
    const cmd = b.addRunArtifact(helper_exe);
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = true;
    cmd.addArgs(&.{ "--opt", opts.opt_flag });
    if (cfg.san) {
        cmd.addArgs(&.{ "--flag", "-fsanitize=address,undefined" });
    }
    if (opts.extra_obj) |obj| {
        cmd.addArgs(&.{ "--extra-obj", obj });
    }
    for (opts.extra_libs) |lib| {
        cmd.addArgs(&.{ "--extra-lib", lib });
    }
    cmd.addArg(cfg.root_path);
    cmd.addFileArg(llvm_ir);
    cmd.addArg(output_path);
    return cmd;
}

fn addToolBuildStep(
    b: *std.Build,
    cfg: RuntimeConfig,
    helper_exe: *std.Build.Step.Compile,
    compiler_ready: *std.Build.Step,
    ensure_build_dir: *std.Build.Step,
    runtime_ready: *std.Build.Step,
    source_path: []const u8,
    ll_output_path: []const u8,
    bin_output_path: []const u8,
    ll_basename: []const u8,
) *std.Build.Step.Run {
    const ir = b.addSystemCommand(&.{ cfg.env_exe, "./build/nurlc", source_path });
    ir.setCwd(b.path("."));
    ir.step.dependOn(compiler_ready);
    applySanBuildEnv(ir, cfg.san);
    const ll = ir.captureStdOut(.{ .basename = ll_basename });

    const copy_ll = addPythonCopyLazyStep(b, cfg.python, ll, ll_output_path, false);
    copy_ll.step.dependOn(ensure_build_dir);
    copy_ll.step.dependOn(&ir.step);

    const link = addLinkStep(b, cfg, helper_exe, ll, bin_output_path, .{});
    link.step.dependOn(ensure_build_dir);
    link.step.dependOn(runtime_ready);
    link.step.dependOn(&ir.step);
    link.step.dependOn(&copy_ll.step);
    return link;
}

fn applySanBuildEnv(cmd: *std.Build.Step.Run, san: bool) void {
    if (!san) return;
    cmd.setEnvironmentVariable("NURL_SAN", "1");
    cmd.setEnvironmentVariable("ASAN_OPTIONS", "detect_leaks=0:abort_on_error=0:halt_on_error=0:print_stacktrace=1");
    cmd.setEnvironmentVariable("UBSAN_OPTIONS", "print_stacktrace=1:halt_on_error=0");
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}
