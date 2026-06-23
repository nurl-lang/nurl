// chart — terminal data-visualisation for NURL.
//
// Turn a list of numbers into something you can actually see in a
// terminal: a one-line sparkline, a labelled horizontal bar chart, a
// histogram, or a line/scatter plot drawn on a character grid. Every
// renderer returns an owned `String` (the caller frees it with
// `string_free`), uses only Unicode that any modern terminal renders, and
// allocates nothing it does not free — leak-clean under ASan/LSan.
//
// This package lives in the NURL registry, NOT the core stdlib: charting
// is opinionated (which glyphs, which scaling, which layout) in a way the
// language proper should stay out of, but it is exactly the kind of
// everyday utility a package ecosystem exists to provide. It is pure
// NURL — no FFI — and depends only on the shipped stdlib (vec, string,
// float), so it builds and behaves identically on every platform.
//
// Surface
//   ( chart_sparkline values )                 → String   ▁▂▃▄▅▆▇█ one-liner
//   ( chart_bars labels values width )         → String   labelled h-bars
//   ( chart_hist values bins width )           → String   binned histogram
//   ( chart_plot values width height )         → String   line/scatter grid
//   ( chart_min values ) / _max / _sum / _mean → f        summary stats
//
// `values` is a ( Vec f ); `labels` is a ( Vec String ) (borrowed, never
// freed or retained). `width`/`height` are in terminal cells. Bars and
// histograms assume non-negative values (the natural shape for a bar
// chart); a negative value contributes an empty bar. The plot handles any
// range, including negatives.
//
// The block glyphs give sub-cell precision: a bar is drawn in whole
// "full block" cells plus one partial left-block for the final eighth, so
// a value of 3.5 units at 1 cell/unit reads as three full cells and a
// half cell — far smoother than rounding to whole characters.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

// ── UTF-8 glyph helpers ───────────────────────────────────────────────
//
// Every glyph we draw is a 3-byte UTF-8 sequence in the U+25xx / U+20xx
// blocks, so one helper covers them all. NURL strings are byte strings;
// `string_push_char` appends a single byte, and we hand-assemble the
// three bytes of each code point.

@ __push3 String out i a i b i c → v {
    ( string_push_char out a )
    ( string_push_char out b )
    ( string_push_char out c )
}

// Vertical block of `lvl` eighths, 1..8 → ▁▂▃▄▅▆▇█ (U+2581..U+2588).
@ __push_vblock String out i lvl → v { ( __push3 out 226 150 + 128 lvl ) }

// Full block █ (U+2588), one whole cell of a horizontal bar.
@ __push_hfull String out → v { ( __push3 out 226 150 136 ) }

// Partial left block of `k` eighths, 1..7 → ▏▎▍▌▋▊▉ (U+258F..U+2589).
@ __push_hpartial String out i k → v { ( __push3 out 226 150 - 144 k ) }

// Bullet • (U+2022), the plot's data mark.
@ __push_dot String out → v { ( __push3 out 226 128 162 ) }

// ── Summary statistics ────────────────────────────────────────────────
//
// Small, exported because charts need them and callers usually want them
// too. An empty series has no meaningful min/max/mean; we return 0.0
// rather than trap, so a renderer fed empty input yields an empty string
// instead of crashing.

@ chart_min ( Vec f ) v → f {
    : i n ( vec_len [f] v )
    ? == n 0 { ^ 0.0 } {}
    : *f dp ( vec_data [f] v )
    : ~ f m . dp 0
    : ~ i i 1
    ~ < i n { : f x . dp i ? < x m { = m x } {} = i + i 1 }
    ^ m
}

@ chart_max ( Vec f ) v → f {
    : i n ( vec_len [f] v )
    ? == n 0 { ^ 0.0 } {}
    : *f dp ( vec_data [f] v )
    : ~ f m . dp 0
    : ~ i i 1
    ~ < i n { : f x . dp i ? > x m { = m x } {} = i + i 1 }
    ^ m
}

@ chart_sum ( Vec f ) v → f {
    : i n ( vec_len [f] v )
    : *f dp ( vec_data [f] v )
    : ~ f s 0.0
    : ~ i i 0
    ~ < i n { = s + s . dp i = i + i 1 }
    ^ s
}

@ chart_mean ( Vec f ) v → f {
    : i n ( vec_len [f] v )
    ? == n 0 { ^ 0.0 } {}
    ^ / ( chart_sum v ) # f n
}

// ── Sparkline ─────────────────────────────────────────────────────────
//
// One glyph per value, each mapped onto the eight block heights between
// the series min and max. A flat series (range 0) draws as a mid-height
// baseline rather than dividing by zero.

