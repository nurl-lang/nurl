& `libc`

@ rand → i

& `libc`

@ malloc i size → *i

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

@ audio_is_silent i pct → i

& `audio`

@ audio_ready → i

: i W 480
: i H 270
: i FPS 60
: i MAX_PART 4000
: i FADE_MASK 16645629  // 0x00FDFDFD – keep 7/8 of each channel
: i ALPHA 4278190080  // 0xFF000000 – opaque alpha

// Linear‑congruential scramble – gives each pitch a distinct hue.
@ hue_from_bin i bin → i {
    : i h + * bin 53 17
    ^ % h 360
}

// Convert hue (0‑360) to a rough RGB value (0x00RRGGBB).
@ hue_rgb i hue → i {
    : i seg / hue 60
    : i f * % hue 60 4
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

// Fade the whole framebuffer toward black (motion‑blur effect).
@ fade_frame * i fb i total_px → v {
    : ~ i i 0
    ~ < i total_px {
        : i old . fb i
        : i kept & old FADE_MASK
        : i faded - kept / kept 8
        = . fb i | ALPHA & faded 16777215
        = i + i 1
    }
}

// --------------------------------------------------------------------
//  Main program – microphone‑driven pixel fireworks
// --------------------------------------------------------------------
@ main → i {
    // Allocate particle pools (parallel i64 arrays).
    : *i px # *i ( malloc * MAX_PART 8 )
    : *i py # *i ( malloc * MAX_PART 8 )
    : *i pvx # *i ( malloc * MAX_PART 8 )
    : *i pvy # *i ( malloc * MAX_PART 8 )
    : *i pcol # *i ( malloc * MAX_PART 8 )
    : *i plife # *i ( malloc * MAX_PART 8 )

    // Initialise life‑counters (0 = free slot).
    : ~ i zi 0
    ~ < zi MAX_PART {
        = . plife zi 0
        = zi + zi 1
    }

    // Open a canvas.
    : *i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS
    : i total_px * W H

    // Main render loop – run while the window stays open.
    ~ == 0 ( canvas_should_close ) {
        // 1️⃣  Fade previous frame (motion blur).
        ( fade_frame fb total_px )

        // 2️⃣  Sample audio – guarded by audio_ready.
        : i ready ( audio_ready )
        : f lvl ? != 0 ready ( audio_level ) 0.0
        : i peak ? != 0 ready ( audio_peak_bin ) 0
        : f cen ? != 0 ready ( audio_centroid ) 0.0
        : i silent ( audio_is_silent 2 )

        // 3️⃣  Spawn new particles proportional to loudness.
        : i spawn_cnt # i * lvl 500.0
        ? != 0 silent { = spawn_cnt 0 } {}

        // Colour based on dominant pitch.
        : i hue ( hue_from_bin peak )
        : i col | ALPHA ( hue_rgb hue )

        // 4️⃣  Vertical bias from centroid (bright sound → top).
        : i cen_i # i cen
        : i bias_y - H / * cen_i H 8000
        ? < bias_y 0 { = bias_y 0 } {}
        ? >= bias_y H { = bias_y - H 1 } {}

        // 5️⃣  Spawn particles.
        : i s 0
        ~ < s spawn_cnt {
            // Find a free slot (plife == 0).
            : ~ i slot 0
            : ~ i found 0
            ~ & == 0 found < slot MAX_PART {
                ? == . plife slot 0 { = found 1 } { = slot + slot 1 }
            }
            // If the pool is full, abort further spawns.
            ? == 0 found { = s spawn_cnt } {}
            ? != 0 found {
                = . px slot / slot 2
                = . py slot bias_y
                : i speed + 100 # i * lvl 800.0
                : i vx - % ( rand ) 400 200
                : i vy - % ( rand ) 400 200
                = . pvx slot / * vx speed 200
                = . pvy slot / * vy speed 200
                = . pcol slot col
                = . plife slot + 60 % ( rand ) 60  // life 60‑120 frames
            } {}
            = s + s 1
        }

        // 6️⃣  Update and draw existing particles.
        : ~ i i 0
        ~ < i MAX_PART {
            ? != 0 . plife i {
                // Advance position (fixed‑point Q8).
                = . px i + . px i / . pvx i 100
                = . py i + . py i / . pvy i 100
                // Simple gravity.
                = . pvy i + . pvy i 4
                // Age.
                = . plife i - . plife i 1

                // Draw if inside the canvas.
                : i x . px i
                : i y . py i
                : i col . pcol i
                ? & >= x 0 < x W {
                    ? & >= y 0 < y H {
                        = . fb + * y W x col
                    } {}
                } {}
                // Kill particles that wander off‑screen.
                ? & >= x 0 < x W & >= y 0 < y H {} { = . plife i 0 }
            } {}
            = i + i 1
        }

        // 7️⃣  Present the frame and sleep.
        ( canvas_present )
        ( canvas_sleep frame_ms )
    }

    // Cleanup.
    ( canvas_close )
    ^ 0
}
