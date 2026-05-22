const std = @import("std");

const c = std.c;

extern "canvas" fn open(w: i64, h: i64, fb: [*]i64) void;
extern "canvas" fn present() void;
extern "canvas" fn sleep(ms: i64) void;
extern "canvas" fn should_close() i64;
extern "canvas" fn close() void;
extern "canvas" fn mouse_x() i64;
extern "canvas" fn mouse_y() i64;
extern "canvas" fn mouse_btn() i64;

pub export var __nurl_asyncify_stack: [4096]i8 = [_]i8{0} ** 4096;

var g_fb: ?[*]i64 = null;
var g_w: i64 = 0;
var g_h: i64 = 0;

fn callocI64(n: usize) ?[*]i64 {
    const raw = c.calloc(n, @sizeOf(i64)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

pub export fn __nurl_asyncify_stack_ptr() i32 {
    return @intCast(@intFromPtr(&__nurl_asyncify_stack[0]));
}

pub export fn __nurl_asyncify_stack_size() i32 {
    return __nurl_asyncify_stack.len;
}

pub export fn canvas_open(w: i64, h: i64) ?[*]i64 {
    if (g_fb) |fb| return fb;
    if (w <= 0 or h <= 0 or w > 4096 or h > 4096) return null;
    const n: usize = @intCast(w * h);
    const fb = callocI64(n) orelse return null;
    g_fb = fb;
    g_w = w;
    g_h = h;
    open(w, h, fb);
    return fb;
}

pub export fn canvas_present() void {
    present();
}

pub export fn canvas_sleep(ms: i64) void {
    if (ms <= 0) return;
    sleep(ms);
}

pub export fn canvas_should_close() i64 {
    return should_close();
}

pub export fn canvas_close() void {
    close();
    if (g_fb) |fb| {
        c.free(fb);
        g_fb = null;
    }
    g_w = 0;
    g_h = 0;
}

pub export fn canvas_mouse_x() i64 {
    if (g_fb == null) return 0;
    return mouse_x();
}

pub export fn canvas_mouse_y() i64 {
    if (g_fb == null) return 0;
    return mouse_y();
}

pub export fn canvas_mouse_btn() i64 {
    if (g_fb == null) return 0;
    return mouse_btn();
}
