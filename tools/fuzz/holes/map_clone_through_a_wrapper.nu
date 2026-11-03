// map_clone_through_a_wrapper: a wrapper handing back map_clone of its map of views.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #377: a wrapper handing back map_clone of its map of views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`

@ cpm ( HashMap i s ) m → ( HashMap i s ) { ^ ( map_clone [i s] m ) }

@ main → i {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }
    : ~ ( HashMap i s ) keep ( map_new [i s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( HashMap i s ) m ( map_new [i s] )
        : ?s old ( map_set [i s] m 1 ( string_data b ) hi ei )
        = keep ( cpm m )
    }
    ?? ( map_get [i s] keep 1 hi ei ) { T w → ( nurl_println w ) F → {} }
    ^ 0
}
