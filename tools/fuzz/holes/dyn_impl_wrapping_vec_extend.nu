// dyn_impl_wrapping_vec_extend: a dyn impl over vec_extend, its holder argument 1.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #377: a dyn impl over vec_extend, its holder argument 1
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Ext [T] { @ ext T self inout ( Vec s ) d ( Vec s ) t → v }

: E1 { i k }

% Ext E1 { @ ext E1 e inout ( Vec s ) d ( Vec s ) t → v { ( vec_extend [s] d t ) } }

@ main → i {
    : %Ext e ( dyn Ext @ E1 { 1 } )
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( ext e ws t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
