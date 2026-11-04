// view_of_an_element_of_a_loop_element_kept_past_the_container: agora #471 — `~ row vv { : String e ( vec_at [String] row 0 ) ( vec_push [s] ws ( string_data e ) ) }`; `vv` ends; `ws` read after
// Closed: a borrow of a loop element borrows what the loop iterates too (bck_borrow_owners: `fe_`), as a borrow of a `vec_at` binding does (agora #471).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of an element read out of a loop element with vec_at, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
        : ( Vec String ) r0 ( vec_new [String] )
        ( vec_push [String] r0 ( string_from `an inner string freed with the outer Vec` ) )
        ( vec_push [( Vec String )] vv r0 )
        ~ row vv {
            : String e ( vec_at [String] row 0 )
            ( vec_push [s] ws ( string_data e ) )
        }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
