// borrow_wrapped_lending_call.nu — a binding whose lending call runs over
// several lines (`: S e ( vec_at [S]` / `a` / `0 )`) borrows from the
// call's argument, as the one-line call does: clearing the source and
// then reading the binding is refused (Agora #678). The pending lend was
// matched to the binding by the line its argument was read on, which a
// wrapped call's binding never carries, so the program compiled and read
// freed memory.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a-long-enough-name-to-live-on-the-heap-000` ) 1 } )
    : S e ( vec_at [S]
    a
    0 )
    ( vec_clear [S] a )
    ( nurl_print ( string_data . e name ) )
    ^ 0
}
