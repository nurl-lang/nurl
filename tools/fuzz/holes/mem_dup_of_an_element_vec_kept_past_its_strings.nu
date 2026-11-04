// mem_dup_of_an_element_vec_kept_past_its_strings: mem_dup of an element of a ( Vec ( Vec s ) ) kept past the strings it views.
// Closed: a copy of a part of an argument — an element or a field handle, a slice of it — holds what that part holds, not the storage it is in: the held evaluator reads a `retpart` argument as what it holds, a holder that borrows its value depends on what that value holds (its borrow ties it to the rest), and the type-class memo reads `-1` as "ask again" (__sym_vint).
// main 836c0e9: rejected, naming the outer Vec; now names the String the copy views.
// map: §2.13 | A2 | rejected | - | Family G review: mem_dup of an element of a ( Vec ( Vec s ) ) kept past the strings it views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    : ~ ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( vec_push [( Vec s )] vv t )
        = keep ( mem_dup ( vec_at [( Vec s )] vv 0 ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
