// Test: iter_zip + iter_enumerate (lazy, auto-drop via cmd=1 cascade).
//
// Iterates manually with cmd=0 / cmd=1 because passing compound types
// like ( Pair i i ) through generic call type-args (`[A]`) and through
// closure param positions (`\ ( Pair i i ) p →`) currently requires
// extra parser plumbing — see ROADMAP. The iterator itself works
// fine; only the consumers (iter_each / iter_map / iter_count …) need
// a single-token type arg.

$ `stdlib/std/iter.nu`

@ main → i {
    // ── iter_zip equal lengths ──
    : ( @ ?( Pair i i ) i ) z1 ( iter_zip [i i] ( iter_range 0 4 ) ( iter_range 100 104 ) )
    ( nurl_print `zip_eq=` )
    : ~ b done F
    ~ ! done {
        : ?( Pair i i ) g ( z1 0 )
        ?? g {
            T p → {
                ( nurl_print `(` )
                ( nurl_print ( nurl_str_int ( pair_first [i i] p ) ) )
                ( nurl_print `,` )
                ( nurl_print ( nurl_str_int ( pair_second [i i] p ) ) )
                ( nurl_print `)` )
            }
            F → { = done T }
        }
    }
    ( z1 1 )
    ( nurl_print `\n` )

    // ── iter_zip stops on shorter side ──
    : ( @ ?( Pair i i ) i ) z2 ( iter_zip [i i] ( iter_range 0 100 ) ( iter_range 0 3 ) )
    : ~ i zcnt 0
    : ~ b zd F
    ~ ! zd {
        : ?( Pair i i ) g ( z2 0 )
        ?? g {
            T p → { = zcnt + zcnt 1 }
            F → { = zd T }
        }
    }
    ( z2 1 )
    ( nurl_print `zip_short_count=` ) ( nurl_print ( nurl_str_int zcnt ) ) ( nurl_print `\n` )

    // ── iter_enumerate over Vec[i] ──
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 10 )
    ( vec_push [i] src 20 )
    ( vec_push [i] src 30 )
    : ( @ ?( Pair i i ) i ) e1 ( iter_enumerate [i] ( iter_from_vec [i] src ) )
    ( nurl_print `enum=` )
    : ~ b ed F
    ~ ! ed {
        : ?( Pair i i ) g ( e1 0 )
        ?? g {
            T p → {
                ( nurl_print `[` )
                ( nurl_print ( nurl_str_int ( pair_first [i i] p ) ) )
                ( nurl_print `:` )
                ( nurl_print ( nurl_str_int ( pair_second [i i] p ) ) )
                ( nurl_print `]` )
            }
            F → { = ed T }
        }
    }
    ( e1 1 )
    ( nurl_print `\n` )
    ( vec_free [i] src )

    // ── pipeline: iter_zip → manual fold for dot-product-ish sum ──
    : ( @ ?( Pair i i ) i ) z3 ( iter_zip [i i] ( iter_range 1 6 ) ( iter_range 10 60 ) )
    : ~ i total 0
    : ~ b td F
    ~ ! td {
        : ?( Pair i i ) g ( z3 0 )
        ?? g {
            T p → { = total + total + ( pair_first [i i] p ) ( pair_second [i i] p ) }
            F → { = td T }
        }
    }
    ( z3 1 )
    ( nurl_print `dot_sum=` ) ( nurl_print ( nurl_str_int total ) ) ( nurl_print `\n` )

    // ── iter_enumerate of strings (alias semantics — borrowed s) ──
    : ( Vec s ) words ( vec_new [s] )
    ( vec_push [s] words `apple` )
    ( vec_push [s] words `banana` )
    ( vec_push [s] words `cherry` )
    : ( @ ?( Pair i s ) i ) we ( iter_enumerate [s] ( iter_from_vec [s] words ) )
    ( nurl_print `enum_str=` )
    : ~ b wd F
    ~ ! wd {
        : ?( Pair i s ) g ( we 0 )
        ?? g {
            T p → {
                ( nurl_print ( nurl_str_int ( pair_first [i s] p ) ) )
                ( nurl_print `=` )
                ( nurl_print ( pair_second [i s] p ) )
                ( nurl_print ` ` )
            }
            F → { = wd T }
        }
    }
    ( we 1 )
    ( nurl_print `\n` )
    ( vec_free [s] words )

    // ── iter_enumerate abandon mid-stream (manual iter_free cascades) ──
    : ( @ ?( Pair i i ) i ) ab ( iter_enumerate [i] ( iter_range 0 1000000 ) )
    : ?( Pair i i ) a1 ( ab 0 )
    ?? a1 {
        T p → {
            ( nurl_print `abandon_first=` )
            ( nurl_print ( nurl_str_int ( pair_first [i i] p ) ) )
            ( nurl_print `,` )
            ( nurl_print ( nurl_str_int ( pair_second [i i] p ) ) )
            ( nurl_print `\n` )
        }
        F → {}
    }
    ( ab 1 )

    ( nurl_print `done\n` )
    ^ 0
}
