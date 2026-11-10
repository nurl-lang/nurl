// inner_loop_elements_freed_then_the_outer_loop_goes_on_runs_clean: agora #490 — `~ row rows { ~ x row { ( string_free x ) } … }`: the outer loop goes on to its next row
// Control for agora #490: moving a loop's element out is refused nowhere; only a borrow of the container's elements read after it is.
// map: §2.5 | A2 | runs-clean | - | agora #490: `~ row rows { ~ x row { ( string_free x ) } … }`: the outer loop goes on to its next row
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) rows ( vec_new [( Vec String )] )
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `an inner string, long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] rows r )
    : ( Vec String ) r2 ( vec_new [String] )
    ( vec_push [String] r2 ( string_from `another inner string, long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] rows r2 )
    ~ row rows { ~ x row { ( string_free x ) } ( nurl_println ( nurl_str_int ( vec_len [String] row ) ) ) }
    ^ 0
}
