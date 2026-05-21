const std = @import("std");

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

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        std.debug.print("nurl-build: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) {
        std.debug.print(
            "usage: {s} <repo-root> <llvm-ir> <output-bin>\n",
            .{args[0]},
        );
        return error.InvalidArgs;
    }

    const root = args[1];
    const ll_path = args[2];
    const output_path = args[3];

    try ensureExists(io, ll_path, "LLVM IR");

    const runtime_path = try std.fs.path.join(arena, &.{ root, "stdlib", "runtime.o" });
    try ensureExists(io, runtime_path, "runtime.o");

    const nolto_marker_path = try std.fs.path.join(arena, &.{ root, "stdlib", "runtime.nolto" });
    const use_lto = !pathExists(io, nolto_marker_path);

    var driver_parts = try splitDriver(gpa, init);
    defer driver_parts.deinit(gpa);

    var child_argv: std.ArrayList([]const u8) = .empty;
    defer child_argv.deinit(gpa);

    try child_argv.appendSlice(gpa, driver_parts.items);
    try child_argv.append(gpa, "-O2");
    if (use_lto) {
        try child_argv.append(gpa, "-flto");
    }
    try child_argv.append(gpa, ll_path);
    try child_argv.append(gpa, runtime_path);
    try child_argv.append(gpa, "-lm");
    try child_argv.append(gpa, "-lpthread");

    const pkg_config_exe = init.environ_map.get("PKG_CONFIG") orelse "pkg-config";
    for (library_specs) |lib| {
        const marker_path = try std.fs.path.join(arena, &.{ root, "stdlib", lib.marker });
        if (!pathExists(io, marker_path)) continue;
        try appendPkgConfigOrFallback(gpa, arena, io, &child_argv, pkg_config_exe, lib);
    }

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

fn splitDriver(gpa: std.mem.Allocator, init: std.process.Init) !std.ArrayList([]const u8) {
    const env_driver = blk: {
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

fn ensureExists(io: std.Io, absolute_path: []const u8, label: []const u8) !void {
    if (!pathExists(io, absolute_path)) {
        std.debug.print("nurl-build: missing {s} at {s}\n", .{ label, absolute_path });
        return error.FileNotFound;
    }
}

fn pathExists(io: std.Io, absolute_path: []const u8) bool {
    std.Io.Dir.accessAbsolute(io, absolute_path, .{}) catch return false;
    return true;
}
