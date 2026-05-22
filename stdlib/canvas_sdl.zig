const std = @import("std");
const c = std.c;

const SDL_Window = opaque {};
const SDL_Renderer = opaque {};
const SDL_Texture = opaque {};

const SDL_Keysym = extern struct {
    scancode: i32,
    sym: i32,
    mod: u16,
    unused: u32,
};

const SDL_KeyboardEvent = extern struct {
    type: u32,
    timestamp: u32,
    windowID: u32,
    state: u8,
    repeat: u8,
    padding2: u8,
    padding3: u8,
    keysym: SDL_Keysym,
};

const SDL_Event = extern union {
    type: u32,
    key: SDL_KeyboardEvent,
    padding: [56]u8,
};

extern fn SDL_GetError() [*:0]const u8;
extern fn SDL_WasInit(flags: u32) u32;
extern fn SDL_Init(flags: u32) c_int;
extern fn SDL_QuitSubSystem(flags: u32) void;
extern fn SDL_CreateWindow(title: [*:0]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32) ?*SDL_Window;
extern fn SDL_DestroyWindow(window: ?*SDL_Window) void;
extern fn SDL_CreateRenderer(window: ?*SDL_Window, index: c_int, flags: u32) ?*SDL_Renderer;
extern fn SDL_DestroyRenderer(renderer: ?*SDL_Renderer) void;
extern fn SDL_RenderSetLogicalSize(renderer: ?*SDL_Renderer, w: c_int, h: c_int) c_int;
extern fn SDL_CreateTexture(renderer: ?*SDL_Renderer, format: u32, access: c_int, w: c_int, h: c_int) ?*SDL_Texture;
extern fn SDL_DestroyTexture(texture: ?*SDL_Texture) void;
extern fn SDL_UpdateTexture(texture: ?*SDL_Texture, rect: ?*const anyopaque, pixels: ?*const anyopaque, pitch: c_int) c_int;
extern fn SDL_RenderClear(renderer: ?*SDL_Renderer) c_int;
extern fn SDL_RenderCopy(renderer: ?*SDL_Renderer, texture: ?*SDL_Texture, src_rect: ?*const anyopaque, dst_rect: ?*const anyopaque) c_int;
extern fn SDL_RenderPresent(renderer: ?*SDL_Renderer) void;
extern fn SDL_PollEvent(event: ?*SDL_Event) c_int;
extern fn SDL_Delay(ms: u32) void;
extern fn SDL_GetMouseState(x: ?*c_int, y: ?*c_int) u32;
extern fn SDL_RenderWindowToLogical(renderer: ?*SDL_Renderer, window_x: c_int, window_y: c_int, logical_x: ?*f32, logical_y: ?*f32) c_int;

const SDL_INIT_VIDEO: u32 = 0x00000020;
const SDL_WINDOWPOS_CENTERED: c_int = @bitCast(@as(u32, 0x2FFF0000));
const SDL_WINDOW_SHOWN: u32 = 0x00000004;
const SDL_RENDERER_SOFTWARE: u32 = 0x00000001;
const SDL_RENDERER_ACCELERATED: u32 = 0x00000002;
const SDL_RENDERER_PRESENTVSYNC: u32 = 0x00000004;
const SDL_TEXTUREACCESS_STREAMING: c_int = 1;
const SDL_PIXELFORMAT_ARGB8888: u32 = 372_645_892;
const SDL_QUIT: u32 = 0x100;
const SDL_KEYDOWN: u32 = 0x300;
const SDLK_ESCAPE: i32 = 27;
const SDL_BUTTON_LEFT: u32 = 1;

fn sdlButton(button: u32) u32 {
    return @as(u32, 1) << @intCast(button - 1);
}

var g_win: ?*SDL_Window = null;
var g_ren: ?*SDL_Renderer = null;
var g_tex: ?*SDL_Texture = null;
var g_fb: ?[*]i64 = null;
var g_rgba: ?[*]i32 = null;
var g_w: c_int = 0;
var g_h: c_int = 0;
var g_should_close: c_int = 0;

fn sdlError() []const u8 {
    return std.mem.span(SDL_GetError());
}

