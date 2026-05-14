// primordial.nu — primordial-soup particle chemistry in NURL
//
// Five elementary particle types, each with its own fixed velocity:
//
//     A  (bit 0):  moves right       (vx = +1)
//     B  (bit 1):  moves left        (vx = -1)
//     C  (bit 2):  moves down        (vy = +1)
//     D  (bit 3):  moves up          (vy = -1)
//     X  (bit 4):  catalyst          random-walks
//
// When particles share a cell they form a COMPOUND — their bitmasks
// are OR'd together. The compound's velocity is the componentwise
// sum of each set bit's contribution, so AB (right + left) sits
// still, AC drifts south-east, ABCD is also still, and so on.
//
// Catalysts are disruptive: if an X ends up in a cell with anything
// else, the whole mixture SCATTERS — each non-X bit breaks back off
// into its own particle and diffuses one cell outward. Meanwhile
// X itself keeps drifting on its random walk.
//
// So the system breathes: random collisions knit particles into
// ever-larger bound compounds; catalyst strikes tear them apart;
// drift carries the pieces off to collide somewhere else.
//
// Try tweaking PARTICLES / CATALYSTS, adding a bit, or changing
// the per-bit velocity — radically different regimes emerge.
//
// NURL features on display:
//   - Top-level constants (: i NAME value)
//   - Mutable globals (: ~ i NAME value) — the RNG state
//   - Bitwise & / | on i64
//   - Nested prefix arithmetic and chained ternaries
//   - Heap arrays via malloc + # *i cast
//   - Toroidal wrap-around via modular arithmetic

// ─── Config ───────────────────────────────────────────────────

: i W 60  // grid width  (display cells per row)
: i H 18  // grid height (rows)
: i SLOTS 128  // particle slots (>= PARTICLES + CATALYSTS,
//                  plus room for scatter)
: i PARTICLES 56  // live particles at t=0 (A/B/C/D mix)
: i CATALYSTS 6  // extra X particles mixed in
: i TICKS 120  // total simulation ticks
: i FRAME_EVERY 20  // snapshot every N ticks

// Bit masks
: i BIT_A 1
: i BIT_B 2
: i BIT_C 4
: i BIT_D 8
: i BIT_X 16

// ─── RNG: 31-bit LCG ──────────────────────────────────────────

: ~ i RNG 305419896

@ rand_next → i {
    = RNG & + * RNG 1103515245 12345 2147483647
    ^ RNG
}

@ rand_range i n → i { ^ % ( rand_next ) n }

// ─── Velocity from bitmask (ignores X) ────────────────────────

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

// Positive-modulo wrap: (n mod m + m) mod m
@ wrap i n i m → i { ^ % + m % n m m }

// ─── Glyph table ──────────────────────────────────────────────
//
// Single chars that hint at each compound's drift direction:
//
//     >  <  v  ^  : single movers (A, B, C, D)
//     ─  │      : stationary (AB=horizontal cancel, CD=vertical)
//     ↘ ↗ ↙ ↖  : diagonals (AC, AD, BC, BD)
//     ⇓ ⇑ ⇒ ⇐  : triples with one net direction
//     ●        : ABCD stationary cluster
//     ✦        : catalyst (X dominates glyph)
//     #        : anything else

@ glyph i b → s {
    ? == b 0 { ^ ` ` } {}
    ? != 0 & b BIT_X { ^ `✦` } {}
    ? == b 1 { ^ `>` } {}
    ? == b 2 { ^ `<` } {}
    ? == b 4 { ^ `v` } {}
    ? == b 8 { ^ `^` } {}
    ? == b 3 { ^ `─` } {}
    ? == b 12 { ^ `│` } {}
    ? == b 5 { ^ `↘` } {}
    ? == b 9 { ^ `↗` } {}
    ? == b 6 { ^ `↙` } {}
    ? == b 10 { ^ `↖` } {}
    ? == b 7 { ^ `⇓` } {}
    ? == b 11 { ^ `⇑` } {}
    ? == b 13 { ^ `⇒` } {}
    ? == b 14 { ^ `⇐` } {}
    ? == b 15 { ^ `●` } {}
    ^ `#`
}

// ─── Slot helpers ─────────────────────────────────────────────

@ find_free * i bs i N → i {
    : ~ i k 0
    ~ < k N {
        ? == . bs k 0 { ^ k } {}
        = k + k 1
    }
    ^ - 0 1
}

