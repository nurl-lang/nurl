const std = @import("std");

const FeatureState = struct {
    enabled: bool,
    cflags: []const []const u8,
};

const RuntimeConfig = struct {
    python: []const u8,
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

pub fn build(b: *std.Build) !void {
    const san = b.option(bool, "san", "Build the compiler/runtime with AddressSanitizer + UBSan") orelse false;
    const cfg = detectRuntimeConfig(b, san);
    const host_is_windows = b.graph.host.result.os.tag == .windows;
    const helper_path = buildBinaryPath(b, "nurl-build", host_is_windows);
    const stage0_bin_path = buildBinaryPath(b, "nurlc_py", host_is_windows);
    const stage1_bin_path = buildBinaryPath(b, "nurlc_self", host_is_windows);
    const stage2_bin_path = buildBinaryPath(b, "nurlc_self2", host_is_windows);
    const final_compiler_path = buildBinaryPath(b, "nurlc", host_is_windows);
    const lastgood_runtime_path = "stdlib/runtime.lastgood.o";
    const lastgood_stage0_bin_path = buildBinaryPath(b, "nurlc_py_lastgood", host_is_windows);
    const lastgood_stage1_bin_path = buildBinaryPath(b, "nurlc_self_lastgood", host_is_windows);
    const lastgood_stage2_bin_path = buildBinaryPath(b, "nurlc_self2_lastgood", host_is_windows);
    const lastgood_compiler_path = buildBinaryPath(b, "nurlc_lastgood", host_is_windows);
    const compare_nurl_analysis_path = b.fmt("compare/nurl_analysis{s}", .{if (host_is_windows) ".exe" else ""});
    const root_compiler_path = rootBinaryPath(b, "nurlc", host_is_windows);
    const nurlfmt_path = buildBinaryPath(b, "nurlfmt", host_is_windows);
    const nurlpkg_path = buildBinaryPath(b, "nurlpkg", host_is_windows);
    const nurllsp_path = buildBinaryPath(b, "nurl-lsp", host_is_windows);
    const nurl_build_exe = b.addExecutable(.{
        .name = "nurl-build",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/nurl-build/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    const ensure_build_dir = addHelperStep(b, nurl_build_exe, &.{ "mkdir", "build" }, true);
    const helper_copy = addHelperCopyLazyStep(b, nurl_build_exe, nurl_build_exe.getEmittedBin(), helper_path, true);
    helper_copy.step.dependOn(&ensure_build_dir.step);
    helper_copy.step.dependOn(&nurl_build_exe.step);
    const sync_runtime_nolto = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.nolto", !cfg.use_lto);
    const sync_runtime_curl = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.curl", cfg.curl.enabled);
    const sync_runtime_openssl = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.openssl", cfg.openssl.enabled);
    const sync_runtime_sqlite3 = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.sqlite3", cfg.sqlite3.enabled);
    const sync_runtime_pq = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.pq", cfg.pq_enabled);
    const sync_runtime_z = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.z", cfg.zlib.enabled);
    const sync_runtime_zstd = addMarkerSyncStep(b, nurl_build_exe, "stdlib/runtime.zstd", cfg.zstd_enabled);
    const sync_canvas_sdl2 = addMarkerSyncStep(b, nurl_build_exe, "stdlib/canvas.sdl2", cfg.sdl2_include != null);

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
        const cmd = addHelperCopyStep(b, nurl_build_exe, "stdlib/runtime.o", "stdlib/runtime.native.o", false);
        cmd.step.dependOn(&runtime_cmd.step);
        break :blk cmd;
    };

    const lastgood_runtime_cmd = addCcCommand(b, cfg.cc_tokens);
    lastgood_runtime_cmd.setCwd(b.path("."));
    lastgood_runtime_cmd.has_side_effects = true;
    lastgood_runtime_cmd.step.dependOn(&sync_runtime_curl.step);
    lastgood_runtime_cmd.step.dependOn(&sync_runtime_openssl.step);
    lastgood_runtime_cmd.step.dependOn(&sync_runtime_sqlite3.step);
    lastgood_runtime_cmd.step.dependOn(&sync_runtime_pq.step);
    lastgood_runtime_cmd.step.dependOn(&sync_runtime_z.step);
    lastgood_runtime_cmd.step.dependOn(&sync_runtime_zstd.step);
    lastgood_runtime_cmd.addArg("-O2");
    if (cfg.san) lastgood_runtime_cmd.addArgs(&.{
        "-fsanitize=address,undefined",
        "-fsanitize-address-use-after-scope",
        "-fno-omit-frame-pointer",
        "-fno-sanitize-recover=all",
    });
    lastgood_runtime_cmd.addArgs(cfg.curl.cflags);
    lastgood_runtime_cmd.addArgs(cfg.openssl.cflags);
    lastgood_runtime_cmd.addArgs(cfg.sqlite3.cflags);
    lastgood_runtime_cmd.addArgs(cfg.zlib.cflags);
    lastgood_runtime_cmd.addArgs(&.{ "-c", "stdlib/runtime.c", "-o", lastgood_runtime_path });

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
    const stage0_ll_copy = addHelperCopyLazyStep(b, nurl_build_exe, stage0_ll, "build/nurlc_py.ll", false);
    stage0_ll_copy.step.dependOn(&ensure_build_dir.step);
    stage0_ll_copy.step.dependOn(&stage0_ir.step);

    const stage0_link = addLinkStep(b, cfg, nurl_build_exe, stage0_ll, stage0_bin_path, .{});
    stage0_link.step.dependOn(&ensure_build_dir.step);
    stage0_link.step.dependOn(&runtime_cmd.step);
    stage0_link.step.dependOn(&stage0_ir.step);

    const stage1_ir = b.addSystemCommand(&.{ stage0_bin_path, "compiler/nurlc.nu" });
    stage1_ir.setCwd(b.path("."));
    stage1_ir.step.dependOn(&stage0_link.step);
    applySanBuildEnv(stage1_ir, cfg.san);
    const stage1_ll = stage1_ir.captureStdOut(.{ .basename = "nurlc_self.ll" });
    const stage1_ll_copy = addHelperCopyLazyStep(b, nurl_build_exe, stage1_ll, "build/nurlc_self.ll", false);
    stage1_ll_copy.step.dependOn(&ensure_build_dir.step);
    stage1_ll_copy.step.dependOn(&stage1_ir.step);

    const stage1_link = addLinkStep(b, cfg, nurl_build_exe, stage1_ll, stage1_bin_path, .{});
    stage1_link.step.dependOn(&ensure_build_dir.step);
    stage1_link.step.dependOn(&runtime_cmd.step);
    stage1_link.step.dependOn(&stage1_ir.step);

    const stage2_ir = b.addSystemCommand(&.{ stage1_bin_path, "compiler/nurlc.nu" });
    stage2_ir.setCwd(b.path("."));
    stage2_ir.step.dependOn(&stage1_link.step);
    applySanBuildEnv(stage2_ir, cfg.san);
    const stage2_ll = stage2_ir.captureStdOut(.{ .basename = "nurlc_self2.ll" });
    const stage2_ll_copy = addHelperCopyLazyStep(b, nurl_build_exe, stage2_ll, "build/nurlc_self2.ll", false);
    stage2_ll_copy.step.dependOn(&ensure_build_dir.step);
    stage2_ll_copy.step.dependOn(&stage2_ir.step);

    const stage2_link = addLinkStep(b, cfg, nurl_build_exe, stage2_ll, stage2_bin_path, .{});
    stage2_link.step.dependOn(&ensure_build_dir.step);
    stage2_link.step.dependOn(&runtime_cmd.step);
    stage2_link.step.dependOn(&stage2_ir.step);

    const fixed_point = addHelperCompareStep(b, nurl_build_exe, stage1_ll, stage2_ll);
    fixed_point.step.dependOn(&stage1_ir.step);
    fixed_point.step.dependOn(&stage2_ir.step);

    const final_compiler_copy = addHelperCopyStep(b, nurl_build_exe, stage2_bin_path, final_compiler_path, true);
    final_compiler_copy.step.dependOn(&stage2_link.step);
    final_compiler_copy.step.dependOn(&fixed_point.step);

    const root_compiler_copy = if (host_is_windows)
        addHelperCopyStep(b, nurl_build_exe, final_compiler_path, root_compiler_path, true)
    else
        addHelperSymlinkStep(b, nurl_build_exe, final_compiler_path, root_compiler_path);
    root_compiler_copy.step.dependOn(&final_compiler_copy.step);

    const bootstrap_step = b.step("bootstrap", "Build the runtime and self-hosted compiler");
    bootstrap_step.dependOn(&helper_copy.step);
    bootstrap_step.dependOn(&runtime_native_cmd.step);
    bootstrap_step.dependOn(&canvas_cmd.step);
    bootstrap_step.dependOn(&stage0_ll_copy.step);
    bootstrap_step.dependOn(&stage1_ll_copy.step);
    bootstrap_step.dependOn(&stage2_ll_copy.step);
    bootstrap_step.dependOn(&root_compiler_copy.step);

    const helper_step = b.step("nurl-build", b.fmt("Build {s}", .{helper_path}));
    helper_step.dependOn(&helper_copy.step);

    const lastgood_stage0_ir = b.addSystemCommand(&.{ cfg.python, "compiler/nurlc.py", "--llvm", "compiler/nurlc_lastgood.nu" });
    lastgood_stage0_ir.setCwd(b.path("."));
    const lastgood_stage0_ll = lastgood_stage0_ir.captureStdOut(.{ .basename = "nurlc_py_lastgood.ll" });
    const lastgood_stage0_ll_copy = addHelperCopyLazyStep(b, nurl_build_exe, lastgood_stage0_ll, "build/nurlc_py_lastgood.ll", false);
    lastgood_stage0_ll_copy.step.dependOn(&ensure_build_dir.step);
    lastgood_stage0_ll_copy.step.dependOn(&lastgood_stage0_ir.step);

    const lastgood_stage0_link = addLinkStep(b, cfg, nurl_build_exe, lastgood_stage0_ll, lastgood_stage0_bin_path, .{
        .runtime_override = lastgood_runtime_path,
        .disable_lto = true,
    });
    lastgood_stage0_link.step.dependOn(&ensure_build_dir.step);
    lastgood_stage0_link.step.dependOn(&lastgood_runtime_cmd.step);
    lastgood_stage0_link.step.dependOn(&lastgood_stage0_ir.step);

    const lastgood_stage1_ir = b.addSystemCommand(&.{ lastgood_stage0_bin_path, "compiler/nurlc_lastgood.nu" });
    lastgood_stage1_ir.setCwd(b.path("."));
    lastgood_stage1_ir.step.dependOn(&lastgood_stage0_link.step);
    applySanBuildEnv(lastgood_stage1_ir, cfg.san);
    const lastgood_stage1_ll = lastgood_stage1_ir.captureStdOut(.{ .basename = "nurlc_self_lastgood.ll" });
    const lastgood_stage1_ll_copy = addHelperCopyLazyStep(b, nurl_build_exe, lastgood_stage1_ll, "build/nurlc_self_lastgood.ll", false);
    lastgood_stage1_ll_copy.step.dependOn(&ensure_build_dir.step);
    lastgood_stage1_ll_copy.step.dependOn(&lastgood_stage1_ir.step);

    const lastgood_stage1_link = addLinkStep(b, cfg, nurl_build_exe, lastgood_stage1_ll, lastgood_stage1_bin_path, .{
        .runtime_override = lastgood_runtime_path,
        .disable_lto = true,
    });
    lastgood_stage1_link.step.dependOn(&ensure_build_dir.step);
    lastgood_stage1_link.step.dependOn(&lastgood_runtime_cmd.step);
    lastgood_stage1_link.step.dependOn(&lastgood_stage1_ir.step);

    const lastgood_stage2_ir = b.addSystemCommand(&.{ lastgood_stage1_bin_path, "compiler/nurlc_lastgood.nu" });
    lastgood_stage2_ir.setCwd(b.path("."));
    lastgood_stage2_ir.step.dependOn(&lastgood_stage1_link.step);
    applySanBuildEnv(lastgood_stage2_ir, cfg.san);
    const lastgood_stage2_ll = lastgood_stage2_ir.captureStdOut(.{ .basename = "nurlc_self2_lastgood.ll" });
    const lastgood_stage2_ll_copy = addHelperCopyLazyStep(b, nurl_build_exe, lastgood_stage2_ll, "build/nurlc_self2_lastgood.ll", false);
    lastgood_stage2_ll_copy.step.dependOn(&ensure_build_dir.step);
    lastgood_stage2_ll_copy.step.dependOn(&lastgood_stage2_ir.step);

    const lastgood_stage2_link = addLinkStep(b, cfg, nurl_build_exe, lastgood_stage2_ll, lastgood_stage2_bin_path, .{
        .runtime_override = lastgood_runtime_path,
        .disable_lto = true,
    });
    lastgood_stage2_link.step.dependOn(&ensure_build_dir.step);
    lastgood_stage2_link.step.dependOn(&lastgood_runtime_cmd.step);
    lastgood_stage2_link.step.dependOn(&lastgood_stage2_ir.step);

    const lastgood_fixed_point = addHelperCompareStep(b, nurl_build_exe, lastgood_stage1_ll, lastgood_stage2_ll);
    lastgood_fixed_point.step.dependOn(&lastgood_stage1_ir.step);
    lastgood_fixed_point.step.dependOn(&lastgood_stage2_ir.step);

    const lastgood_compiler_copy = addHelperCopyStep(b, nurl_build_exe, lastgood_stage2_bin_path, lastgood_compiler_path, true);
    lastgood_compiler_copy.step.dependOn(&lastgood_stage2_link.step);
    lastgood_compiler_copy.step.dependOn(&lastgood_fixed_point.step);

    const lastgood_tests = addHelperStep(b, nurl_build_exe, &.{"snapshot-test"}, true);
    lastgood_tests.setEnvironmentVariable("NURLC", lastgood_compiler_path);
    lastgood_tests.setEnvironmentVariable("NURL_RUNTIME", lastgood_runtime_path);
    lastgood_tests.step.dependOn(&helper_copy.step);
    lastgood_tests.step.dependOn(&lastgood_stage0_ll_copy.step);
    lastgood_tests.step.dependOn(&lastgood_stage1_ll_copy.step);
    lastgood_tests.step.dependOn(&lastgood_stage2_ll_copy.step);
    lastgood_tests.step.dependOn(&lastgood_compiler_copy.step);

    const bootstrap_lastgood_step = b.step("bootstrap-lastgood", "Bootstrap compiler/nurlc_lastgood.nu and run tests against it");
    bootstrap_lastgood_step.dependOn(&lastgood_tests.step);

    const nurl_cmd = addHelperStep(b, nurl_build_exe, &.{"nurl"}, true);
    if (b.args) |args| {
        nurl_cmd.addArgs(args);
    }
    nurl_cmd.step.dependOn(bootstrap_step);
    const nurl_step = b.step("nurl", "Compile a .nu file to a native binary via nurl-build");
    nurl_step.dependOn(&nurl_cmd.step);

    const wasmnurl_cmd = addHelperStep(b, nurl_build_exe, &.{"wasmnurl"}, true);
    if (b.args) |args| {
        wasmnurl_cmd.addArgs(args);
    }
    wasmnurl_cmd.step.dependOn(bootstrap_step);
    const wasmnurl_step = b.step("wasmnurl", "Compile a .nu file using nurlc.wasm under wasmtime");
    wasmnurl_step.dependOn(&wasmnurl_cmd.step);

    const buildwasm_cmd = addHelperStep(b, nurl_build_exe, &.{"buildwasm"}, true);
    if (b.args) |args| {
        buildwasm_cmd.addArgs(args);
    }
    const buildwasm_step = b.step("buildwasm", "Build compiler/nurlc.nu to nurlc.wasm via the local NURL API");
    buildwasm_step.dependOn(&buildwasm_cmd.step);

    const api_runtime_objs_cmd = addHelperStep(b, nurl_build_exe, &.{"api-runtime-objs"}, true);
    api_runtime_objs_cmd.setEnvironmentVariable("NURL_ZIG", b.graph.zig_exe);
    if (b.args) |args| {
        api_runtime_objs_cmd.addArgs(args);
    }
    const api_runtime_objs_step = b.step("api-runtime-objs", "Build wasm/windows/macos runtime objects for API containers");
    api_runtime_objs_step.dependOn(&api_runtime_objs_cmd.step);

    const clean_tree_cmd = addHelperStep(b, nurl_build_exe, &.{"clean"}, true);
    const clean_tree_step = b.step("clean-tree", "Remove build artifacts, legacy IRs, and Python caches");
    clean_tree_step.dependOn(&clean_tree_cmd.step);

    const startdev_cmd = addHelperStep(b, nurl_build_exe, &.{"startdev"}, true);
    if (b.args) |args| {
        startdev_cmd.addArgs(args);
    }
    const startdev_step = b.step("startdev", "Build and run the local NURL API Docker image");
    startdev_step.dependOn(&startdev_cmd.step);

    const dockerpush_cmd = addHelperStep(b, nurl_build_exe, &.{"dockerpush"}, true);
    if (b.args) |args| {
        dockerpush_cmd.addArgs(args);
    }
    const dockerpush_step = b.step("dockerpush", "Build and push the local NURL API Docker image");
    dockerpush_step.dependOn(&dockerpush_cmd.step);

    const nurlfmt_link = addToolBuildStep(
        b,
        cfg,
        nurl_build_exe,
        &root_compiler_copy.step,
        &ensure_build_dir.step,
        &runtime_cmd.step,
        "tools/nurlfmt/nurlfmt.nu",
        "build/nurlfmt.ll",
        nurlfmt_path,
        "nurlfmt.ll",
        final_compiler_path,
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
        nurlpkg_path,
        "nurlpkg.ll",
        final_compiler_path,
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
        nurllsp_path,
        "nurl-lsp.ll",
        final_compiler_path,
    );
    const compare_nurl_analysis_link = addToolBuildStep(
        b,
        cfg,
        nurl_build_exe,
        &root_compiler_copy.step,
        &ensure_build_dir.step,
        &runtime_cmd.step,
        "compare/nurl_analysis.nu",
        "build/nurl_analysis.ll",
        compare_nurl_analysis_path,
        "nurl_analysis.ll",
        final_compiler_path,
    );

    const fmt_step = b.step("nurlfmt", b.fmt("Build {s}", .{nurlfmt_path}));
    fmt_step.dependOn(&nurlfmt_link.step);

    const fmt_cmd = b.addSystemCommand(&.{nurlfmt_path});
    fmt_cmd.setCwd(b.path("."));
    fmt_cmd.has_side_effects = true;
    if (b.args) |args| {
        fmt_cmd.addArgs(args);
    }
    fmt_cmd.step.dependOn(&nurlfmt_link.step);
    const fmt_run_step = b.step("fmt", b.fmt("Run {s} with forwarded args", .{nurlfmt_path}));
    fmt_run_step.dependOn(&fmt_cmd.step);

    const pkg_step = b.step("nurlpkg", b.fmt("Build {s}", .{nurlpkg_path}));
    pkg_step.dependOn(&nurlpkg_link.step);

    const lsp_step = b.step("nurl-lsp", b.fmt("Build {s}", .{nurllsp_path}));
    lsp_step.dependOn(&nurllsp_link.step);

    const tools_step = b.step("tools", "Build nurlfmt, nurlpkg, and nurl-lsp");
    tools_step.dependOn(&helper_copy.step);
    tools_step.dependOn(&nurlfmt_link.step);
    tools_step.dependOn(&nurlpkg_link.step);
    tools_step.dependOn(&nurllsp_link.step);

    const fmt_idempotent_cmd = addHelperStep(b, nurl_build_exe, &.{"fmt-idempotent"}, true);
    if (b.args) |args| {
        fmt_idempotent_cmd.addArgs(args);
    }
    fmt_idempotent_cmd.step.dependOn(tools_step);
    const fmt_idempotent_step = b.step("fmt-idempotent", "Verify nurlfmt idempotence and IR transparency");
    fmt_idempotent_step.dependOn(&fmt_idempotent_cmd.step);

    const dwarf_test_cmd = addHelperStep(b, nurl_build_exe, &.{"dwarf-test"}, true);
    if (b.args) |args| {
        dwarf_test_cmd.addArgs(args);
    }
    dwarf_test_cmd.step.dependOn(bootstrap_step);
    const dwarf_test_step = b.step("dwarf-test", "Run the DWARF debug-info behavioural regression harness");
    dwarf_test_step.dependOn(&dwarf_test_cmd.step);

    const test_42_cmd = addHelperStep(b, nurl_build_exe, &.{"test-42"}, true);
    if (b.args) |args| {
        test_42_cmd.addArgs(args);
    }
    test_42_cmd.step.dependOn(tools_step);
    const test_42_step = b.step("test-42", "Run the 4.2 Result/try propagation regression tests");
    test_42_step.dependOn(&test_42_cmd.step);

    const mcp_spec_drift_cmd = addHelperStep(b, nurl_build_exe, &.{"mcp-spec-drift"}, false);
    if (b.args) |args| {
        mcp_spec_drift_cmd.addArgs(args);
    }
    const mcp_spec_drift_step = b.step("mcp-spec-drift", "Check the pinned MCP protocol revision against the current spec");
    mcp_spec_drift_step.dependOn(&mcp_spec_drift_cmd.step);

    const bench_csv_cmd = addHelperStep(b, nurl_build_exe, &.{"bench-csv"}, true);
    if (b.args) |args| {
        bench_csv_cmd.addArgs(args);
    }
    bench_csv_cmd.step.dependOn(&compare_nurl_analysis_link.step);
    const bench_csv_step = b.step("bench-csv", "Run the CSV benchmark harness and optionally append compare/HISTORY.md");
    bench_csv_step.dependOn(&bench_csv_cmd.step);

    const sort_csv_cmd = addHelperStep(b, nurl_build_exe, &.{"sort-csv"}, true);
    if (b.args) |args| {
        sort_csv_cmd.addArgs(args);
    }
    const sort_csv_step = b.step("sort-csv", "Sort compare/test_data.csv with the Zig baseline comparator");
    sort_csv_step.dependOn(&sort_csv_cmd.step);

    const install_dev_cmd = addHelperStep(b, nurl_build_exe, &.{"install"}, true);
    if (b.args) |args| {
        install_dev_cmd.addArgs(args);
    }
    const install_dev_step = b.step("install-dev", "Install the local NURL developer experience via nurl-build");
    install_dev_step.dependOn(&install_dev_cmd.step);

    const uninstall_dev_cmd = addHelperStep(b, nurl_build_exe, &.{ "install", "--uninstall" }, true);
    if (b.args) |args| {
        uninstall_dev_cmd.addArgs(args);
    }
    const uninstall_dev_step = b.step("uninstall-dev", "Remove the local NURL developer install via nurl-build");
    uninstall_dev_step.dependOn(&uninstall_dev_cmd.step);

    b.getInstallStep().dependOn(tools_step);

    const snapshot_test_cmd = addHelperStep(b, nurl_build_exe, &.{"snapshot-test"}, true);
    if (b.args) |args| {
        snapshot_test_cmd.addArgs(args);
    }
    snapshot_test_cmd.step.dependOn(tools_step);

    const update_lastgood = addHelperCopyStep(b, nurl_build_exe, "compiler/nurlc.nu", "compiler/nurlc_lastgood.nu", false);
    update_lastgood.step.dependOn(&snapshot_test_cmd.step);

    const check_step = b.step("check", "Bootstrap the project, build tools, and run the snapshot test suite");
    check_step.dependOn(&update_lastgood.step);

    if (!host_is_windows) {
        const san_test_cmd = addHelperStep(b, nurl_build_exe, &.{"san-test"}, true);
        if (b.args) |args| {
            san_test_cmd.addArgs(args);
        }
        san_test_cmd.step.dependOn(tools_step);
        const san_test_step = b.step("san-test", "Run the sanitizer corpus after a sanitized build (-Dsan=true)");
        san_test_step.dependOn(&san_test_cmd.step);
    }
}

fn detectRuntimeConfig(b: *std.Build, san: bool) RuntimeConfig {
    const python = resolvePython(b);
    const root_path = b.build_root.path orelse ".";
    const cc_tokens = resolveCcTokens(b);
    const host_is_macos = b.graph.host.result.os.tag == .macos;
    const use_lto = !san and !isNativeMacZigCc(cc_tokens, host_is_macos);

    return .{
        .python = python,
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

fn addHelperStep(
    b: *std.Build,
    helper_exe: *std.Build.Step.Compile,
    args: []const []const u8,
    side_effects: bool,
) *std.Build.Step.Run {
    const cmd = b.addRunArtifact(helper_exe);
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = side_effects;
    cmd.addArgs(args);
    return cmd;
}

fn addMarkerSyncStep(
    b: *std.Build,
    helper_exe: *std.Build.Step.Compile,
    path: []const u8,
    enabled: bool,
) *std.Build.Step.Run {
    return addHelperStep(b, helper_exe, &.{ "marker", if (enabled) "--on" else "--off", path }, true);
}

fn addHelperCopyStep(
    b: *std.Build,
    helper_exe: *std.Build.Step.Compile,
    src: []const u8,
    dest: []const u8,
    executable: bool,
) *std.Build.Step.Run {
    return addHelperStep(b, helper_exe, if (executable) &.{ "copy", "--exec", src, dest } else &.{ "copy", src, dest }, true);
}

fn addHelperSymlinkStep(
    b: *std.Build,
    helper_exe: *std.Build.Step.Compile,
    src: []const u8,
    dest: []const u8,
) *std.Build.Step.Run {
    return addHelperStep(b, helper_exe, &.{ "symlink", src, dest }, true);
}

fn addHelperCopyLazyStep(
    b: *std.Build,
    helper_exe: *std.Build.Step.Compile,
    src: std.Build.LazyPath,
    dest: []const u8,
    executable: bool,
) *std.Build.Step.Run {
    const cmd = addHelperStep(b, helper_exe, if (executable) &.{ "copy", "--exec" } else &.{"copy"}, true);
    cmd.addFileArg(src);
    cmd.addArg(dest);
    return cmd;
}

fn addHelperCompareStep(
    b: *std.Build,
    helper_exe: *std.Build.Step.Compile,
    lhs: std.Build.LazyPath,
    rhs: std.Build.LazyPath,
) *std.Build.Step.Run {
    const cmd = addHelperStep(b, helper_exe, &.{"compare"}, false);
    cmd.addFileArg(lhs);
    cmd.addFileArg(rhs);
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
        runtime_override: ?[]const u8 = null,
        disable_lto: bool = false,
    },
) *std.Build.Step.Run {
    const cmd = b.addRunArtifact(helper_exe);
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = true;
    cmd.addArgs(&.{ "--opt", opts.opt_flag });
    if (opts.disable_lto) {
        cmd.addArg("--no-lto");
    }
    if (opts.runtime_override) |runtime_path| {
        cmd.addArgs(&.{ "--runtime", runtime_path });
    }
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
    compiler_bin_path: []const u8,
) *std.Build.Step.Run {
    const ir = b.addSystemCommand(&.{ compiler_bin_path, source_path });
    ir.setCwd(b.path("."));
    ir.step.dependOn(compiler_ready);
    applySanBuildEnv(ir, cfg.san);
    const ll = ir.captureStdOut(.{ .basename = ll_basename });

    const copy_ll = addHelperCopyLazyStep(b, helper_exe, ll, ll_output_path, false);
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

fn buildBinaryPath(b: *std.Build, name: []const u8, host_is_windows: bool) []const u8 {
    return b.fmt("build/{s}{s}", .{ name, if (host_is_windows) ".exe" else "" });
}

fn rootBinaryPath(b: *std.Build, name: []const u8, host_is_windows: bool) []const u8 {
    return b.fmt("{s}{s}", .{ name, if (host_is_windows) ".exe" else "" });
}
