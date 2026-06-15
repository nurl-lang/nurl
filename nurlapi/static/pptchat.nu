// pptchat.nu — the embedded WebAssembly module for the PTT-Chat playground
// demo. A self-contained NURL program (wasm32-wasi) that reads the browser
// microphone through the `audio` FFI and paints a live "push-to-talk" monitor
// on a canvas: a VU level meter (green→red) plus a frequency-spectrum bar
// display. It carries no networking yet — it visualises the local mic so you
// can see your voice being captured before it is Opus-encoded and pushed onto
// the NURL overlay (which the page text describes).
//
// wasm-only: the audio_* / canvas_* hooks are provided by the demo page's JS
// shim (mic → Web Audio AnalyserNode). Build with the playground's wasm path
// (nurl_build_wasm / POST /build_wasm), not nurl.sh.

& `canvas` @ canvas_open i w i h → *i
& `canvas` @ canvas_present → v
& `canvas` @ canvas_sleep i ms → v
& `canvas` @ canvas_should_close → i
& `canvas` @ canvas_close → v

& `audio` @ audio_level → f
& `audio` @ audio_bin i idx → f
& `audio` @ audio_bin_count → i
& `audio` @ audio_is_silent i pct → i
& `audio` @ audio_ready → i

: i W 480
: i H 220
: i ALPHA 4278190080   // 0xFF000000
: i BG    4279308888   // 0xFF101418 — page-matching dark
: i TRACK 4280427059   // 0xFF222833 — VU track
: i BAR   4281572607   // 0xFF33CCFF — spectrum bars

@ clamp255 i x → i { ^ ? > x 255 255 ? < x 0 0 x }

// VU colour: green at rest → yellow → red as level climbs (0..100).
@ vu_color i l → i {
    : i r ( clamp255 / * l 255 50 )
    : i g ( clamp255 / * - 100 l 255 50 )
    ^ | ALPHA | * r 65536 * g 256
}

// Fill an axis-aligned rect into the i64-per-pixel framebuffer, clipped to W×H.
@ fill_rect *i fb i x i y i w i h i col → v {
    : ~ i yy y
    ~ < yy + y h {
        ? & >= yy 0 < yy H {
            : ~ i xx x
            ~ < xx + x w {
                ? & >= xx 0 < xx W { = . fb + * yy W xx col } {}
                = xx + xx 1
            }
        } {}
        = yy + yy 1
    }
}

@ main → i {
    : *i fb ( canvas_open W H )
    : i total * W H

    ~ == 0 ( canvas_should_close ) {
        // clear to background
        : ~ i p 0
        ~ < p total { = . fb p BG = p + p 1 }

        : i ready ( audio_ready )
        : f lvl ? != 0 ready ( audio_level ) 0.0
        : ~ i l100 # i * lvl 100.0
        ? > l100 100 { = l100 100 } {}
        ? < l100 0 { = l100 0 } {}

        // VU meter: a 400 px track with a level-coloured fill
        ( fill_rect fb 40 28 400 26 TRACK )
        ( fill_rect fb 40 28 / * l100 400 100 26 ( vu_color l100 ) )

        // "transmitting" tick: bright when not silent, dim when idle
        : i live ? == 0 ready 0 ? == 1 ( audio_is_silent 4 ) 0 1
        ( fill_rect fb 40 64 12 12 ? == live 1 ( vu_color 90 ) TRACK )

        // spectrum: 64 bars across the lower canvas, height ∝ bin magnitude
        : i bc ( audio_bin_count )
        ? > bc 0 {
            : i nbars 64
            : ~ i b 0
            ~ < b nbars {
                : i bin / * b bc nbars
                : f mag ? != 0 ready ( audio_bin bin ) 0.0
                : ~ i bh # i * mag 130.0
                ? > bh 130 { = bh 130 } {}
                ? < bh 0 { = bh 0 } {}
                ( fill_rect fb + 40 * b 6 - 210 bh 5 bh BAR )
                = b + b 1
            }
        } {}

        ( canvas_present )
        ( canvas_sleep 33 )
    }
    ( canvas_close )
    ^ 0
}
