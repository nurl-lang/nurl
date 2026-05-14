// primordial_canvas.nu — primordial particle chemistry, live on a pixel canvas
//
// Same rules as examples/primordial.nu (compounds via bitmask OR, summed
// velocities, catalyst scattering) but rendered as animated pixels into
// a real canvas instead of as ASCII snapshots.
//
// In the browser playground the canvas element above the output animates
// live; press Stop to exit. Natively the program opens an SDL2 window;
// close it or press Escape to exit.
//
// Particle types (bitmask):
//   A=1  →  vx=+1        (red channel)
//   B=2  →  vx=-1        (green channel)
//   C=4  →  vy=+1        (blue channel)
//   D=8  →  vy=-1        (yellow = R+G)
//   X=16 →  catalyst     (white; random-walks, scatters compounds)
//
// When a compound is rendered, its colour is the OR of its bits' colours,
// so AC (red + blue) draws purple, ABCD draws all-channel-on = white,
// and so on. Catalysts punch bright white pixels through the soup.

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

// ── Config ────────────────────────────────────────────────────
: i W 180
: i H 100
: i SLOTS 360
: i PARTICLES 240
: i CATALYSTS 24
: i FPS 30

// Bit masks
: i BIT_A 1
: i BIT_B 2
: i BIT_C 4
: i BIT_D 8
: i BIT_X 16

// Background and particle colours (0xAARRGGBB)
: i COL_BG 4279769112  // 0xFF181a20 — matches playground panel
: i COL_A 4294901760  // 0xFFff0000 red
: i COL_B 4278222848  // 0xFF00d040 green
: i COL_C 4281784574  // 0xFF2090fe blue
: i COL_D 4294964035  // 0xFFfff143 yellow
: i COL_X 4294967295  // 0xFFffffff white

// ── RNG ───────────────────────────────────────────────────────
: ~ i RNG 305419896

@ rand_next → i {
    = RNG & + * RNG 1103515245 12345 2147483647
    ^ RNG
}

@ rand_range i n → i { ^ % ( rand_next ) n }

// ── Physics helpers ───────────────────────────────────────────
@ vel_x i b → i {
    : ~ i v 0
    ? != 0 & b BIT_A { = v + v 1 } {}
    ? != 0 & b BIT_B { = v - v 1 } {}
    ^ v
}

@ vel_y i b → i {
    : ~ i v 0
    ? != 0 & b BIT_C { = v + v 1 } {}
    ? != 0 & b BIT_D { = v - v 1 } {}
    ^ v
}

@ wrap i n i m → i { ^ % + m % n m m }

// Compose a colour from a compound bitmask by OR'ing per-bit colours.
@ colour_of i b → i {
    ? != 0 & b BIT_X { ^ COL_X } {}  // catalyst dominates
    : ~ i c COL_BG
    ? != 0 & b BIT_A { = c | c COL_A } {}
    ? != 0 & b BIT_B { = c | c COL_B } {}
    ? != 0 & b BIT_C { = c | c COL_C } {}
    ? != 0 & b BIT_D { = c | c COL_D } {}
    ^ c
}

@ find_free * i bs i N → i {
    : ~ i k 0
    ~ < k N {
        ? == . bs k 0 { ^ k } {}
        = k + k 1
    }
    ^ - 0 1
}

// ── One simulation tick ───────────────────────────────────────
@ tick * i xs * i ys * i bs i N → v {
    // 1) Move
    : ~ i k 0
    ~ < k N {
        : i b . bs k
        ? != 0 b {
            : ~ i vx ( vel_x b )
            : ~ i vy ( vel_y b )
            ? != 0 & b BIT_X {
                = vx + vx - ( rand_range 3 ) 1
                = vy + vy - ( rand_range 3 ) 1
            } {}
            = . xs k ( wrap + . xs k vx W )
            = . ys k ( wrap + . ys k vy H )
        } {}
        = k + k 1
    }
    // 2) Collisions
    : ~ i i_ 0
    ~ < i_ N {
        ? != 0 . bs i_ {
            : ~ i j_ + i_ 1
            ~ < j_ N {
                ? & != 0 . bs j_ & == . xs i_ . xs j_ == . ys i_ . ys j_ {
                    : i merged | . bs i_ . bs j_
                    : i xm . xs i_
                    : i ym . ys i_
                    ? != 0 & merged BIT_X {
                        = . bs i_ BIT_X
                        = . bs j_ 0
                        : ~ i bit 1
                        ~ <= bit 8 {
                            ? != 0 & merged bit {
                                : i free ( find_free bs N )
                                ? >= free 0 {
                                    = . bs free bit
                                    = . xs free ( wrap + xm - ( rand_range 3 ) 1 W )
                                    = . ys free ( wrap + ym - ( rand_range 3 ) 1 H )
                                } {}
                            } {}
                            = bit * bit 2
                        }
                    } {
                        = . bs i_ merged
                        = . bs j_ 0
                    }
                } {}
                = j_ + j_ 1
            }
        } {}
        = i_ + i_ 1
    }
}

// ── Render one frame into the framebuffer ────────────────────
@ render * i fb * i xs * i ys * i bs i N → v {
    // Clear to background
    : ~ i g 0
    ~ < g * W H {
        = . fb g COL_BG
        = g + g 1
    }
    // Plot each live particle
    : ~ i k 0
    ~ < k N {
        : i b . bs k
        ? != 0 b {
            : i x . xs k
            : i y . ys k
            : i idx + * y W x
            = . fb idx ( colour_of b )
            // 2x2 block so pixels are visible even at small FPS
            ? < + x 1 W { = . fb + idx 1 ( colour_of b ) } {}
            ? < + y 1 H { = . fb + idx W ( colour_of b ) } {}
            ? & < + x 1 W < + y 1 H { = . fb + idx + W 1 ( colour_of b ) } {}
        } {}
        = k + k 1
    }
}

@ main → i {
    : *i xs # *i ( malloc * SLOTS 8 )
    : *i ys # *i ( malloc * SLOTS 8 )
    : *i bs # *i ( malloc * SLOTS 8 )

    : ~ i k 0
    ~ < k SLOTS {
        = . xs k 0
        = . ys k 0
        = . bs k 0
        = k + k 1
    }

    // Seed particles
    : ~ i p 0
    ~ < p PARTICLES {
        : i w ( rand_range 4 )
        : i bit ? == w 0 BIT_A ? == w 1 BIT_B ? == w 2 BIT_C BIT_D
        = . bs p bit
        = . xs p ( rand_range W )
        = . ys p ( rand_range H )
        = p + p 1
    }
    : ~ i c 0
    ~ < c CATALYSTS {
        : i slot + PARTICLES c
        = . bs slot BIT_X
        = . xs slot ( rand_range W )
        = . ys slot ( rand_range H )
        = c + c 1
    }

    : *i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS

    ~ == 0 ( canvas_should_close ) {
        ( render fb xs ys bs SLOTS )
        ( tick xs ys bs SLOTS )
        ( canvas_present )
        ( canvas_sleep frame_ms )
    }

    ( canvas_close )
    ^ 0
}
