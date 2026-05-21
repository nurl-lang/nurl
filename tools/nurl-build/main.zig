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
    mkdir,
    copy,
    symlink,
    marker,
    compare,
    buildwasm,
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

    if (std.meta.stringToEnum(Command, args[1])) |cmd| {
        return switch (cmd) {
            .link => runLink(init, args[2..]),
            .mkdir => runMkdir(io, args[2..]),
            .copy => runCopy(init.gpa, arena, io, args[2..]),
            .symlink => runSymlink(arena, init, io, args[2..]),
            .marker => runMarker(io, args[2..]),
            .compare => runCompare(init, io, args[2..]),
            .buildwasm => runBuildWasm(init, args[2..]),
            .clean => runClean(init, args[2..]),
            .startdev => runStartDev(init, args[2..]),
            .dockerpush => runDockerPush(init, args[2..]),
        };
    }

    return runLink(init, args[1..]);
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
    try std.Io.Dir.cwd().createDirPath(io, args[0]);
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
    if (std.fs.path.dirname(dest_abs)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }

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

    if (std.fs.path.dirname(dest)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }

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
        std.debug.print("       Start it first: ./startdev.sh\n", .{});
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

    if (std.fs.path.dirname(final_out_path)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = final_out_path,
        .data = response_bytes,
    });

    std.debug.print("\nDone: {s}  ({d} bytes)\n", .{ final_out_path, response_bytes.len });
    std.debug.print("\nTry:\n  ./wasmnurl.sh examples/showcase.nu\n", .{});
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
