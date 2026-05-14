// audio_sparkles.nu — Microphone-driven pixel fireworks.
//
// Reads the browser microphone through the `audio` FFI and paints
// particles on a pixel canvas whose count, colour and velocity track
// the sound:
//
//   audio_level      → brightness + number of new particles / frame
//   audio_peak_bin   → hue shift (dominant pitch)
//   audio_centroid   → vertical bias (bright sound → top)
//   audio_is_silent  → particles fall & fade (no new spawns)
//
// Build (in-browser): press Build then Run in the NURL playground.
// The browser will ask for microphone permission on first run.
//
// The program is wasm-only: all audio_* hooks are provided by the
// playground's JS shim (stdlib/audio_wasm.c forwards to them). A
// native SDL2 back-end is *not* wired up for audio today, so running
// this via `nurl.sh` will link-fail with unresolved host imports.

& `libc`

@ rand → i

& `canvas`

@ canvas_open i w i h → *i

& `canvas`

@ canvas_present → v

& `canvas`

@ canvas_sleep i ms → v

& `canvas`

@ canvas_should_close → i

& `canvas`

@ canvas_close → v

& `audio`

@ audio_level → f

& `audio`

@ audio_peak_bin → i

& `audio`

@ audio_centroid → f

& `audio`

@ audio_bin_count → i

& `audio`

@ audio_is_silent i pct → i

& `audio`

@ audio_ready → i

: i W 480
: i H 270
: i FPS 60
: i MAX_PART 2000
: i FADE_MASK 16645629  // 0x00FDFDFD — keep 7/8 of each channel
: i ALPHA 4278190080  // 0xFF000000

// Linear-congruential-ish scramble so `hue_from_bin` doesn't just
// produce rainbows; gives each dominant pitch a distinct colour.
@ hue_from_bin i bin → i {
    : i h + * bin 53 17
    ^ % h 360
}

// Convert hue 0..360 into a rough RGB value (sextant-based, no sat/val).
// Returns 0x00RRGGBB (alpha added by caller).
@ hue_rgb i hue → i {
    : i seg / hue 60
    : i f * % hue 60 4  // 0..236 within segment
    : i q - 255 f
    : i r 0 : i g 0 : i b 0
    ? == seg 0 { = r 255 = g f = b 0 } {}
    ? == seg 1 { = r q = g 255 = b 0 } {}
    ? == seg 2 { = r 0 = g 255 = b f } {}
    ? == seg 3 { = r 0 = g q = b 255 } {}
    ? == seg 4 { = r f = g 0 = b 255 } {}
    ? == seg 5 { = r 255 = g 0 = b q } {}
    ^ | | * r 65536 * g 256 b
}

@ main → i {
    // Particle pools: parallel i64 arrays. Positions are in framebuffer
    // coords. vx/vy are pixels/frame × 100 (fixed-point Q8-ish).
    : *i px # *i ( malloc * MAX_PART 8 )
    : *i py # *i ( malloc * MAX_PART 8 )
    : *i pvx # *i ( malloc * MAX_PART 8 )
    : *i pvy # *i ( malloc * MAX_PART 8 )
    : *i pcol # *i ( malloc * MAX_PART 8 )
    : *i plife # *i ( malloc * MAX_PART 8 )

    // Zero life-counter for every slot (0 = free).
    : ~ i zi 0
    ~ < zi MAX_PART {
        = . plife zi 0
        = zi + zi 1
    }

    : *i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS
    : ~ i t 0
    : i total_px * W H

    ~ == 0 ( canvas_should_close ) {

        // ── 1. Fade the whole framebuffer toward black for motion blur.
        : ~ i px_idx 0
        ~ < px_idx total_px {
            : i old . fb px_idx
            // Preserve 7/8 of each 8-bit channel → smooth exponential fade.
            : i kept & old FADE_MASK
            // NURL has no bit-shift operator; integer division by 8 is the
            // moral equivalent of `kept >> 3` for the unsigned channel bytes.
            : i faded - kept / kept 8  // approx *7/8
            = . fb px_idx | ALPHA & faded 16777215
            = px_idx + px_idx 1
        }

        // ── 2. Sample microphone.
        : i ready ( audio_ready )
        : f lvl ? != 0 ready ( audio_level ) 0.0
        : i peak ? != 0 ready ( audio_peak_bin ) 0
        : f cen ? != 0 ready ( audio_centroid ) 0.0
        : i silent ( audio_is_silent 2 )

        // ── 3. Spawn up to N new particles proportional to loudness.
        //      lvl is 0..1; typical speech/music peaks around 0.2–0.5.
        : i spawn_cnt # i * lvl 300.0
        ? != 0 silent { = spawn_cnt 0 } {}

        : i hue ( hue_from_bin peak )
        : i col | ALPHA ( hue_rgb hue )

        // cen is in Hz; map a rough 50–8000 Hz range to vertical bias
        // 0 (top) .. H (bottom). Bright pitches aim up.
        : i cen_i # i cen
        : i bias_y - H / * cen_i H 8000
        ? < bias_y 0 { = bias_y 0 } {}
        ? >= bias_y H { = bias_y - H 1 } {}

        : ~ i s 0
        ~ < s spawn_cnt {
            // Find a free slot (plife == 0).
            : ~ i slot 0
            : ~ i found 0
            ~ & == 0 found < slot MAX_PART {
                ? == . plife slot 0 { = found 1 } { = slot + slot 1 }
            }
            ? == 0 found { = s spawn_cnt } {}  // pool full, stop spawning

            ? != 0 found {
                = . px slot / W 2
                = . py slot bias_y
                // Velocity: random direction, magnitude ∝ loudness.
                : i speed + 100 # i * lvl 800.0
                : i ang % ( rand ) 360
                // Cheap sin/cos via table is overkill; approximate with
                // modulo-branches. Use rand again for variety.
                : i vx - % ( rand ) 400 200
                : i vy - % ( rand ) 400 200
                = . pvx slot / * vx speed 200
                = . pvy slot / * vy speed 200
                = . pcol slot col
                = . plife slot + 60 % ( rand ) 60  // 60–120 frames
            } {}

            = s + s 1
        }

        // ── 4. Integrate and draw existing particles.
        : ~ i i 0
        ~ < i MAX_PART {
            ? != 0 . plife i {
                // Advance position (vx/vy are pixels/frame × 100).
                = . px i + . px i / . pvx i 100
                = . py i + . py i / . pvy i 100
                // Gravity (pulls down).
                = . pvy i + . pvy i 4
                // Decay life.
                = . plife i - . plife i 1

                : i xx . px i
                : i yy . py i
                ? & & >= xx 0 < xx W & >= yy 0 < yy H {
                    = . fb + * yy W xx . pcol i
                } { = . plife i 0 }
            } {}
            = i + i 1
        }

        ( canvas_present )
        ( canvas_sleep frame_ms )
        = t + t 1
    }

    ( canvas_close )
    ^ 0
}
