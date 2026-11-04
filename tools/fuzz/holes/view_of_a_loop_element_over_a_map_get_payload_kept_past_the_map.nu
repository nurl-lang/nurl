// view_of_a_loop_element_over_a_map_get_payload_kept_past_the_map: agora #471 — `~ x . ( map_get [i ( Vec String )] m 1 hi ei ) 1` pushes views of `x` into `ws`; the map ends at its block's end and `ws` is read after
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element over a map_get payload, kept past the map
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`

@ main → i {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( HashMap i ( Vec String ) ) m ( map_new [i ( Vec String )] )
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string in a map value, freed with the map` ) )
        : ?( Vec String ) old ( map_set [i ( Vec String )] m 1 t hi ei )
        ~ x . ( map_get [i ( Vec String )] m 1 hi ei ) 1 { ( vec_push [s] ws ( string_data x ) ) }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
