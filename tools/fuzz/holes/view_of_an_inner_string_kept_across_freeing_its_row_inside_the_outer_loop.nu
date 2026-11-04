// view_of_an_inner_string_kept_across_freeing_its_row_inside_the_outer_loop: agora #471 — views of inner Strings collected by `~ e vv { ~ x e { … } ( vec_free e ) }`, the row freed through the outer element after its inner loop; the views are read after
// Closed: inside the outer loop the views still name the outer element, `^e`: freeing it ends them (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: views of a row's inner Strings, kept across freeing the row through the outer loop's element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `an inner string freed with its row` ) )
    ( vec_push [( Vec String )] vv r0 )
    : ( Vec s ) ws ( vec_new [s] )
    ~ e vv {
        ~ x e { ( vec_push [s] ws ( string_data x ) ) }
        ( vec_free [String] e )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
