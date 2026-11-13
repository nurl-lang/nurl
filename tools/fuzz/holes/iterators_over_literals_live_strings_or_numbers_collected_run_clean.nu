// iterators_over_literals_live_strings_or_numbers_collected_run_clean: iterators over a Vec of literals, over a Vec of views of a String that outlives them, and over numbers, collected and read
// Guard for agora #472's fix: an iterator's results hold what it holds, and nothing ends before them here.
// main ff75baea: accepted, clean.
// map: §2.2 | A2 | runs-clean | - | agora #472 guard: iterators whose results outlive nothing they view
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t `a literal` )
        = keep ( iter_collect [s] ( iter_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    : String b ( string_from `a String that outlives the iterator` )
    : ( Vec s ) t2 ( vec_new [s] )
    ( vec_push [s] t2 ( string_data b ) )
    : ( Vec s ) k2 ( iter_collect [s] ( iter_from_vec [s] t2 ) )
    ( nurl_println ( vec_at [s] k2 0 ) )
    : ( Vec i ) ns ( iter_collect [i] ( iter_map [i i] ( iter_range 0 5 ) \ i x → i { ^ * x x } ) )
    ( nurl_println_int ( vec_len [i] ns ) )
    ^ 0
}
