// map_get_payload_cloned_past_the_map_runs_clean: vec_clone of a ( Vec s ) value matched out of map_get, kept past the map; the text lives.
// Kept: a match payload a call lends — an element read out of a Vec, a map's value — is tied to that call's lent arguments by its borrow, and holds besides what a copy of the scrutinee holds.
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | Family G review: vec_clone of a ( Vec s ) value matched out of map_get, kept past the map; the text lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`

@ main → i {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }
    : String text ( string_from `hello world, long enough for a heap buffer` )
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( HashMap i ( Vec s ) ) m ( map_new [i ( Vec s )] )
        : ( Vec s ) ws ( vec_new [s] )
        ( vec_push [s] ws ( string_data text ) )
        : ?( Vec s ) old ( map_set [i ( Vec s )] m 1 ws hi ei )
        ?? ( map_get [i ( Vec s )] m 1 hi ei ) { T v → { = keep ( vec_clone [s] v ) } F → {} }
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
