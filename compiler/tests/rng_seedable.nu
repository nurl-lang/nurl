// Regression: std/rng.nu — seedable deterministic PRNG (xoshiro256**).
//
// xoshiro256** seeded via SplitMix64 is a fully specified, portable
// algorithm: a given seed must produce a byte-identical stream on every
// platform and every build. The expected values below were computed by
// an independent reference implementation of the same algorithm; this
// test pins NURL's output to them. A drift here means either the u64
// codegen (logical `lshr` for `>>`, wrapping `mul`/`add`, `rotl` via
// shift-or) or the seeding regressed — both silent-miscompile classes.
//
// Also guards the field-vs-index `.` aliasing footgun: rng_next's locals
// are deliberately named `w*` so they don't shadow the `s*` field names
// (a shadow turns `. st s0` from a field load into a pointer index).
//
// Covers: exact stream for seeds 0 and 0x1234; determinism (two
// generators, one seed → identical streams); rng_below bounds + zero
// guard; rng_range inverted-range guard.

$ `stdlib/core/string.nu`
$ `stdlib/std/rng.nu`

// Compare; print a line and return 1 on mismatch, 0 on match.
@ chk i got i want s label → i {
    ? == got want {
        ^ 0
    } {
        ( nurl_print `FAIL ` )
        ( nurl_print label )
        ( nurl_print ` got=` )
        ( nurl_print ( nurl_str_int got ) )
        ( nurl_print ` want=` )
        ( nurl_print ( nurl_str_int want ) )
        ( nurl_print `\n` )
        ^ 1
    }
}

@ main → i {
    : ~ i fails 0

    // ── Exact stream, seed 0 ────────────────────────────────────────
    : Rng g0 ( rng_seed 0 )
    = fails + fails ( chk ( rng_next g0 ) -7355399402456485196 `seed0[0]` )
    = fails + fails ( chk ( rng_next g0 ) -4652746763540216534 `seed0[1]` )
    = fails + fails ( chk ( rng_next g0 ) 1900383378846508768 `seed0[2]` )
    = fails + fails ( chk ( rng_next g0 ) 7684712102626143532 `seed0[3]` )
    = fails + fails ( chk ( rng_next g0 ) -4925340083591827879 `seed0[4]` )
    ( rng_free g0 )

    // ── Exact stream, seed 0x1234 ───────────────────────────────────
    : Rng g1 ( rng_seed 0x1234 )
    = fails + fails ( chk ( rng_next g1 ) -3525385174084883479 `seed1[0]` )
    = fails + fails ( chk ( rng_next g1 ) -5997322183977983201 `seed1[1]` )
    = fails + fails ( chk ( rng_next g1 ) 1717958663746102582 `seed1[2]` )
    = fails + fails ( chk ( rng_next g1 ) -1912904096732430461 `seed1[3]` )
    = fails + fails ( chk ( rng_next g1 ) -7012801589984659952 `seed1[4]` )
    ( rng_free g1 )

    // ── Determinism: same seed → identical streams ──────────────────
    : Rng a ( rng_seed 42 )
    : Rng b ( rng_seed 42 )
    : ~ i k 0
    ~ < k 64 {
        = fails + fails ( chk ( rng_next a ) ( rng_next b ) `det` )
        = k + k 1
    }
    ( rng_free a )
    ( rng_free b )

    // ── rng_below: in-range + zero guard ────────────────────────────
    : Rng r ( rng_seed 7 )
    = k 0
    ~ < k 1000 {
        : i v ( rng_below r 6 )
        ? | < v 0 >= v 6 {
            = fails + fails 1
            ( nurl_print `FAIL rng_below out of [0,6)\n` )
        } {}
        = k + k 1
    }
    // n <= 0 → 0
    = fails + fails ( chk ( rng_below r 0 ) 0 `below0` )
    = fails + fails ( chk ( rng_below r -3 ) 0 `belowNeg` )

    // ── rng_range: inverted range returns `from` ────────────────────
    = fails + fails ( chk ( rng_range r 10 10 ) 10 `rangeEmpty` )
    = fails + fails ( chk ( rng_range r 10 5 ) 10 `rangeInverted` )
    // valid range stays in [100, 110)
    = k 0
    ~ < k 500 {
        : i v ( rng_range r 100 110 )
        ? | < v 100 >= v 110 {
            = fails + fails 1
            ( nurl_print `FAIL rng_range out of [100,110)\n` )
        } {}
        = k + k 1
    }
    ( rng_free r )

    ? == fails 0 {
        ( nurl_print `rng: all checks passed\n` )
        ^ 0
    } {
        ( nurl_print `rng: ` )
        ( nurl_print ( nurl_str_int fails ) )
        ( nurl_print ` checks FAILED\n` )
        ^ 1
    }
}
