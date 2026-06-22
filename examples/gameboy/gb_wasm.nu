// examples/gameboy/gb_wasm.nu — WebAssembly browser front-end.
//
// Shares the emulator engine in core.nu and drives it from the
// playground's canvas FFI. The ROM bytes and the live joypad state are
// pulled from two small host-provided import modules ("rom", "joypad")
// that gameboydemo.html wires up. One `run_one_frame` runs per displayed
// frame; `canvas_sleep` is the Asyncify yield back to the browser.
//
// Build (in the API container):  POST this source to /build_wasm.

$ `examples/gameboy/core.nu`

// ── Canvas FFI (module "canvas") — same shape as the native SDL API ──
& `canvas` @ canvas_open i w i h → *i

& `canvas` @ canvas_present → v

& `canvas` @ canvas_sleep i ms → v

& `canvas` @ canvas_should_close → i

// ── Host imports wired up by gameboydemo.html ──
& `canvas` @ host_rom_size → i  // ROM length in bytes
& `canvas` @ host_rom_byte i idx → i  // ROM[idx]
& `canvas` @ host_joypad → i  // button bitmask (see g_joyp)
& `canvas` @ host_audio i ptr i nsamples → v  // drain APU ring → Web Audio

// GB shade (0=white..3=black) → ARGB8888 0xAARRGGBB (host swaps R/B).
@ shade_argb i s → i {
    ?? s {
        0 → ^ 0xFFFFFFFF
        1 → ^ 0xFFAAAAAA
        2 → ^ 0xFF555555
        3 → ^ 0xFF000000
        _ → ^ 0xFF000000
    }
}

// Copy the 160×144 GB framebuffer into the canvas surface (one i64 per
// pixel; the low 32 bits carry the ARGB value).
@ blit * i fb → v {
    : *u gb # *u g_fb
    : ~ i i 0
    ~ < i 23040 {
        = . fb i ( shade_argb & # i . gb i 255 )
        = i + i 1
    }
}

@ main → i {
    // Pull the selected ROM from the host into a scratch buffer, boot it.
    : i n ( host_rom_size )
    ? <= n 1 { ^ 1 } {}
    : s buf ( nurl_alloc n )
    : *u bp # *u buf
    : ~ i i 0
    ~ < i n { = . bp i # u ( host_rom_byte i ) = i + i 1 }
    ( cart_load bp n )
    ( nurl_free buf )

    : *i fb ( canvas_open 160 144 )
    : ~ i running 1
    ~ != running 0 {
        = g_joyp ( host_joypad )
        ( run_one_frame )
        ( blit fb )
        ( canvas_present )
        ( host_audio # i g_audio g_audio_len )  // hand this frame's samples to Web Audio
        = g_audio_len 0
        ( canvas_sleep 16 )
        ? != 0 ( canvas_should_close ) { = running 0 } {}
    }
    ^ 0
}
