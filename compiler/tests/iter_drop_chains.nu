// iter_drop_chains.nu — lazy iterators (stdlib/std/iter.nu) release
// themselves: a chain dropped half consumed or never consumed frees every
// closure env and every cursor with it, with nothing released by hand.
// Each round builds map∘filter∘range, zip, chain, take of an
// effectively endless range, enumerate∘skip, from_vec and repeat chains,
// a chain returned by a function, one held in a struct field and one
// captured by another closure, advances some of them and drops them all;
// the live allocation count (nurl_alloc_count − nurl_free_count) must not
// grow from one round to the next.
//
// Also checked: copies of an iterator share its cursor and a consumer
// only borrows it (take a prefix, then go on with the rest — before, the
// consumer's cmd=1 freed the cursor under the second reader), and cmd=1
// is a plain "end" that every combinator passes upstream.

$ `stdlib/std/iter.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ first_i ( @ ?i i ) it → i {
    : ?i g ( it 0 )
    ?? g {
        T x → { ^ x }
        F → { ^ -1 }
    }
}

// A function that wraps a chain and hands it back.
@ evens_squared i n → ( @ ?i i ) {
    : ( @ i i ) sq \ i x → i { ^ * x x }
    : ( @ b i ) ev \ i x → b { ^ == 0 % x 2 }
    ^ ( iter_map [i i] ( iter_filter [i] ( iter_range 0 n ) ev ) sq )
}

: Holder {
    i tag
    ( @ ?i i ) it
}

@ round ( Vec i ) data → i {
    : ~ i acc 0
    : ( @ i i ) sq \ i x → i { ^ * x x }
    : ( @ b i ) ev \ i x → b { ^ == 0 % x 2 }
    : ( @ b i ) gt50 \ i x → b { ^ > x 50 }

    // map∘filter∘range: half consumed, and never consumed
    : ( @ ?i i ) a ( iter_map [i i] ( iter_filter [i] ( iter_range 0 100 ) ev ) sq )
    = acc + acc ( first_i a )
    = acc + acc ( first_i a )
    = acc + acc ( first_i a )
    : ( @ ?i i ) a2 ( iter_map [i i] ( iter_filter [i] ( iter_range 0 100 ) ev ) sq )

    // zip: never consumed, and one step taken
    : ( @ ?( Pair i i ) i ) z ( iter_zip [i i] ( iter_range 0 10 ) ( iter_range 5 50 ) )
    : ( @ ?( Pair i i ) i ) z2 ( iter_zip [i i] ( iter_range 0 10 ) ( iter_range_step 50 0 -5 ) )
    : ?( Pair i i ) zg ( z2 0 )
    ?? zg {
        T p → { = acc + acc + ( pair_first [i i] p ) ( pair_second [i i] p ) }
        F → {}
    }

    // chain: stopped inside its second half, and never consumed
    : ( @ ?i i ) c ( iter_chain [i] ( iter_range 0 3 ) ( iter_range_step 10 0 -1 ) )
    : ~ i k 0
    ~ < k 5 { = acc + acc ( first_i c ) = k + k 1 }
    : ( @ ?i i ) c2 ( iter_chain [i] ( iter_range 0 3 ) ( iter_range 7 9 ) )

    // take of an effectively endless range
    : ( @ ?i i ) t ( iter_take [i] ( iter_range 0 1000000000 ) 5 )
    = acc + acc ( first_i t )
    = acc + acc ( first_i t )

    // enumerate over skip, and over a borrowed Vec
    : ( @ ?( Pair i i ) i ) e ( iter_enumerate [i] ( iter_skip [i] ( iter_range 0 100 ) 3 ) )
    : ?( Pair i i ) eg ( e 0 )
    ?? eg {
        T p → { = acc + acc + ( pair_first [i i] p ) ( pair_second [i i] p ) }
        F → {}
    }
    : ( @ ?( Pair i i ) i ) e2 ( iter_enumerate [i] ( iter_from_vec [i] data ) )

    // from_vec and repeat
    : ( @ ?i i ) fv ( iter_filter [i] ( iter_from_vec [i] data ) gt50 )
    = acc + acc ( first_i fv )
    : ( @ ?i i ) rp ( iter_take [i] ( iter_repeat [i] 4 1000 ) 3 )
    = acc + acc ( first_i rp )

    // consumers over temporaries and over a binding that is used again
    = acc + acc ( iter_sum_i ( iter_map [i i] ( iter_filter [i] ( iter_range 0 20 ) ev ) sq ) )
    : ( Vec i ) col ( iter_collect [i] ( iter_chain [i] ( iter_range 0 3 ) ( iter_skip [i] ( iter_range 0 6 ) 4 ) ) )
    = acc + acc ( vec_len [i] col )
    : ( @ ?i i ) big ( iter_range 0 1000 )
    = acc + acc ? ( iter_any [i] big gt50 ) 1 0
    = acc + acc ( first_i big )
    : ?i fd ( iter_find [i] ( iter_range 0 100 ) gt50 )
    ?? fd {
        T x → { = acc + acc x }
        F → {}
    }
    = acc + acc ( iter_count [i] ( iter_take [i] ( iter_range 0 1000000000 ) 7 ) )

    // a chain built by a function
    : ( @ ?i i ) fe ( evens_squared 1000 )
    = acc + acc ( first_i fe )
    = acc + acc ( first_i fe )

    // an iterator in a struct field
    : Holder h @ Holder { 1 ( iter_take [i] ( iter_range 0 1000000 ) 10 ) }
    = acc + acc ( first_i . h it )

    // an iterator captured by another closure
    : ( @ ?i i ) inner ( iter_range 100 200 )
    = acc + acc ( first_i inner )
    : ( @ i i ) peek_more \ i d → i { ^ + d ( first_i inner ) }
    = acc + acc ( peek_more 1 )

    // the optional early release
    : ( @ ?i i ) early ( iter_map [i i] ( iter_range 0 50 ) sq )
    = acc + acc ( first_i early )
    ( iter_free [i] early )

    ^ acc
}

@ main → i {
    : ( Vec i ) data ( vec_new [i] )
    : ~ i j 0
    ~ < j 64 { ( vec_push [i] data * j 3 ) = j + j 1 }

    : ~ i r 0
    : ~ i base 0
    : ~ b steady T
    : ~ i chk 0
    ~ < r 20 {
        = chk ( round data )
        : i l ( live )
        ? == r 1 { = base l } {}
        ? & > r 1 != l base { = steady F } {}
        = r + r 1
    }
    ( nurl_print `checksum=` ) ( nurl_print ( nurl_str_int chk ) ) ( nurl_print `\n` )

    // a prefix through a consumer, then the rest from the same cursor
    : ( @ ?i i ) src ( iter_range 0 8 )
    : ( Vec i ) pre ( iter_collect [i] ( iter_take [i] src 3 ) )
    ( nurl_print `prefix_len=` ) ( nurl_print ( nurl_str_int ( vec_len [i] pre ) ) ) ( nurl_print `\n` )
    ( nurl_print `rest_sum=` ) ( nurl_print ( nurl_str_int ( iter_sum_i src ) ) ) ( nurl_print `\n` )

    // cmd=1 ends the chain it is sent to, upstream included
    : ( @ i i ) sq \ i x → i { ^ * x x }
    : ( @ ?i i ) up ( iter_range 0 10 )
    : ( @ ?i i ) m ( iter_map [i i] up sq )
    ( nurl_print `m=` ) ( nurl_print ( nurl_str_int ( first_i m ) ) ) ( nurl_print `\n` )
    ( m 1 )
    ( nurl_print `m_after_end=` ) ( nurl_print ( nurl_str_int ( first_i m ) ) ) ( nurl_print `\n` )
    ( nurl_print `upstream_after_end=` ) ( nurl_print ( nurl_str_int ( first_i up ) ) ) ( nurl_print `\n` )

    ( nurl_print ? steady `live allocations: steady\n` `live allocations: GROWING\n` )
    ^ 0
}
