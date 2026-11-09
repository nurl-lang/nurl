// closure_literal_as_vec_extends_holder_keeps_views_past_their_source: a closure literal `\ ( Vec s ) d ( Vec s ) t → v { ( vec_extend [s] d t ) }` called with an outer Vec and a block-local Vec of views of a block-local String; the outer Vec is read after the block.
// Closed: the closure literal's answer carries that its first parameter takes the second's views, as the named wrapper's does (agora #468). Refused on main 9e8d4a88.
// main d85806eb / 8a2afbc: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #468: a closure literal whose ( Vec s ) parameter is vec_extend's holder keeps views past their source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( @ v ( Vec s ) ( Vec s ) ) f \ ( Vec s ) d ( Vec s ) t → v { ( vec_extend [s] d t ) }
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( f ws t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
