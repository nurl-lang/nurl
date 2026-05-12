// pixels_demo.nu — minimal canvas animation: a plasma-like color gradient
//
// Opens a WxH pixel window, animates a moving sinusoidal color field
// frame by frame, and closes cleanly when the window is closed
// (native) or the Stop button is pressed (browser playground).
//
// The canvas framebuffer is w*h i64 slots; the low 32 bits of each
// slot are an ARGB8888 pixel (0xAARRGGBB). Alpha = 0xFF = opaque.
//
// Demonstrates the full canvas API:
//     canvas_open        — allocate + show the window, get framebuffer
//     canvas_present     — blit framebuffer to the visible surface
//     canvas_sleep       — frame pacing; yields to the host event loop
//     canvas_should_close— non-zero when the user closes the window
//     canvas_close       — teardown

& `canvas` @ canvas_open         i w i h → * i
& `canvas` @ canvas_present      → v
& `canvas` @ canvas_sleep        i ms → v
& `canvas` @ canvas_should_close → i
& `canvas` @ canvas_close        → v

: i W     160
: i H      90
: i FPS    30

// Sine look-up table: indexed by t in milliradians in [0, LUT_SIZE).
// Populated once at startup from isin(); the inner render loop then
// only does array reads, turning three trig calls per pixel into
// three memory loads.
: i LUT_SIZE 6283

// ── crude fixed-point sine: returns sin(x / 1000) * 1000 as an int.
// Uses the identity sin(x) ≈ x - x^3/6 for |x| < 1 and wraps into
// that range. Not precise, but shapes a nice plasma.
@ isin i t → i {
    // Wrap t into [-3141, 3141]   (≈ -π..π, in milliradians)
    : ~ i x % t 6283
    ? > x 3141 { = x - x 6283 } {}
    ? < x - 0 3141 { = x + x 6283 } {}
    // Use Bhaskara's approx: sin(x) ≈ 4x(π-|x|) / (5π² - x(π-|x|))  (in milli)
    : i absx ? < x 0 - 0 x x
    : i k - 3141 absx
    : i num * 4 * x k
    : i den - * 5 * 3141 3141 * x k
    // guard against divide by zero on small kernels
    ? == den 0 { ^ 0 } {}
    ^ / * num 1000 den
}

// Positive modulo that handles any sign of t. NURL's % is C srem,
// which can return negative on negative inputs — wrap via (t%L + L) % L.
@ pmod i t i L → i { ^ % + % t L L L }

@ main → i {
    // Build three channel-specific LUTs up-front. Each lut_X entry
    // already has its byte shifted into the final ARGB position
    // (r<<16, g<<8, b<<0) with the 0xFF alpha baked into lut_r.
    // That turns the inner-loop pixel formula into:
    //     pixel = lut_r[i1] | lut_g[i2] | lut_b[i3]
    // i.e. three loads, three ORs, one store — no multiplies on the
    // hot path, no trig, no division. ~150 KiB total table size.
    : * i lut_r # * i ( malloc * LUT_SIZE 8 )
    : * i lut_g # * i ( malloc * LUT_SIZE 8 )
    : * i lut_b # * i ( malloc * LUT_SIZE 8 )
    : ~ i k 0
    ~ < k LUT_SIZE {
        : i v + 128 / * ( isin k ) 120 1000
        = . lut_r k + 4278190080 * v 65536    // 0xFF<<24 | v<<16
        = . lut_g k * v 256                   //            v<<8
        = . lut_b k v                         //            v<<0
        = k + k 1
    }

    : * i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS
    : ~ i t 0

    ~ == 0 ( canvas_should_close ) {
        // Per-frame t-phases for the three channels.
        : i p1 t
        : i p2 * t 2
        : i p3 * t 3

        : ~ i y 0
        ~ < y H {
            // Per-row base indices (positive mod once).
            // Channel 1 has no y term: base is constant across rows.
            : i base1 ( pmod p1               LUT_SIZE )
            : i base2 ( pmod + p2 * y  50     LUT_SIZE )
            : i base3 ( pmod + p3 * y - 0 30  LUT_SIZE )

            // Per-x stride of each channel's sine argument.
            // Using straight add + conditional sub for cheap wrap-around.
            : ~ i i1 base1
            : ~ i i2 base2
            : ~ i i3 base3
            : i row_off * y W

            : ~ i x 0
            ~ < x W {
                // Pre-shifted LUTs already embed alpha/r/g/b into
                // their ARGB slots → one OR per channel yields the pixel.
                = . fb + row_off x | | . lut_r i1 . lut_g i2 . lut_b i3

                // Advance LUT indices by each channel's x-stride,
                // wrapping modulo LUT_SIZE with a single compare+sub.
                = i1 + i1 40
                ? >= i1 LUT_SIZE { = i1 - i1 LUT_SIZE } {}
                = i2 + i2 20
                ? >= i2 LUT_SIZE { = i2 - i2 LUT_SIZE } {}
                = i3 + i3 30
                ? >= i3 LUT_SIZE { = i3 - i3 LUT_SIZE } {}

                = x + x 1
            }
            = y + y 1
        }

        ( canvas_present )
        ( canvas_sleep frame_ms )
        = t + t 1
    }

    ( canvas_close )
    ^ 0
}
