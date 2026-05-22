const std = @import("std");

fn canvasStubDie(name: []const u8) noreturn {
    std.debug.print(
        "canvas: {s} called but this build has no SDL2 back-end.\n" ++
            "        Install SDL2 dev headers (e.g. `apt install libsdl2-dev`,\n" ++
            "        `brew install sdl2`, or `vcpkg install sdl2:x64-windows`)\n" ++
            "        and rebuild to enable the native canvas.\n",
        .{name},
    );
    std.process.exit(1);
}

pub export fn canvas_open(w: i64, h: i64) ?[*]i64 {
    _ = w;
    _ = h;
    canvasStubDie("canvas_open");
}

pub export fn canvas_present() void {
    canvasStubDie("canvas_present");
}

pub export fn canvas_sleep(ms: i64) void {
    _ = ms;
    canvasStubDie("canvas_sleep");
}

pub export fn canvas_should_close() i64 {
    canvasStubDie("canvas_should_close");
}

pub export fn canvas_mouse_x() i64 {
    canvasStubDie("canvas_mouse_x");
}

pub export fn canvas_mouse_y() i64 {
    canvasStubDie("canvas_mouse_y");
}

pub export fn canvas_mouse_btn() i64 {
    canvasStubDie("canvas_mouse_btn");
}

pub export fn canvas_close() void {}