@ chart_sparkline ( Vec f ) v → String {
    : i n ( vec_len [f] v )
    : String out ( string_with_cap * n 3 )
    ? == n 0 { ^ out } {}
    : *f dp ( vec_data [f] v )
    : f mn ( chart_min v )
    : f mx ( chart_max v )
    : f range - mx mn
    : ~ i i 0
    ~ < i n {
        : f x . dp i
        : ~ i lvl 4
        ? > range 0.0 { = lvl + 1 # i ( float_round * 7.0 / - x mn range ) } {}
        ? < lvl 1 { = lvl 1 } {}
        ? > lvl 8 { = lvl 8 } {}
        ( __push_vblock out lvl )
        = i + i 1
    }
    ^ out
}

// ── Labels (for bars / histograms) ────────────────────────────────────
//
// `labels` is borrowed: we read a label's bytes but never free it or keep
// a reference, so the caller's Vec stays the sole owner.

@ __label_len ( Vec String ) labels i idx → i {
    ?? ( vec_get [String] labels idx ) {
        T s → { ^ ( string_len s ) }
        F _ → { ^ 0 }
    }
}

// Append label `idx` left-justified into a `lw`-wide column (truncated if
// longer, space-padded if shorter).
@ __push_label String out ( Vec String ) labels i idx i lw → v {
    : ~ i printed 0
    ?? ( vec_get [String] labels idx ) {
        T s → {
            : s raw ( string_data s )
            : i sl ( string_len s )
            : i take ? > sl lw lw sl
            : ~ i k 0
            ~ < k take { ( string_push_char out ( nurl_str_get raw k ) ) = k + k 1 }
            = printed take
        }
        F _ → {}
    }
    : ~ i p printed
    ~ < p lw { ( string_push_char out 32 ) = p + p 1 }
}

// ── Horizontal bar chart ──────────────────────────────────────────────
//
//   apples   ████████▌ 8.5
//   pears    ██████ 6
//   cherries ██▏ 2.1
//
// The longest value fills `width` cells; everything else scales linearly.
// Sub-cell precision comes from the partial left-blocks (eighths). Each
// row is `<label> <bar> <value>`; the value is printed with %g so whole
// numbers stay whole.

@ chart_bars ( Vec String ) labels ( Vec f ) values i width → String {
    : i n ( vec_len [f] values )
    : String out ( string_new )
    ? == n 0 { ^ out } {}
    : ~ i w width
    ? < w 1 { = w 1 } {}

    // Label column width, capped so one long label can't blow out the row.
    : ~ i lw 0
    : ~ i i 0
    ~ < i n {
        : i ll ( __label_len labels i )
        ? > ll lw { = lw ll } {}
        = i + i 1
    }
    ? > lw 24 { = lw 24 } {}

    // Eighths-per-unit so the max value maps to exactly `w` full cells.
    : f mx ( chart_max values )
    : ~ f scale 0.0
    ? > mx 0.0 { = scale / # f * w 8 mx } {}

    : *f dp ( vec_data [f] values )
    = i 0
    ~ < i n {
        ( __push_label out labels i lw )
        ( string_push_char out 32 )
        : f x . dp i
        : ~ i eighths 0
        ? > x 0.0 { = eighths # i ( float_round * x scale ) } {}
        ? < eighths 0 { = eighths 0 } {}
        : i full / eighths 8
        : i rem - eighths * full 8
        : ~ i c 0
        ~ < c full { ( __push_hfull out ) = c + c 1 }
        ? > rem 0 { ( __push_hpartial out rem ) } {}
        ( string_push_char out 32 )
        ( string_push_float out x )
        ( string_push_char out 10 )
        = i + i 1
    }
    ^ out
}

// ── Histogram ─────────────────────────────────────────────────────────
//
// Bin `values` into `bins` equal-width buckets over [min, max] and draw
// the counts as a bar chart, one row per bucket labelled with its range.
// Built on top of `chart_bars`, so it inherits the sub-cell bars.

@ __push_range_label String dst f lo f hi → v {
    ( string_push_char dst 91 )         // [
    ( string_push_float dst lo )
    ( string_push_str dst `, ` )
    ( string_push_float dst hi )
    ( string_push_char dst 41 )         // )
}

@ chart_hist ( Vec f ) values i bins i width → String {
    : i n ( vec_len [f] values )
    : String out ( string_new )
    ? == n 0 { ^ out } {}
    : ~ i nb bins
    ? < nb 1 { = nb 1 } {}

    : f mn ( chart_min values )
    : f mx ( chart_max values )
    : f range - mx mn

    : ( Vec f ) counts ( vec_with_cap [f] nb )
    : ~ i b 0
    ~ < b nb { ( vec_push [f] counts 0.0 ) = b + b 1 }

    : *f dp ( vec_data [f] values )
    : ~ i i 0
    ~ < i n {
        : f x . dp i
        : ~ i bi 0
        ? > range 0.0 { = bi # i ( float_floor * # f nb / - x mn range ) } {}
        ? < bi 0 { = bi 0 } {}
        ? >= bi nb { = bi - nb 1 } {}
        ?? ( vec_get [f] counts bi ) {
            T cur → { ( vec_set [f] counts bi + cur 1.0 ) }
            F _ → {}
        }
        = i + i 1
    }

    // Build the per-bucket range labels.
    : f span ? > range 0.0 / range # f nb 0.0
    : ( Vec String ) labels ( vec_with_cap [String] nb )
    = b 0
    ~ < b nb {
        : f lo + mn * span # f b
        : f hi + mn * span # f + b 1
        : String lbl ( string_new )
        ( __push_range_label lbl lo hi )
        ( vec_push [String] labels lbl )
        = b + b 1
    }

    : String body ( chart_bars labels counts width )
    ( string_push_str out ( string_data body ) )
    ( string_free body )
    ( vec_free_with [String] labels \ String s → v { ( string_free s ) } )
    ( vec_free [f] counts )
    ^ out
}

// ── Line / scatter plot ───────────────────────────────────────────────
//
//   8.5 |        •
//       |    •••• ••
//       |  ••       •
//     2 |••
//
// The series is resampled to `width` columns; each column's value maps to
// a row (top = max, bottom = min). Consecutive samples are joined
// vertically so the result reads as a connected line. A y-axis gutter
// labels the max (top row) and min (bottom row).

@ __push_spaces String out i k → v {
    : ~ i i 0
    ~ < i k { ( string_push_char out 32 ) = i + i 1 }
}

// Right-justify `raw` into a `gw`-wide field.
@ __push_rjust String out s raw i gw → v {
    : i l ( nurl_str_len raw )
    ? < l gw { ( __push_spaces out - gw l ) } {}
    ( string_push_str out raw )
}

@ chart_plot ( Vec f ) values i width i height → String {
    : i n ( vec_len [f] values )
    : String out ( string_new )
    ? | < n 1 | < width 1 < height 1 { ^ out } {}

    : f mn ( chart_min values )
    : f mx ( chart_max values )
    : f range - mx mn
    : *f dp ( vec_data [f] values )

    // Character grid, row-major, 0 = blank / 1 = mark.
    : i cells * width height
    : ( Vec i ) grid ( vec_with_cap [i] cells )
    : ~ i g 0
    ~ < g cells { ( vec_push [i] grid 0 ) = g + g 1 }

    // For each column: resample, map to a row, then connect to the
    // previous column's row so the marks form a line.
    : ~ i prev -1
    : ~ i c 0
    ~ < c width {
        : ~ i si 0
        ? > width 1 { = si # i ( float_round / # f * c - n 1 # f - width 1 ) } {}
        ? < si 0 { = si 0 } {}
        ? >= si n { = si - n 1 } {}
        : f val . dp si
        : ~ i row / - height 1 2
        ? > range 0.0 { = row # i ( float_round * # f - height 1 / - mx val range ) } {}
        ? < row 0 { = row 0 } {}
        ? >= row height { = row - height 1 } {}

        : ~ i r0 row
        : ~ i r1 row
        ? >= prev 0 {
            ? < prev row { = r0 prev } { = r1 prev }
        } {}
        : ~ i rr r0
        ~ <= rr r1 { ( vec_set [i] grid + * rr width c 1 ) = rr + rr 1 }
        = prev row
        = c + c 1
    }

    // Y-axis gutter labelled with max (top) and min (bottom).
    : s mxs ( float_to_string mx )
    : s mns ( float_to_string mn )
    : i gw ? > ( nurl_str_len mxs ) ( nurl_str_len mns ) ( nurl_str_len mxs ) ( nurl_str_len mns )

    : ~ i rr 0
    ~ < rr height {
        ? == rr 0 { ( __push_rjust out mxs gw ) } {
            ? == rr - height 1 { ( __push_rjust out mns gw ) } { ( __push_spaces out gw ) }
        }
        ( string_push_str out ` |` )
        : ~ i cc 0
        ~ < cc width {
            ?? ( vec_get [i] grid + * rr width cc ) {
                T v → { ? == v 1 { ( __push_dot out ) } { ( string_push_char out 32 ) } }
                F _ → { ( string_push_char out 32 ) }
            }
            = cc + cc 1
        }
        ( string_push_char out 10 )
        = rr + rr 1
    }

    ( vec_free [i] grid )
    ^ out
}
