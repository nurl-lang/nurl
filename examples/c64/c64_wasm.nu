// examples/c64/c64_wasm.nu — WebAssembly browser front-end for the C64.
//
// Shares the emulator engine in core.nu and drives it from the
// playground's canvas FFI. The three C64 ROMs (KERNAL / BASIC / CHARGEN)
// and the live keyboard-matrix state are pulled from host-provided import
// functions that c64demo.html wires up. One `run_one_frame` runs per
// displayed frame; `canvas_sleep` is the Asyncify yield back to the
// browser.
//
// Build (in the API container / via nurl_build_wasm): POST the combined
// source (core.nu + this file) to /build_wasm at -O2.

$ `examples/c64/core.nu`

// ── Canvas FFI (module "canvas") — same shape as the Game Boy demo ──
& `canvas` @ canvas_open i w i h → *i
& `canvas` @ canvas_present → v
& `canvas` @ canvas_sleep i ms → v
& `canvas` @ canvas_should_close → i

// ── Host imports wired up by c64demo.html ──
// bank: 0 = KERNAL (8K), 1 = BASIC (8K), 2 = CHARGEN (4K).
& `canvas` @ host_rom_byte i bank i idx → i
// Keyboard matrix: returns the row bitmask for column `col` (bit set = key down).
& `canvas` @ host_kb_col i col → i
// RESTORE key (wired to the NMI line, not the matrix): 1 while held.
& `canvas` @ host_restore → i
// A queued .prg to autostart: host_prg_pending returns its length once
// (clearing the queue), then host_prg_byte serves its bytes.
& `canvas` @ host_prg_pending → i
& `canvas` @ host_prg_byte i idx → i
// Hand this frame's SID samples (packed-stereo i64 ring) to Web Audio.
& `canvas` @ host_audio i ptr i nsamples → v
// A queued .d64 disk image: host_disk_pending returns its length once
// (clearing the queue), then host_disk_byte serves its bytes.
& `canvas` @ host_disk_pending → i
& `canvas` @ host_disk_byte i idx → i

// ── C64 16-colour palette (Pepto) → ARGB 0xAARRGGBB (host swaps R/B) ──
@ pal_argb i c → i {
    ?? & c 0x0F {
        0 → ^ 0xFF000000
        1 → ^ 0xFFFFFFFF
        2 → ^ 0xFF68372B
        3 → ^ 0xFF70A4B2
        4 → ^ 0xFF6F3D86
        5 → ^ 0xFF588D43
        6 → ^ 0xFF352879
        7 → ^ 0xFFB8C76F
        8 → ^ 0xFF6F4F25
        9 → ^ 0xFF433900
        10 → ^ 0xFF9A6759
        11 → ^ 0xFF444444
        12 → ^ 0xFF6C6C6C
        13 → ^ 0xFF9AD284
        14 → ^ 0xFF6C5EB5
        15 → ^ 0xFF959595
        _ → ^ 0xFF000000
    }
}

// Copy the 384x272 colour-index framebuffer into the canvas surface (one
// i64 per pixel; the low 32 bits carry the ARGB value).
@ blit * i fb → v {
    : *u src # *u g_fb
    : ~ i i 0
    ~ < i 104448 {
        = . fb i ( pal_argb & # i . src i 255 )
        = i + i 1
    }
}

// Pull a fixed-size ROM bank from the host into a NURL buffer.
@ pull_rom i bank i n → s {
    : s buf ( nurl_alloc n )
    : *u bp # *u buf
    : ~ i i 0
    ~ < i n { = . bp i # u ( host_rom_byte bank i )  = i + i 1 }
    ^ buf
}

@ main → i {
    ( c64_alloc )
    // Load the three ROMs from the host, then cold-boot.
    : s kbuf ( pull_rom 0 8192 )   ( load_kernal  # *u kbuf 8192 )  ( nurl_free kbuf )
    : s bbuf ( pull_rom 1 8192 )   ( load_basic   # *u bbuf 8192 )  ( nurl_free bbuf )
    : s cbuf ( pull_rom 2 4096 )   ( load_chargen # *u cbuf 4096 )  ( nurl_free cbuf )
    ( c64_boot )

    : *i fb ( canvas_open 384 272 )
    : *u kb # *u g_kb
    : ~ i running 1
    ~ != running 0 {
        // Refresh the keyboard matrix from the host.
        : ~ i col 0
        ~ < col 8 { = . kb col # u & ( host_kb_col col ) 255  = col + col 1 }
        = g_restore & ( host_restore ) 1
        // A .prg queued by the host? Pull it in and autostart it.
        : i pn ( host_prg_pending )
        ? > pn 0 {
            : s pb ( nurl_alloc pn )
            : *u pp # *u pb
            : ~ i k 0
            ~ < k pn { = . pp k # u ( host_prg_byte k )  = k + k 1 }
            ( prg_autostart # *u pb pn )
            ( nurl_free pb )
        } {}
        // A .d64 queued by the host? Attach it (drive 8) and autostart.
        : i dn ( host_disk_pending )
        ? > dn 0 {
            : s db ( nurl_alloc dn )
            : *u dp # *u db
            : ~ i j 0
            ~ < j dn { = . dp j # u ( host_disk_byte j )  = j + j 1 }
            ( disk_attach # *u db dn )
            ( nurl_free db )
            ( disk_autostart )
        } {}
        ( run_one_frame )       // also rasterises the frame (framebuffer + collisions)
        ( blit fb )
        ( canvas_present )
        ( host_audio # i g_audio g_audio_len )   // drain this frame's SID samples
        = g_audio_len 0
        ( canvas_sleep 20 )
        ? != 0 ( canvas_should_close ) { = running 0 } {}
    }
    ^ 0
}
