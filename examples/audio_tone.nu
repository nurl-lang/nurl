// examples/audio_tone.nu — chiptune square-wave melody + oscilloscope.
//
// Demonstrates AUDIO OUTPUT in the NURL playground's WebAssembly runner.
// Each frame we synthesize a block of PCM and hand it to the browser's
// Web Audio sink via the `audio_out_push` host shim, while drawing the
// waveform on the canvas. Press Build, then Run.
//
// Audio format: packed-stereo i64 samples — low 16 bits = left, high 16
// bits = right (both signed 16-bit) — pushed at 48 kHz.

& `canvas` @ canvas_open i w i h → *i
& `canvas` @ canvas_present → v
& `canvas` @ canvas_sleep i ms → v
& `canvas` @ canvas_should_close → i

// Audio output sink (provided by the playground; a no-op import elsewhere).
// Push `n` packed-stereo samples from the buffer at `buf`.
& `canvas` @ audio_out_push i buf i n → v

// A one-octave major scale (C4..C5), in Hz.
@ note_freq i n → i {
    ?? n {
        0 → ^ 262   1 → ^ 294   2 → ^ 330   3 → ^ 349
        4 → ^ 392   5 → ^ 440   6 → ^ 494   7 → ^ 523
        _ → ^ 440
    }
}

@ main → i {
    : i W 320
    : i H 140
    : *i fb ( canvas_open W H )
    : s sbuf ( nurl_zalloc * 2048 8 )       // packed samples handed to audio
    : *i scope # *i ( malloc * 2048 8 )     // raw signed samples for the scope

    : i rate 48000
    : i spf 800                             // samples per frame (≈ 48000 / 60)
    : i amp 5000                            // square-wave amplitude (modest)

    : ~ i phase 0
    : ~ i note 0
    : ~ i frame 0

    ~ == 0 ( canvas_should_close ) {
        : i freq ( note_freq note )
        : i period / rate freq
        : i half / period 2

        // ── synthesize one frame of a square wave ──
        : ~ i i 0
        ~ < i spf {
            : i ph % phase period
            : i s ? < ph half amp - 0 amp
            = . scope i s
            ( nurl_poke sbuf i | & s 0xFFFF << & s 0xFFFF 16 )
            = phase + phase 1
            = i + i 1
        }
        ( audio_out_push # i sbuf spf )

        // ── draw: clear, then plot the waveform ──
        : i tot * W H
        : ~ i p 0
        ~ < p tot { = . fb p 0xFF101418  = p + p 1 }

        : ~ i x 0
        ~ < x W {
            : i si / * x spf W
            : i s . scope si
            : ~ i y + / H 2 / * s / H 2 32768
            ? < y 0 { = y 0 } {}
            ? >= y H { = y - H 1 } {}
            = . fb + * y W x 0xFF33FF66
            = x + x 1
        }

        ( canvas_present )
        ( canvas_sleep 16 )

        = frame + frame 1
        ? >= frame 28 { = frame 0  = note % + note 1 8 } {}   // next note ≈ 0.47 s
    }
    ^ 0
}