fn failCanvas(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

pub export fn canvas_open(w: i64, h: i64) ?[*]i64 {
    if (g_win != null) return g_fb;
    if (w <= 0 or h <= 0 or w > 4096 or h > 4096) {
        failCanvas("canvas_open: invalid dimensions {d}x{d}\n", .{ w, h });
        return null;
    }

    if (SDL_WasInit(SDL_INIT_VIDEO) == 0) {
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            failCanvas("canvas_open: SDL_Init failed: {s}\n", .{sdlError()});
            return null;
        }
    }

    var scale: i64 = 1;
    while (w * scale < 400 and h * scale < 400 and scale < 8) : (scale += 1) {}

    g_win = SDL_CreateWindow(
        "NURL Canvas",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        @intCast(w * scale),
        @intCast(h * scale),
        SDL_WINDOW_SHOWN,
    );
    if (g_win == null) {
        failCanvas("canvas_open: CreateWindow failed: {s}\n", .{sdlError()});
        return null;
    }

    g_ren = SDL_CreateRenderer(g_win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (g_ren == null) {
        g_ren = SDL_CreateRenderer(g_win, -1, SDL_RENDERER_SOFTWARE);
    }
    if (g_ren == null) {
        failCanvas("canvas_open: CreateRenderer failed: {s}\n", .{sdlError()});
        SDL_DestroyWindow(g_win);
        g_win = null;
        return null;
    }

    _ = SDL_RenderSetLogicalSize(g_ren, @intCast(w), @intCast(h));

    g_tex = SDL_CreateTexture(
        g_ren,
        SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING,
        @intCast(w),
        @intCast(h),
    );
    if (g_tex == null) {
        failCanvas("canvas_open: CreateTexture failed: {s}\n", .{sdlError()});
        SDL_DestroyRenderer(g_ren);
        g_ren = null;
        SDL_DestroyWindow(g_win);
        g_win = null;
        return null;
    }

    const px_count: usize = @intCast(w * h);
    const fb_raw = c.calloc(px_count, @sizeOf(i64)) orelse return null;
    const rgba_raw = c.malloc(px_count * @sizeOf(i32)) orelse {
        c.free(fb_raw);
        return null;
    };
    g_fb = @ptrCast(@alignCast(fb_raw));
    g_rgba = @ptrCast(@alignCast(rgba_raw));
    g_w = @intCast(w);
    g_h = @intCast(h);
    g_should_close = 0;
    return g_fb;
}

pub export fn canvas_present() void {
    const tex = g_tex orelse return;
    const fb = g_fb orelse return;
    const rgba = g_rgba orelse return;
    const ren = g_ren orelse return;

    const n: usize = @intCast(@as(i64, g_w) * @as(i64, g_h));
    var i: usize = 0;
    while (i < n) : (i += 1) {
        rgba[i] = @truncate(fb[i] & 0xFFFF_FFFF);
    }

    _ = SDL_UpdateTexture(tex, null, @ptrCast(rgba), g_w * @as(c_int, @intCast(@sizeOf(i32))));
    _ = SDL_RenderClear(ren);
    _ = SDL_RenderCopy(ren, tex, null, null);
    SDL_RenderPresent(ren);

    var e: SDL_Event = undefined;
    while (SDL_PollEvent(&e) != 0) {
        if (e.type == SDL_QUIT) {
            g_should_close = 1;
        } else if (e.type == SDL_KEYDOWN and e.key.keysym.sym == SDLK_ESCAPE) {
            g_should_close = 1;
        }
    }
}

pub export fn canvas_sleep(ms: i64) void {
    if (ms <= 0) return;
    SDL_Delay(@intCast(ms));
}

pub export fn canvas_should_close() i64 {
    var e: SDL_Event = undefined;
    while (SDL_PollEvent(&e) != 0) {
        if (e.type == SDL_QUIT) {
            g_should_close = 1;
        } else if (e.type == SDL_KEYDOWN and e.key.keysym.sym == SDLK_ESCAPE) {
            g_should_close = 1;
        }
    }
    return g_should_close;
}

fn canvasMouseXY(out_x: ?*c_int, out_y: ?*c_int) void {
    var wx: c_int = 0;
    var wy: c_int = 0;
    _ = SDL_GetMouseState(&wx, &wy);
    if (g_ren != null and g_w > 0 and g_h > 0) {
        var fx: f32 = 0;
        var fy: f32 = 0;
        _ = SDL_RenderWindowToLogical(g_ren, wx, wy, &fx, &fy);
        if (out_x) |ptr| ptr.* = @intFromFloat(fx);
        if (out_y) |ptr| ptr.* = @intFromFloat(fy);
    } else {
        if (out_x) |ptr| ptr.* = wx;
        if (out_y) |ptr| ptr.* = wy;
    }
}

pub export fn canvas_mouse_x() i64 {
    if (g_win == null) return 0;
    var x: c_int = 0;
    var y: c_int = 0;
    canvasMouseXY(&x, &y);
    return x;
}

pub export fn canvas_mouse_y() i64 {
    if (g_win == null) return 0;
    var x: c_int = 0;
    var y: c_int = 0;
    canvasMouseXY(&x, &y);
    return y;
}

pub export fn canvas_mouse_btn() i64 {
    if (g_win == null) return 0;
    const state = SDL_GetMouseState(null, null);
    return if ((state & sdlButton(SDL_BUTTON_LEFT)) != 0) 1 else 0;
}

pub export fn canvas_close() void {
    if (g_tex) |tex| {
        SDL_DestroyTexture(tex);
        g_tex = null;
    }
    if (g_ren) |ren| {
        SDL_DestroyRenderer(ren);
        g_ren = null;
    }
    if (g_win) |win| {
        SDL_DestroyWindow(win);
        g_win = null;
    }
    if (g_fb) |fb| {
        c.free(fb);
        g_fb = null;
    }
    if (g_rgba) |rgba| {
        c.free(rgba);
        g_rgba = null;
    }
    g_w = 0;
    g_h = 0;
    g_should_close = 0;
    if (SDL_WasInit(SDL_INIT_VIDEO) != 0) {
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
    }
}