// ─── Simulation tick ──────────────────────────────────────────

@ tick * i xs * i ys * i bs i N → v {

    // 1) Move each live particle
    : ~ i k 0
    ~ < k N {
        : i b . bs k
        ? != 0 b {
            : ~ i vx ( vel_x b )
            : ~ i vy ( vel_y b )
            // Catalysts random-walk in addition to their baseline velocity
            ? != 0 & b BIT_X {
                = vx + vx - ( rand_range 3 ) 1
                = vy + vy - ( rand_range 3 ) 1
            } {}
            = . xs k ( wrap + . xs k vx W )
            = . ys k ( wrap + . ys k vy H )
        } {}
        = k + k 1
    }

    // 2) Resolve same-cell collisions (pairwise)
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
                        // SCATTER: i_ keeps only X, j_ dies, and each
                        // non-X bit of merged spawns a new particle
                        // displaced by ±1 so it doesn't instantly
                        // re-collide with the catalyst.
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
                        // Plain merge: i_ absorbs j_
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

// ─── Rendering ────────────────────────────────────────────────

@ render i tick_no * i xs * i ys * i bs i N → v {
    // Cell bitmask buffer
    : *i grid # *i ( malloc * * W H 8 )
    : ~ i g 0
    ~ < g * W H {
        = . grid g 0
        = g + g 1
    }

    : ~ i k 0
    ~ < k N {
        : i b . bs k
        ? != 0 b {
            : i idx + * . ys k W . xs k
            = . grid idx | . grid idx b
        } {}
        = k + k 1
    }

    ( nurl_print `\n── tick ` )
    ( nurl_print ( nurl_str_int tick_no ) )
    ( nurl_print ` ` )
    : ~ i dash 0
    ~ < dash - W 12 {
        ( nurl_print `─` )
        = dash + dash 1
    }
    ( nurl_print `\n┌` )
    : ~ i d2 0
    ~ < d2 W { ( nurl_print `─` ) = d2 + d2 1 }
    ( nurl_print `┐\n` )

    : ~ i y 0
    ~ < y H {
        ( nurl_print `│` )
        : ~ i x 0
        ~ < x W {
            ( nurl_print ( glyph . grid + * y W x ) )
            = x + x 1
        }
        ( nurl_print `│\n` )
        = y + y 1
    }

    ( nurl_print `└` )
    : ~ i d3 0
    ~ < d3 W { ( nurl_print `─` ) = d3 + d3 1 }
    ( nurl_print `┘\n` )
}

// ─── Init + main loop ─────────────────────────────────────────

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

    // Seed with PARTICLES random single-bit movers
    : ~ i p 0
    ~ < p PARTICLES {
        : i w ( rand_range 4 )
        : i bit ? == w 0 BIT_A ? == w 1 BIT_B ? == w 2 BIT_C BIT_D
        = . bs p bit
        = . xs p ( rand_range W )
        = . ys p ( rand_range H )
        = p + p 1
    }

    // Sprinkle catalysts
    : ~ i c 0
    ~ < c CATALYSTS {
        : i slot + PARTICLES c
        = . bs slot BIT_X
        = . xs slot ( rand_range W )
        = . ys slot ( rand_range H )
        = c + c 1
    }

    ( nurl_print `\n╔═════════════════════════════════════════════════════════════════╗\n` )
    ( nurl_print `║  primordial life — particle chemistry in NURL                   ║\n` )
    ( nurl_print `║    A >    B <    C v    D ^    X ✦ (catalyst, scatters)        ║\n` )
    ( nurl_print `║    compounds: AB ─ , CD │ , AC ↘ , AD ↗ , BC ↙ , BD ↖ , ABCD ●  ║\n` )
    ( nurl_print `╚═════════════════════════════════════════════════════════════════╝\n` )

    ( render 0 xs ys bs SLOTS )

    : ~ i t 1
    ~ <= t TICKS {
        ( tick xs ys bs SLOTS )
        ? == 0 % t FRAME_EVERY { ( render t xs ys bs SLOTS ) } {}
        = t + t 1
    }

    ( nurl_print `\n…time marches on. Final tick = ` )
    ( nurl_print ( nurl_str_int TICKS ) )
    ( nurl_print `.\n` )
    ^ 0
}
